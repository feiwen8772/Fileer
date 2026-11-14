import AppKit

/// A virtual destination: no Finder launch and no synthetic file selection.
final class SystemLocationViewController: NSViewController, @preconcurrency NetServiceBrowserDelegate,
    @preconcurrency NetServiceDelegate, NSSharingServiceDelegate {
    let location: SidebarSystemLocation
    var onOpen: ((URL) -> Void)?
    var onConnect: (() -> Void)?
    private let discoveryEnabled: Bool
    private let mounts: ServerMountSession
    private let content = NSStackView()
    private let devices = NSStackView()
    private let message = NSTextField(wrappingLabelWithString: "")
    private var browsers: [NetServiceBrowser] = []
    private var services: [NetService] = []
    private var resolving: NetService?
    private var panel: NSOpenPanel?
    private var sharing: NSSharingService?
    private(set) var stopped = false

    init(location: SidebarSystemLocation, discoveryEnabled: Bool = true,
         mounts: ServerMountSession) {
        self.location = location
        self.discoveryEnabled = discoveryEnabled
        self.mounts = mounts
        super.init(nibName: nil, bundle: nil)
    }

    isolated deinit { stop() }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        ThemeStyle.bind(root, to: .content)
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 20
        content.translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: location.symbol, accessibilityDescription: location.title)
        icon.symbolConfiguration = .init(pointSize: 56, weight: .regular)
        let title = NSTextField(labelWithString: location.title)
        title.font = .systemFont(ofSize: 26, weight: .semibold)
        message.alignment = .center
        message.textColor = .secondaryLabelColor
        message.preferredMaxLayoutWidth = 480
        message.stringValue = location == .network
            ? String(localized: "Discover shared computers on your local network, or connect to a server.")
            : String(localized: "Choose files or folders, then select a nearby recipient in the system AirDrop panel.")
        let button = NSButton(title: location == .network ? String(localized: "Connect to Server…") : String(localized: "Choose Files…"),
                              target: self, action: #selector(primaryAction))
        button.bezelStyle = .rounded
        devices.orientation = .vertical
        devices.alignment = .leading
        devices.spacing = 8
        for child in [icon, title, message, button, devices] { content.addArrangedSubview(child) }
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let document = NSView()
        scroll.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor), scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 40),
            content.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            content.widthAnchor.constraint(lessThanOrEqualTo: document.widthAnchor, constant: -48),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -40),
            icon.heightAnchor.constraint(equalToConstant: 72)
        ])
        view = root
    }

    func start() {
        guard location == .network, discoveryEnabled, browsers.isEmpty, !stopped else { return }
        for type in ["_smb._tcp.", "_afpovertcp._tcp."] {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browsers.append(browser)
            browser.searchForServices(ofType: type, inDomain: "local.")
        }
    }

    func stop() {
        stopped = true
        onOpen = nil
        onConnect = nil
        panel?.cancel(nil)
        panel = nil
        mounts.cancel()
        for browser in browsers { browser.delegate = nil; browser.stop() }
        for service in services { service.delegate = nil; service.stop() }
        browsers.removeAll()
        services.removeAll()
        resolving = nil
        sharing?.delegate = nil
        sharing = nil
    }

    @objc private func primaryAction() {
        guard !stopped else { return }
        if location == .network { onConnect?(); return }
        guard let window = view.window, panel == nil else { return }
        let chooser = NSOpenPanel()
        chooser.canChooseFiles = true
        chooser.canChooseDirectories = true
        chooser.allowsMultipleSelection = true
        panel = chooser
        chooser.beginSheetModal(for: window) { [weak self, weak chooser] response in
            guard let self, !stopped, let chooser, panel === chooser else { return }
            panel = nil
            guard response == .OK, !chooser.urls.isEmpty else { return }
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: chooser.urls) else { return }
            sharing = service
            service.delegate = self
            service.perform(withItems: chooser.urls)
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard !stopped, browsers.contains(where: { $0 === browser }), !services.contains(service) else { return }
        services.append(service)
        rebuildDevices()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        guard !stopped, browsers.contains(where: { $0 === browser }) else { return }
        if resolving === service { resolving = nil; mounts.cancel() }
        service.delegate = nil
        service.stop()
        services.removeAll { $0 == service }
        rebuildDevices()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        guard !stopped, browsers.contains(where: { $0 === browser }) else { return }
        message.stringValue = String(localized: "Network discovery is unavailable. You can still connect to a server by address.")
    }

    private func rebuildDevices() {
        for child in devices.arrangedSubviews { devices.removeArrangedSubview(child); child.removeFromSuperview() }
        for (index, service) in services.enumerated() {
            let button = NSButton(title: service.name, target: self, action: #selector(connectDevice(_:)))
            button.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.bezelStyle = .rounded
            button.tag = index
            devices.addArrangedSubview(button)
        }
    }

    @objc private func connectDevice(_ sender: NSButton) {
        guard !stopped, services.indices.contains(sender.tag) else { return }
        resolving?.stop()
        mounts.cancel()
        let service = services[sender.tag]
        resolving = service
        service.delegate = self
        service.resolve(withTimeout: 10)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard !stopped, resolving === sender, let host = sender.hostName else { return }
        resolving = nil
        var address = URLComponents()
        address.scheme = sender.type == "_smb._tcp." ? "smb" : "afp"
        address.host = host
        address.port = sender.port
        guard let url = address.url else { return }
        mounts.connect(url) { [weak self] result in
            guard let self, !stopped, let result else { return }
            switch result {
            case .success(let url): onOpen?(url)
            case .failure: message.stringValue = String(localized: "Couldn’t connect to the server.")
            }
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        guard !stopped, resolving === sender else { return }
        resolving = nil
        message.stringValue = String(localized: "Couldn’t connect to the server.")
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { sharing = nil }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        guard !stopped, sharing === sharingService else { return }
        message.stringValue = error.localizedDescription
        sharing = nil
    }
}

extension PaneHostViewController {
    func showSystemPage(_ page: SystemLocationViewController) {
        closeSystemPage()
        systemPage = page
        addChild(page)
        page.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(page.view)
        NSLayoutConstraint.activate([
            page.view.leadingAnchor.constraint(equalTo: browser.view.leadingAnchor),
            page.view.trailingAnchor.constraint(equalTo: browser.view.trailingAnchor),
            page.view.topAnchor.constraint(equalTo: browser.view.topAnchor),
            page.view.bottomAnchor.constraint(equalTo: browser.view.bottomAnchor)
        ])
        browser.view.isHidden = true
        page.start()
    }

    func closeSystemPage() {
        systemPage?.stop()
        systemPage?.view.removeFromSuperview()
        systemPage?.removeFromParent()
        systemPage = nil
        if isViewLoaded { browser.view.isHidden = false }
    }
}
