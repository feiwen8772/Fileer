import AppKit

extension BrowserWindowController {
    func showSidebarOverview(_ space: SidebarSpace) {
        sidebarSpaceTask?.cancel()
        let request = UUID(); sidebarSpaceRequest = request
        let browser = browser
        pane.host.closeSystemPage()
        browser.showMessage(symbol: "square.grid.2x2", title: space.name)
        let revision = browser.navigationRevision
        var overview = space
        overview.favorites = Places.favorites(preferences: services.preferences, checks: services.places).map(\.url)
        let reader = sidebarSpaceReader
        sidebarSpaceTask = Task { [weak browser, weak self] in
            let groups = await reader(overview)
            guard !Task.isCancelled, let self, !isClosed, sidebarSpaceRequest == request, split.sidebar.activeSpaceID == space.id,
                  let browser, browser.navigationRevision == revision, panes.contains(where: { $0.browser === browser }) else { return }
            browser.showGroups(groups, summary: space.name)
        }
    }
    func openSidebarPin(_ url: URL) {
        if !url.isFileURL { NSWorkspace.shared.open(url); return }
        sidebarSpaceTask?.cancel()
        let request = UUID(); sidebarSpaceRequest = request
        let spaceID = split.sidebar.activeSpaceID
        let browser = browser, revision = browser.navigationRevision
        sidebarSpaceTask = Task { [weak browser, weak self] in
            let entry = await SidebarSpaceReads.entry(url)
            guard !Task.isCancelled, let self, !isClosed, sidebarSpaceRequest == request, split.sidebar.activeSpaceID == spaceID,
                  let browser, browser.navigationRevision == revision, panes.contains(where: { $0.browser === browser }), let entry else { return }
            browser.open([entry])
        }
    }
}

nonisolated enum SidebarSpaceReads {
    @concurrent static func entry(_ url: URL) async -> FileEntry? { makeEntry(url) }
    private static func makeEntry(_ url: URL) -> FileEntry? {
        if url.isFileURL { return FileEntry(url: url) }
        guard ["https", "http"].contains(url.scheme ?? "") else { return nil }
        return FileEntry(url: url, name: url.absoluteString, isDirectory: false, isPackage: false,
                         isHidden: false, isSymlink: false, isVolume: false, size: nil, modified: nil,
                         created: nil, added: nil, kind: "", contentType: nil)
    }
    @concurrent static func groups(_ space: SidebarSpace) async -> [(title: String, detail: String, entries: [FileEntry])] {
        let groups = [SidebarSpaceGroup(name: String(localized: "Pinned Items"), urls: space.pinned)]
            + space.groups + [SidebarSpaceGroup(name: String(localized: "Favorites"), urls: space.favorites)]
        var seen: Set<String> = []
        return groups.map { group in
            let entries = group.urls.compactMap { url -> FileEntry? in
                guard !Task.isCancelled, let entry = makeEntry(url), seen.insert(entry.locationKey).inserted else { return nil }
                return entry
            }
            return (group.name, "", entries)
        }
    }
}
