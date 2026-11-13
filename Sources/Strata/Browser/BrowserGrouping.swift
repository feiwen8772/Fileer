import AppKit

extension Notification.Name {
    static let browserGroupingChanged = Self("StrataBrowserGroupingChanged")
}

enum BrowserGroupKey: Int, CaseIterable {
    case name, kind, modified, created, added, size, tags

    init(sort: SortKey) {
        switch sort {
        case .name: self = .name
        case .kind: self = .kind
        case .modified: self = .modified
        case .created: self = .created
        case .added: self = .added
        case .size: self = .size
        case .tags: self = .tags
        default: self = .kind
        }
    }

}

final class BrowserGrouping {
    private(set) var headers: [FileNode] = []

    func rebuild(_ rows: [FileNode], by key: BrowserGroupKey?, ascending: Bool? = nil, tags: (URL) -> [String]) {
        guard let key else { headers = []; return }
        var buckets: [String: [FileNode]] = [:]
        var ranks: [String: Int] = [:]
        var monthTitles: [Int: String] = [:]
        var kindTitles: [String: String] = [:]
        let calendar = Calendar.current
        for node in rows {
            let entry = node.entry
            let title: String
            switch key {
            case .name: title = String(entry.displayName.prefix(1)).uppercased()
            case .kind:
                let kind = entry.isFolder ? "folder" : entry.contentType?.identifier ?? "unknown"
                if let cached = kindTitles[kind] { title = cached }
                else {
                    title = FileKindGroup.of(isFolder: entry.isFolder, type: entry.contentType).title
                    kindTitles[kind] = title
                }
            case .tags: title = tags(entry.url).sorted().first ?? String(localized: "None")
            case .size:
                if let size = entry.size, !entry.isFolder {
                    let bounds: [Int64] = [0, 1_024, 1_048_576, 104_857_600, 1_073_741_824]
                    let rank = bounds.lastIndex(where: { size >= $0 }) ?? 0
                    title = rank == bounds.count - 1 ? "≥ \(Format.bytes(bounds[rank]))"
                        : "\(Format.bytes(bounds[rank])) – \(Format.bytes(bounds[rank + 1]))"
                    ranks[title] = rank
                } else { title = "—"; ranks[title] = Int.max }
            case .modified, .created, .added:
                let date = key == .modified ? entry.modified : key == .created ? entry.created : entry.added
                if let date {
                    let parts = calendar.dateComponents([.year, .month], from: date)
                    let month = (parts.year ?? 0) * 12 + (parts.month ?? 0)
                    if let cached = monthTitles[month] { title = cached }
                    else {
                        title = date.formatted(.dateTime.year().month(.wide))
                        monthTitles[month] = title
                    }
                    ranks[title] = month
                } else { title = "—"; ranks[title] = Int.max }
            }
            buckets[title, default: []].append(node)
        }
        let previous = Dictionary(headers.compactMap { header in header.groupTitle.map { ($0, header) } }, uniquingKeysWith: { a, _ in a })
        let ascending = ascending ?? ![BrowserGroupKey.modified, .created, .added].contains(key)
        headers = buckets.keys.sorted {
            if ranks[$0] == Int.max { return false }
            if ranks[$1] == Int.max { return true }
            if let a = ranks[$0], let b = ranks[$1], a != b { return ascending ? a < b : a > b }
            let order = $0.localizedStandardCompare($1)
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }.compactMap { title in
            guard let children = buckets[title], let first = children.first else { return nil }
            let header = previous[title] ?? FileNode(entry: first.entry)
            header.groupTitle = title
            header.children = children
            return header
        }
    }

    static func menu(target: AnyObject, action: Selector = #selector(BrowserViewController.chooseGrouping(_:))) -> NSMenuItem {
        let root = NSMenuItem(title: String(localized: "Use Groups"), action: action, keyEquivalent: "")
        root.target = target
        root.image = NSImage(systemSymbolName: "square.grid.3x1.below.line.grid.1x2", accessibilityDescription: nil)
        return root
    }
}

extension BrowserViewController {
    var canGroup: Bool { !isShowingResults && directory != nil && [.list, .grid, .columns].contains(effectiveMode) }
    private var groupingPreferenceKey: String? { directory.map { services.folderViews.key(for: $0) + ".grouping" } }
    var groupKey: BrowserGroupKey? {
        guard let key = groupingPreferenceKey,
              let value = preferences.defaults.object(forKey: key) as? Int, value >= 0,
              let choice = ordering.choice else { return nil }
        return BrowserGroupKey(sort: choice.key)
    }
    var showsFolderGroups: Bool { canGroup && groupKey != nil }
    var displayedRows: [FileNode] { showsFolderGroups ? grouping.headers : rows }

    func rebuildGroups() {
        grouping.rebuild(rows, by: showsFolderGroups ? groupKey : nil, ascending: ordering.choice?.ascending) { [tags = services.tags] in tags.cachedTags(for: $0).map(\.name) }
    }

    func reloadOutline() {
        rebuildGroups()
        outlineView.reloadData()
        if showsFolderGroups { for header in grouping.headers { outlineView.expandItem(header) } }
    }

    @objc func chooseGrouping(_ sender: NSMenuItem) {
        guard canGroup, !inlineRename.isEditing, let key = groupingPreferenceKey else { return }
        preferences.defaults.set(groupKey == nil ? 0 : -1, forKey: key)
        preferences.notifications.post(name: .browserGroupingChanged, object: preferences, userInfo: ["key": key])
    }

    func validateGrouping(_ item: NSMenuItem) -> Bool {
        item.state = showsFolderGroups ? .on : .off
        return canGroup && !inlineRename.isEditing
    }

    @objc func groupingChanged(_ notification: Notification) {
        guard notification.userInfo?["key"] as? String == groupingPreferenceKey, !isShowingResults else { return }
        let selection = selectedURLs
        let expanded = (0..<outlineView.numberOfRows).compactMap { outlineView.item(atRow: $0) as? FileNode }
            .filter { $0.groupTitle == nil && outlineView.isItemExpanded($0) }
        reloadOutline()
        for node in expanded { outlineView.expandItem(node) }
        pushContent()
        select(selection, scroll: false)
    }
}
