import AppKit

extension NSPasteboard.PasteboardType {
    static let sidebarSection = Self("dev.strata.sidebar-section")
}

extension SidebarViewController {
    private var sectionSettingsKey: String { "sidebarSections." + (activeSpaceID?.uuidString ?? "default") }
    var collapsedSectionIDs: Set<String> {
        get {
            guard activeSpaceID != nil else { return preferences.collapsedSidebarSections }
            return Set((preferences.defaults.stringArray(forKey: sectionSettingsKey + ".collapsed") ?? []).map { $0 == "spaceFavorites" ? "favorites" : $0 })
        }
        set {
            if activeSpaceID == nil { preferences.collapsedSidebarSections = newValue }
            else { preferences.defaults.set(Array(newValue), forKey: sectionSettingsKey + ".collapsed") }
        }
    }
    func orderedSections(_ sections: [SidebarSection]) -> [SidebarSection] {
        let ids = (preferences.defaults.stringArray(forKey: sectionSettingsKey + ".order") ?? []).map { activeSpaceID != nil && $0 == "spaceFavorites" ? "favorites" : $0 }
        let ranks = Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a })
        return sections.enumerated().sorted {
            let a = ranks[$0.element.id] ?? ids.count + $0.offset
            let b = ranks[$1.element.id] ?? ids.count + $1.offset
            return a < b
        }.map(\.element)
    }
    func sectionDrag(_ section: SidebarSection) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setPropertyList(["owner": String(describing: ObjectIdentifier(services.sidebarSpaces)), "space": activeSpaceID?.uuidString ?? "default", "section": section.id], forType: .sidebarSection)
        return item
    }
    func sectionDropIndex(_ info: NSDraggingInfo, item: Any?, index: Int) -> Int? {
        guard let data = info.draggingPasteboard.propertyList(forType: .sidebarSection) as? [String: String],
              data["owner"] == String(describing: ObjectIdentifier(services.sidebarSpaces)),
              data["space"] == (activeSpaceID?.uuidString ?? "default"),
              sections.contains(where: { $0.id == data["section"] }) else { return nil }
        if item == nil, index >= 0, index <= sections.count { return index }
        if let section = item as? SidebarSection { return sections.firstIndex { $0 === section } }
        return nil
    }
    @discardableResult func reorderSection(_ id: String, to index: Int) -> Bool {
        guard let from = sections.firstIndex(where: { $0.id == id }), index >= 0, index <= sections.count else { return false }
        var ids = sections.map(\.id)
        ids.remove(at: from)
        ids.insert(id, at: min(index > from ? index - 1 : index, ids.count))
        preferences.defaults.set(ids, forKey: sectionSettingsKey + ".order")
        preferences.notifications.post(name: .sidebarSpacesChanged, object: services.sidebarSpaces)
        return true
    }
    func canPinSpaceSection(_ item: Any?) -> Bool {
        guard let section = spaceSection(for: item), let space = activeSpace else { return false }
        return space.groups.contains { $0.id.uuidString == section.id }
    }
}
