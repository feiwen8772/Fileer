import AppKit

final class SidebarSpaceTitleView: NSView {
    let label = NSTextField(labelWithString: "")
    let addCategory = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: String(localized: "New Category…")) ?? NSImage(), target: nil, action: nil)
    var onMenu: (() -> NSMenu?)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        addCategory.title = ""
        addCategory.imagePosition = .imageOnly
        addCategory.toolTip = String(localized: "New Category…")
        addCategory.isBordered = false
        addCategory.font = .systemFont(ofSize: 11)
        addCategory.translatesAutoresizingMaskIntoConstraints = false
        addCategory.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(addCategory)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: addCategory.leadingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            addCategory.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            addCategory.centerYAnchor.constraint(equalTo: centerYAnchor),
            addCategory.heightAnchor.constraint(equalToConstant: 24),
            addCategory.widthAnchor.constraint(equalToConstant: 24),
        ])
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit === addCategory || hit.isDescendant(of: addCategory) { return hit }
        return self
    }
    override func menu(for event: NSEvent) -> NSMenu? { onMenu?() }
}
