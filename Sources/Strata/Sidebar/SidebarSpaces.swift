import AppKit

extension Notification.Name {
    static let sidebarSpacesChanged = Self("StrataSidebarSpacesChanged")
}

nonisolated struct SidebarSpaceGroup: Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var urls: [URL] = []
}

nonisolated struct SidebarSpace: Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var groups: [SidebarSpaceGroup] = []
    var pinned: [URL] = []
    // Kept for decoding older records; visible favorites use the shared Places store.
    var favorites: [URL] = []
    var favoritesSeeded: Bool? = nil
}

final class SidebarSpaces {
    let preferences: Prefs
    private(set) var all: [SidebarSpace]
    init(preferences: Prefs) {
        self.preferences = preferences
        all = preferences.defaults.data(forKey: "sidebarSpaces.v1")
            .flatMap { try? JSONDecoder().decode([SidebarSpace].self, from: $0) } ?? []
    }
    func space(_ id: UUID?) -> SidebarSpace? { all.first { $0.id == id } }
    @discardableResult func create(_ name: String) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, all.count < 100 else { return nil }
        let space = SidebarSpace(name: name)
        all.append(space); save(); return space.id
    }
    func update(_ id: UUID, _ change: (inout SidebarSpace) -> Void) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        var value = all[index]; change(&value)
        guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.groups.count <= 100, value.groups.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }
        all[index] = value; save()
    }
    func remove(_ id: UUID) { all.removeAll { $0.id == id }; save() }
    func pin(_ urls: [URL], in id: UUID, section: String) {
        let urls = urls.filter { $0.isFileURL || ["https", "http"].contains($0.scheme ?? "") }
        update(id) { space in
            func append(_ items: inout [URL]) {
                for url in urls where !items.contains(url) && items.count < 5000 { items.append(url) }
            }
            if section == "spacePinned" { append(&space.pinned) }
            else if let index = space.groups.firstIndex(where: { $0.id.uuidString == section }) { append(&space.groups[index].urls) }
        }
    }
    static func dropOperation(for mask: NSDragOperation) -> NSDragOperation {
        if mask.contains(.link) { return .link }
        if mask.contains(.copy) { return .copy }
        if mask.contains(.generic) { return .generic }
        return []
    }
    func placeReference(_ url: URL, in id: UUID, section: String, at index: Int) {
        update(id) { space in
            func place(_ urls: inout [URL]) {
                func key(_ value: URL) -> String { value.isFileURL ? value.lexicallyStandardized.path : value.absoluteString }
                let existing = urls.first { key($0) == key(url) }
                urls.removeAll { key($0) == key(url) }
                urls.insert(existing ?? url, at: max(0, min(index, urls.count)))
            }
            if section == "spacePinned" { place(&space.pinned) }
            else if let group = space.groups.firstIndex(where: { $0.id.uuidString == section }) { place(&space.groups[group].urls) }
        }
    }
    func createGroup(_ name: String, in id: UUID) {
        guard space(id) != nil else { return }
        let group = SidebarSpaceGroup(name: name)
        let key = "sidebarSections." + id.uuidString + ".order"
        let order = preferences.defaults.stringArray(forKey: key) ?? []
        preferences.defaults.set([group.id.uuidString] + order, forKey: key)
        update(id) { $0.groups.insert(group, at: 0) }
    }
    private func save() {
        guard let data = try? JSONEncoder().encode(all) else { return }
        preferences.defaults.set(data, forKey: "sidebarSpaces.v1")
        preferences.notifications.post(name: .sidebarSpacesChanged, object: self)
    }
}

extension SidebarViewController {
    var activeSpace: SidebarSpace? { services.sidebarSpaces.space(activeSpaceID) }

    func installSpaceControls(in container: NSView) {
        spaceTitle.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(spaceTitle)
        let titleHeight = spaceTitle.heightAnchor.constraint(equalToConstant: 0)
        spaceTitleHeight = titleHeight
        NSLayoutConstraint.activate([
            spaceTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            spaceTitle.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            spaceTitle.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor), titleHeight,
        ])
        spaceTitle.addCategory.target = self
        spaceTitle.addCategory.action = #selector(newCategoryFromTitle(_:))
        spaceTitle.onMenu = { [weak self] in self?.spaceTitleMenu() }
        let menu = NSButton(image: NSImage(systemSymbolName: "keyboard", accessibilityDescription: String(localized: "Keyboard Shortcuts")) ?? NSImage(), target: nil, action: #selector(AppDelegate.showShortcuts(_:)))
        menu.title = ""
        menu.imagePosition = .imageOnly
        menu.toolTip = String(localized: "Every shortcut in Fileer (⌘/)")
        let add = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: nil) ?? NSImage(),
                           target: self, action: #selector(newSidebarSpace(_:)))
        for button in [menu, add] {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.symbolConfiguration = .init(pointSize: 14, weight: .regular)
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        menu.isBordered = false; add.isBordered = false
        add.toolTip = String(localized: "New Sidebar Space…")
        add.setAccessibilityLabel(add.toolTip)
        spaceDots.orientation = .horizontal
        spaceDots.alignment = .centerY
        spaceDots.distribution = .fillEqually
        spaceDots.spacing = 0
        spaceDotsScroll.documentView = spaceDots
        spaceDotsScroll.drawsBackground = false
        spaceDotsScroll.hasHorizontalScroller = false
        spaceDotsScroll.hasVerticalScroller = false
        spaceDotsScroll.automaticallyAdjustsContentInsets = false
        spaceFooter.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(spaceFooter)
        for child in [menu, spaceDotsScroll, add] { child.translatesAutoresizingMaskIntoConstraints = false; spaceFooter.addSubview(child) }
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        spaceFooter.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: spaceFooter.topAnchor),
            separator.leadingAnchor.constraint(equalTo: spaceFooter.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: spaceFooter.trailingAnchor),
        ])
        let width = spaceDotsScroll.widthAnchor.constraint(equalToConstant: 16)
        width.priority = .defaultLow
        spaceDotsWidth = width
        NSLayoutConstraint.activate([
            spaceFooter.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            spaceFooter.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            spaceFooter.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor),
            spaceFooter.heightAnchor.constraint(equalToConstant: 36),
            menu.leadingAnchor.constraint(equalTo: spaceFooter.leadingAnchor, constant: 8),
            menu.centerYAnchor.constraint(equalTo: spaceFooter.centerYAnchor), menu.widthAnchor.constraint(equalToConstant: 24),
            add.trailingAnchor.constraint(equalTo: spaceFooter.trailingAnchor, constant: -8),
            add.centerYAnchor.constraint(equalTo: spaceFooter.centerYAnchor), add.widthAnchor.constraint(equalToConstant: 24),
            spaceDotsScroll.centerXAnchor.constraint(equalTo: spaceFooter.centerXAnchor),
            spaceDotsScroll.centerYAnchor.constraint(equalTo: spaceFooter.centerYAnchor),
            spaceDotsScroll.leadingAnchor.constraint(greaterThanOrEqualTo: menu.trailingAnchor, constant: 6),
            spaceDotsScroll.trailingAnchor.constraint(lessThanOrEqualTo: add.leadingAnchor, constant: -6),
            spaceDotsScroll.heightAnchor.constraint(equalToConstant: 28), width,
        ])
        preferences.notifications.addObserver(self, selector: #selector(spacesChanged), name: .sidebarSpacesChanged, object: services.sidebarSpaces)
        refreshSpaceControls()
    }

    func refreshSpaceControls() {
        if activeSpaceID != nil && activeSpace == nil { activeSpaceID = nil }
        spaceTitle.isHidden = activeSpace == nil
        spaceTitleHeight?.constant = activeSpace == nil ? 0 : 38
        spaceTitle.label.stringValue = activeSpace?.name ?? ""
        spaceTitle.toolTip = activeSpace?.name
        let spaces = services.sidebarSpaces.all
        let names = [String(localized: "Default Space")] + spaces.map(\.name)
        let identifiers = ["default"] + spaces.map { $0.id.uuidString }
        let selected = activeSpaceID.flatMap { id in spaces.firstIndex { $0.id == id }.map { $0 + 1 } } ?? 0
        if spaceDots.arrangedSubviews.map({ $0.identifier?.rawValue }) != identifiers.map(Optional.some) {
            for child in spaceDots.arrangedSubviews { spaceDots.removeArrangedSubview(child); child.removeFromSuperview() }
            for (index, identifier) in identifiers.enumerated() {
                let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil) ?? NSImage()
                let dot = NSButton(image: image, target: self, action: #selector(spacePicked(_:)))
                dot.imagePosition = .imageOnly
                dot.isBordered = false
                dot.tag = index
                dot.identifier = NSUserInterfaceItemIdentifier(identifier)
                spaceDots.addArrangedSubview(dot)
                dot.widthAnchor.constraint(equalToConstant: 16).isActive = true
                dot.heightAnchor.constraint(equalToConstant: 28).isActive = true
            }
            let width = CGFloat(names.count) * 16
            spaceDots.frame = NSRect(x: 0, y: 0, width: width, height: 28)
            spaceDotsWidth?.constant = width
        }
        for (index, child) in spaceDots.arrangedSubviews.enumerated() {
            guard let dot = child as? NSButton else { continue }
            dot.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: index == selected ? 11 : 9, weight: .regular)
            dot.alphaValue = index == selected ? 1 : 0.35
            dot.toolTip = names[index]
            dot.setAccessibilityLabel(names[index])
            dot.setAccessibilityValue(index == selected ? 1 : 0)
        }
        spaceDots.layoutSubtreeIfNeeded()
        if spaceDots.arrangedSubviews.indices.contains(selected) { spaceDots.scrollToVisible(spaceDots.arrangedSubviews[selected].frame) }
    }

    @objc func spacesChanged() {
        let previous = activeSpaceID
        refreshSpaceControls(); reload(); refreshSpaceMode()
        if previous != nil && activeSpaceID == nil { onDefaultSpace?() }
    }
    func refreshSpaceMode() { showSidebarMode() }
    @objc private func spacePicked(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue else { return }
        if identifier == "default" { activeSpaceID = nil }
        else {
            guard let id = UUID(uuidString: identifier), services.sidebarSpaces.space(id) != nil else { return }
            activeSpaceID = id
        }
        refreshSpaceControls()
        reload(); refreshSpaceMode()
        if let space = activeSpace { onSpaceOverview?(space) }
        else { onDefaultSpace?() }
    }
    func customSpaceSections(_ space: SidebarSpace, inheriting defaults: [SidebarSection]) -> [SidebarSection] {
        func section(_ id: String, _ name: String, _ urls: [URL]) -> SidebarSection {
            SidebarSection(id: id, title: name, items: urls.map { url in
                let template = defaults.flatMap(\.items).first { $0.url?.lexicallyStandardized == url.lexicallyStandardized }
                let symbol = url.isFileURL ? ((services.places.isFolder(url.path) ?? url.hasDirectoryPath) ? "folder" : "doc") : "link"
                let item = SidebarItem(title: template?.title ?? (url.lastPathComponent.isEmpty ? url.absoluteString : url.lastPathComponent), target: .folder(url), symbol: template?.symbol ?? symbol)
                item.isEjectable = template?.isEjectable ?? false
                return item
            })
        }
        return space.groups.map { section($0.id.uuidString, $0.name, $0.urls) }
            + defaults

    }
    func spaceSection(for item: Any?) -> SidebarSection? {
        if let section = item as? SidebarSection { return section }
        return sections.first { section in section.items.contains { $0 === item as? SidebarItem } }
    }
    func spaceDrop(_ urls: [URL], onto item: Any?) -> Bool {
        guard let id = activeSpaceID, canPinSpaceSection(item), let section = spaceSection(for: item), !urls.isEmpty,
              urls.allSatisfy({ !services.copies.contains($0) }) else { return false }
        services.sidebarSpaces.pin(urls, in: id, section: section.id)
        return true
    }
    func spaceTitleMenu() -> NSMenu? {
        guard let space = activeSpace else { return nil }
        let menu = NSMenu()
        for (title, action) in [(String(localized: "Rename"), #selector(renameSidebarSpace(_:))),
                                (String(localized: "Remove"), #selector(removeSidebarSpace(_:))),
                                (String(localized: "New Category…"), #selector(newSpaceGroup(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = space.id
            menu.addItem(item)
        }
        return menu
    }

    func populateSpaceMenu(_ menu: NSMenu, item: Any?, includeSpaceActions: Bool = true) {
        func add(_ title: String, _ action: Selector, _ represented: Any? = nil) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self; entry.representedObject = represented; menu.addItem(entry)
        }
        if let space = activeSpace, let section = item as? SidebarSection,
           space.groups.contains(where: { $0.id.uuidString == section.id }) {
            let ids = [space.id.uuidString, section.id]
            add(String(localized: "New Category…"), #selector(newSpaceGroup(_:)), space.id)
            add(String(localized: "Rename Category…"), #selector(renameSpaceGroup(_:)), ids)
            add(String(localized: "Remove Category"), #selector(removeSpaceGroup(_:)), ids)
            return
        }
        add(String(localized: "New Sidebar Space…"), #selector(newSidebarSpace(_:)))
        guard includeSpaceActions, let space = activeSpace else { return }
        add(String(localized: "Space Overview"), #selector(spaceOverview(_:)), space.id)
        add(String(localized: "Rename"), #selector(renameSidebarSpace(_:)), space.id)
        add(String(localized: "Remove"), #selector(removeSidebarSpace(_:)), space.id)
        menu.addItem(.separator())
        add(String(localized: "Add Link…"), #selector(addSpaceLink(_:)), space.id)
        add(String(localized: "New Category…"), #selector(newSpaceGroup(_:)), space.id)
        if let section = spaceSection(for: item) {
            if let row = item as? SidebarItem, let url = row.url {
                add(String(localized: "Remove from Sidebar"), #selector(removeSpacePin(_:)), [space.id.uuidString, section.id, url.absoluteString])
                add(String(localized: "Add to Favorites"), #selector(favoriteSpacePin(_:)), [space.id.uuidString, url.absoluteString])
            } else if space.groups.contains(where: { $0.id.uuidString == section.id }) {
                add(String(localized: "Rename Category…"), #selector(renameSpaceGroup(_:)), [space.id.uuidString, section.id])
                add(String(localized: "Remove Category"), #selector(removeSpaceGroup(_:)), [space.id.uuidString, section.id])
            }
        }
    }
    func referenceRemovalItem(_ item: SidebarItem) -> NSMenuItem? {
        guard let id = activeSpaceID, let section = spaceSection(for: item), let url = item.url else { return nil }
        let entry = NSMenuItem(title: String(localized: "Remove from Sidebar"), action: #selector(removeSpacePin(_:)), keyEquivalent: "")
        entry.target = self
        entry.representedObject = [id.uuidString, section.id, url.absoluteString]
        return entry
    }

    private func nameSheet(_ title: String, initial: String = "", save: @escaping (String) -> Void) {
        guard let window = view.window else { return }
        let alert = NSAlert(); alert.messageText = title
        let field = NSTextField(string: initial); field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Save")); alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if response == .alertFirstButtonReturn && !name.isEmpty { save(name) }
            }
        }
    }
    @objc private func addSpaceLink(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        nameSheet(String(localized: "Add Link…"), initial: "https://") { [store = services.sidebarSpaces] address in
            guard let url = URL(string: address), ["https", "http"].contains(url.scheme ?? ""), url.host != nil else { return }
            store.pin([url], in: id, section: "spacePinned")
        }
    }

    @objc private func newSidebarSpace(_ sender: Any?) {
        nameSheet(String(localized: "New Sidebar Space…")) { [weak self, store = services.sidebarSpaces] name in
            guard let id = store.create(name) else { return }
            self?.activeSpaceID = id; self?.spacesChanged()
            if let space = store.space(id) { self?.onSpaceOverview?(space) }
        }
    }
    @objc private func renameSidebarSpace(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let space = services.sidebarSpaces.space(id) else { return }
        nameSheet(String(localized: "Rename"), initial: space.name) { [store = services.sidebarSpaces] name in store.update(id) { $0.name = name } }
    }
    @objc private func removeSidebarSpace(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        services.sidebarSpaces.remove(id)
    }
    @objc private func newCategoryFromTitle(_ sender: NSButton) {
        guard let id = activeSpaceID else { return }
        let item = NSMenuItem()
        item.representedObject = id
        newSpaceGroup(item)
    }

    @objc private func newSpaceGroup(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        nameSheet(String(localized: "New Category…")) { [store = services.sidebarSpaces] name in store.createGroup(name, in: id) }
    }
    @objc private func spaceOverview(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let space = services.sidebarSpaces.space(id) else { return }
        onSpaceOverview?(space)
    }
    @objc private func renameSpaceGroup(_ sender: NSMenuItem) {
        guard let ids = sender.representedObject as? [String], let id = UUID(uuidString: ids[0]), let space = services.sidebarSpaces.space(id), let group = space.groups.first(where: { $0.id.uuidString == ids[1] }) else { return }
        nameSheet(String(localized: "Rename Category…"), initial: group.name) { [store = services.sidebarSpaces] name in store.update(id) { space in
            if let index = space.groups.firstIndex(where: { $0.id == group.id }) { space.groups[index].name = name }
        } }
    }
    @objc private func removeSpaceGroup(_ sender: NSMenuItem) {
        guard let ids = sender.representedObject as? [String], let id = UUID(uuidString: ids[0]) else { return }
        services.sidebarSpaces.update(id) { $0.groups.removeAll { $0.id.uuidString == ids[1] } }
    }
    @objc private func removeSpacePin(_ sender: NSMenuItem) {
        guard let ids = sender.representedObject as? [String], let id = UUID(uuidString: ids[0]), let url = URL(string: ids[2]) else { return }
        services.sidebarSpaces.update(id) { space in
            if ids[1] == "spacePinned" { space.pinned.removeAll { $0 == url } }
            else if let i = space.groups.firstIndex(where: { $0.id.uuidString == ids[1] }) { space.groups[i].urls.removeAll { $0 == url } }
        }
    }
    @objc private func favoriteSpacePin(_ sender: NSMenuItem) {
        guard let ids = sender.representedObject as? [String], let id = UUID(uuidString: ids[0]), let url = URL(string: ids[1]) else { return }
        guard services.sidebarSpaces.space(id) != nil, !services.copies.contains(url) else { return }
        addFavorites([url], at: nil)
    }
}
