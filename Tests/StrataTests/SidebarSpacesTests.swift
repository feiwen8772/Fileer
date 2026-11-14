import AppKit
import Testing
@testable import Strata
@testable import StrataFiles
@testable import StrataModel
@testable import StrataSupport

struct SidebarSpacesTests {
    @Test func spacesPersistTheirOwnPinnedReferencesWithoutChangingFiles() throws {
        let tree = try TestTree("a.txt", "ab.txt", "folder/child.txt")
        let prefs = try Prefs.isolated()
        let store = SidebarSpaces(preferences: prefs)
        let first = try #require(store.create("Client")), second = try #require(store.create("Personal"))
        let group = SidebarSpaceGroup(name: "Documents")
        store.update(first) { $0.groups.append(group) }
        let before = tree.snapshot()
        store.pin([tree.url("a.txt"), tree.url("a.txt"), tree.url("folder")], in: first, section: group.id.uuidString)
        store.pin([tree.url("ab.txt")], in: first, section: "spacePinned")
        #expect(store.space(first)?.groups.first?.urls == [tree.url("a.txt"), tree.url("folder")])
        #expect(store.space(second)?.favorites.isEmpty == true)
        store.update(first) { $0.name = "Renamed" }
        let reopened = SidebarSpaces(preferences: prefs)
        #expect(reopened.space(first)?.name == "Renamed")
        #expect(reopened.space(first)?.pinned == [tree.url("ab.txt")])
        reopened.remove(first)
        #expect(reopened.space(second) != nil)
        #expect(tree.snapshot() == before)
        #expect(store.create("  ") == nil)
        reopened.update(first) { $0.name = "Stale" }
        #expect(reopened.space(first) == nil)
    }

    @Test func customSidebarHasBottomFavoritesAndDropsOnlyPinReferences() throws {
        let tree = try TestTree("a.txt", "folder/child.txt")
        let environment = try IndependentEnvironment()
        let sidebar = SidebarViewController(services: environment.services)
        sidebar.loadViewIfNeeded()
        let store = environment.services.sidebarSpaces
        let id = try #require(store.create("Project"))
        let group = SidebarSpaceGroup(name: "Files")
        store.update(id) { $0.groups.append(group) }
        sidebar.activeSpaceID = id; sidebar.spacesChanged()
        #expect(sidebar.sections.last?.id == "favorites")
        #expect(!sidebar.sections.contains { $0.id == "spacePinned" })
        var overviews: [UUID] = []
        sidebar.onSpaceOverview = { overviews.append($0.id) }
        let dot = try #require(sidebar.spaceDots.arrangedSubviews[1] as? NSButton)
        #expect(dot.identifier?.rawValue == id.uuidString)
        if let action = dot.action { NSApp.sendAction(action, to: sidebar, from: dot) }
        sidebar.view.frame = NSRect(x: 0, y: 0, width: 240, height: 700)
        sidebar.view.layoutSubtreeIfNeeded()
        #expect(sidebar.spaceFooter.frame.height == 36)
        let add = try #require(sidebar.spaceFooter.subviews.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("newSidebarSpace:") })
        #expect(add.action == NSSelectorFromString("newSidebarSpace:"))
        let dotCenter = dot.convert(NSPoint(x: dot.bounds.midX, y: dot.bounds.midY), to: sidebar.spaceFooter)
        #expect(abs(dotCenter.y - add.frame.midY) < 1)
        let keyboard = try #require(sidebar.spaceFooter.subviews.compactMap { $0 as? NSButton }.first { $0.action == #selector(AppDelegate.showShortcuts(_:)) })
        #expect(abs(keyboard.frame.midY - dotCenter.y) < 1)
        #expect(abs(dot.frame.width - 16) < 1)

        #expect(sidebar.spaceFooter.subviews.compactMap { $0 as? NSButton }.contains { $0.action == #selector(AppDelegate.showShortcuts(_:)) && $0.target == nil })
        #expect(sidebar.view.subviews.contains { $0 is NSPopUpButton } == false)
        #expect(sidebar.spaceDots.arrangedSubviews.count == 2)
        #expect(sidebar.spaceFooter.frame.minY == sidebar.view.bounds.minY)
        #expect(overviews == [id])
        let section = try #require(sidebar.sections.first { $0.id == group.id.uuidString })
        let before = tree.snapshot()
        let drag = FileDrag([tree.url("a.txt"), tree.url("folder")], offering: [.copy, .move])
        #expect(sidebar.outlineView(sidebar.outline, validateDrop: drag, proposedItem: section, proposedChildIndex: 0) == .copy)
        #expect(sidebar.outlineView(sidebar.outline, acceptDrop: drag, item: section, childIndex: 0))
        let move = FileDrag([tree.url("a.txt")], offering: .move)
        #expect(sidebar.outlineView(sidebar.outline, validateDrop: move, proposedItem: section, proposedChildIndex: 0).isEmpty)
        #expect(!sidebar.outlineView(sidebar.outline, acceptDrop: move, item: section, childIndex: 0))
        #expect(store.space(id)?.groups.first?.urls.count == 2)
        #expect(tree.snapshot() == before)
        let other = SidebarViewController(services: environment.services)
        other.loadViewIfNeeded()
        #expect(other.activeSpaceID == nil)
        store.remove(id)
        #expect(sidebar.activeSpaceID == nil)
        _ = try #require(store.create("Other"))
        if let action = dot.action { NSApp.sendAction(action, to: sidebar, from: dot) }
        #expect(sidebar.activeSpaceID == nil)
    }

    @Test func sectionOrderAndCollapsedStateStayWithTheirSpace() throws {
        let environment = try IndependentEnvironment()
        let sidebar = SidebarViewController(services: environment.services)
        sidebar.loadViewIfNeeded()
        let store = environment.services.sidebarSpaces
        let first = try #require(store.create("First")), second = try #require(store.create("Second"))
        sidebar.activeSpaceID = first; sidebar.spacesChanged()
        for id in ["favorites", "locations", "insights", "tags", "frequent"] {
            #expect(sidebar.sections.contains { $0.id == id })
        }
        let favorites = try #require(sidebar.sections.first { $0.id == "favorites" })
        let drag = FileDrag([], offering: .move)
        let writer = try #require(sidebar.outlineView(sidebar.outline, pasteboardWriterForItem: favorites))
        drag.draggingPasteboard.writeObjects([writer])
        #expect(drag.draggingPasteboard.availableType(from: [.fileURL]) == nil)
        #expect(sidebar.outlineView(sidebar.outline, validateDrop: drag, proposedItem: nil, proposedChildIndex: 0) == .move)
        #expect(sidebar.outlineView(sidebar.outline, acceptDrop: drag, item: nil, childIndex: 0))
        #expect(sidebar.sections.first?.id == "favorites")
        let locations = try #require(sidebar.sections.first { $0.id == "locations" })
        sidebar.outline.collapseItem(locations)
        #expect(sidebar.collapsedSectionIDs.contains("locations"))
        sidebar.reload()
        let collapsed = try #require(sidebar.sections.first { $0.id == "locations" })
        #expect(!sidebar.outline.isItemExpanded(collapsed))
        let reopened = SidebarViewController(services: environment.services)
        reopened.loadViewIfNeeded()
        reopened.activeSpaceID = first; reopened.spacesChanged()
        #expect(reopened.sections.first?.id == "favorites")
        #expect(reopened.collapsedSectionIDs.contains("locations"))
        sidebar.activeSpaceID = second; sidebar.spacesChanged()
        #expect(sidebar.sections.last?.id == "favorites")
        #expect(!sidebar.sections.contains { $0.id == "spacePinned" })
        #expect(!sidebar.collapsedSectionIDs.contains("locations"))
        for section in sidebar.sections {
            sidebar.outline.collapseItem(section)
            #expect(sidebar.collapsedSectionIDs.contains(section.id))
            sidebar.outline.expandItem(section)
            #expect(!sidebar.collapsedSectionIDs.contains(section.id))
        }
        #expect(reopened.collapsedSectionIDs.contains("locations"))
        sidebar.activeSpaceID = first; sidebar.spacesChanged()
        #expect(sidebar.sections.first?.id == "favorites")
        let restored = try #require(sidebar.sections.first { $0.id == "locations" })
        sidebar.outline.expandItem(restored)
        #expect(!sidebar.collapsedSectionIDs.contains("locations"))
        let stale = FileDrag([])
        stale.draggingPasteboard.writeObjects([sidebar.sectionDrag(restored)])
        sidebar.activeSpaceID = second; sidebar.spacesChanged()
        #expect(sidebar.sectionDropIndex(stale, item: nil, index: 0) == nil)
    }

    @Test func builtInSectionsAndMenusShareTheDefaultDataAndActions() throws {
        let tree = try TestTree("Documents/", "Downloads/")
        let environment = try IndependentEnvironment()
        environment.preferences.favoritePaths = [tree.url("Documents").path, tree.url("Downloads").path]
        let sidebar = SidebarViewController(services: environment.services)
        sidebar.loadViewIfNeeded()
        let defaults = sidebar.sections
        let id = try #require(environment.services.sidebarSpaces.create("Shared"))
        sidebar.activeSpaceID = id; sidebar.spacesChanged()
        for section in defaults {
            let inherited = try #require(sidebar.sections.first { $0.id == section.id })
            #expect(inherited.items.map(\.target) == section.items.map(\.target))
            #expect(inherited.items.map(\.title) == section.items.map(\.title))
            let customHeaderMenu = NSMenu()
            sidebar.populateItemMenu(customHeaderMenu, for: inherited)
            sidebar.activeSpaceID = nil
            let defaultHeaderMenu = NSMenu()
            sidebar.populateItemMenu(defaultHeaderMenu, for: section)
            sidebar.activeSpaceID = id
            #expect(customHeaderMenu.items.map(\.action) == defaultHeaderMenu.items.map(\.action))
            #expect(defaultHeaderMenu.items.isEmpty)
            for (_, b) in zip(section.items, inherited.items) {
                let customMenu = NSMenu()
                sidebar.populateItemMenu(customMenu, for: b)
                sidebar.activeSpaceID = nil
                let defaultMenu = NSMenu()
                sidebar.populateItemMenu(defaultMenu, for: b)
                sidebar.activeSpaceID = id
                #expect(customMenu.items.map(\.action) == defaultMenu.items.map(\.action))
                #expect(customMenu.items.map(\.title) == defaultMenu.items.map(\.title))
            }
        }
        environment.preferences.favoritePaths = [tree.url("Documents").path]
        let favorites = try #require(sidebar.sections.first { $0.id == "favorites" })
        #expect(favorites.items.compactMap(\.url).map(\.fileViewKey) == [tree.url("Documents").lexicallyStandardized.fileViewKey])
        #expect(environment.services.sidebarSpaces.space(id)?.favorites.isEmpty == true)
        sidebar.outline.collapseItem(favorites)
        #expect(!sidebar.outline.isItemExpanded(favorites))
        sidebar.outline.expandItem(favorites)
        #expect(sidebar.outline.isItemExpanded(favorites))
    }

    @Test func legacySpaceFavoritesDoNotOverrideSharedFavorites() throws {
        let tree = try TestTree("Documents/", "Old/")
        let prefs = try Prefs.isolated()
        prefs.favoritePaths = [tree.url("Documents").path]
        let legacy = SidebarSpace(name: "Existing", favorites: [tree.url("Old")])
        prefs.defaults.set(try JSONEncoder().encode([legacy]), forKey: "sidebarSpaces.v1")
        let environment = try IndependentEnvironment(preferences: prefs)
        let sidebar = SidebarViewController(services: environment.services)
        sidebar.activeSpaceID = legacy.id; sidebar.loadViewIfNeeded()
        let favorites = try #require(sidebar.sections.first { $0.id == "favorites" })
        #expect(favorites.items.compactMap(\.url).map(\.fileViewKey) == [tree.url("Documents").lexicallyStandardized.fileViewKey])
        #expect(environment.services.sidebarSpaces.space(legacy.id)?.favorites == [tree.url("Old")])
    }

    @Test func customSpaceTitleUpdatesAndItsMenuKeepsTheOriginalSpaceIdentity() throws {
        let environment = try IndependentEnvironment()
        let sidebar = SidebarViewController(services: environment.services)
        sidebar.loadViewIfNeeded()
        #expect(sidebar.spaceTitle.isHidden)
        #expect(sidebar.spaceTitleHeight?.constant == 0)
        #expect(sidebar.spaceTitleMenu() == nil)
        let store = environment.services.sidebarSpaces
        let id = try #require(store.create("Client"))
        sidebar.activeSpaceID = id; sidebar.spacesChanged()
        #expect(!sidebar.spaceTitle.isHidden)
        #expect(sidebar.spaceTitle.label.stringValue == "Client")
        let menu = try #require(sidebar.spaceTitle.onMenu?())
        #expect(menu.items.count == 3)
        #expect(!menu.items.contains { $0.action == NSSelectorFromString("spaceOverview:") })
        #expect(menu.items.last?.action == NSSelectorFromString("newSpaceGroup:"))
        #expect(sidebar.spaceTitle.addCategory.action == NSSelectorFromString("newCategoryFromTitle:"))
        sidebar.view.frame = NSRect(x: 0, y: 0, width: 240, height: 700)
        sidebar.view.layoutSubtreeIfNeeded()
        let button = sidebar.spaceTitle.addCategory
        let parent = try #require(sidebar.spaceTitle.superview)
        let point = parent.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
        #expect(sidebar.spaceTitle.hitTest(point) === button)
        #expect(menu.items.allSatisfy { $0.representedObject as? UUID == id })
        store.update(id) { $0.name = "Renamed" }
        #expect(sidebar.spaceTitle.label.stringValue == "Renamed")
        sidebar.activeSpaceID = nil; sidebar.spacesChanged()
        #expect(sidebar.spaceTitle.isHidden)
        #expect(sidebar.spaceTitleHeight?.constant == 0)
        #expect(menu.items.allSatisfy { $0.representedObject as? UUID == id })
    }

    @Test func newCategoriesLeadAndReferenceRowsUseNormalIconsAndMenus() throws {
        let tree = try TestTree("folder/", "note.txt")
        let environment = try IndependentEnvironment()
        let sidebar = SidebarViewController(services: environment.services)
        sidebar.loadViewIfNeeded()
        let store = environment.services.sidebarSpaces
        let id = try #require(store.create("Project"))
        sidebar.activeSpaceID = id; sidebar.spacesChanged()
        store.createGroup("First", in: id)
        store.createGroup("Newest", in: id)
        let group = try #require(store.space(id)?.groups.first)
        #expect(sidebar.sections.first?.title == "Newest")
        store.pin([tree.url("folder/"), tree.url("note.txt")], in: id, section: group.id.uuidString)
        let section = try #require(sidebar.sections.first)
        #expect(section.items.map(\.symbol) == ["folder", "doc"])
        let before = tree.snapshot()
        store.placeReference(tree.url("note.txt"), in: id, section: group.id.uuidString, at: 0)
        #expect(store.space(id)?.groups.first?.urls == [tree.url("note.txt"), tree.url("folder/")])
        #expect(tree.snapshot() == before)
        let headerMenu = NSMenu()
        sidebar.populateItemMenu(headerMenu, for: section)
        #expect(headerMenu.items.contains { $0.action == NSSelectorFromString("renameSpaceGroup:") })
        #expect(headerMenu.items.contains { $0.action == NSSelectorFromString("removeSpaceGroup:") })
        let currentSection = try #require(sidebar.sections.first { $0.id == group.id.uuidString })
        let row = try #require(currentSection.items.first)
        let rowMenu = NSMenu()
        sidebar.populateItemMenu(rowMenu, for: row)
        #expect(rowMenu.items.contains { $0.action == NSSelectorFromString("copyItemPath:") })
        #expect(rowMenu.items.contains { $0.action == NSSelectorFromString("openReference:") })
        #expect(rowMenu.items.contains { $0.action == NSSelectorFromString("removeSpacePin:") })
        #expect(sidebar.spaceTitle.addCategory.image != nil && sidebar.spaceTitle.addCategory.title.isEmpty)
    }

    @Test func locationsExposeNativeNetworkAndAirDropInEverySpace() throws {
        let environment = try IndependentEnvironment()
        let sidebar = SidebarViewController(services: environment.services)
        sidebar.loadViewIfNeeded()
        for id in [nil, try #require(environment.services.sidebarSpaces.create("Project"))] as [UUID?] {
            sidebar.activeSpaceID = id; sidebar.spacesChanged()
            let locations = try #require(sidebar.sections.first { $0.id == "locations" })
            var selected: SidebarTarget?
            sidebar.onSelect = { selected = $0 }
            for destination in SidebarSystemLocation.allCases {
                let row = try #require(locations.items.first { $0.target == .systemLocation(destination) })
                #expect(row.url == nil)
                sidebar.outline.selectRowIndexes([sidebar.outline.row(forItem: row)], byExtendingSelection: false)
                #expect(selected == .systemLocation(destination))
                let menu = NSMenu()
                sidebar.populateItemMenu(menu, for: row)
                #expect(menu.items.isEmpty)
            }
        }
    }

    private actor OverviewGate {
        typealias Rows = [(title: String, detail: String, entries: [FileEntry])]
        var waiting: [String: CheckedContinuation<Rows, Never>] = [:]
        let started: AsyncStream<String>.Continuation
        init(_ started: AsyncStream<String>.Continuation) { self.started = started }
        func read(_ space: SidebarSpace) async -> Rows {
            await withCheckedContinuation { continuation in
                waiting[space.name] = continuation
                started.yield(space.name)
            }
        }
        func finish(_ name: String) { waiting.removeValue(forKey: name)?.resume(returning: []) }
    }

    @Test func aLateOverviewCannotReplaceTheNewlySelectedSpace() async throws {
        let tree = try TestTree("folder/")
        let environment = try IndependentEnvironment()
        let owner = BrowserWindowController(location: tree.url("folder"), services: environment.services)
        owner.window?.setFrameAutosaveName("")
        owner.split.splitView.autosaveName = nil
        defer { owner.window?.contentViewController = nil; owner.panes.forEach { $0.stopBackgroundWork() } }
        await owner.browser.directoryReads.task?.value
        let (events, started) = AsyncStream<String>.makeStream()
        let gate = OverviewGate(started)
        var next = events.makeAsyncIterator()
        owner.sidebarSpaceReader = { await gate.read($0) }
        let first = SidebarSpace(name: "One"), second = SidebarSpace(name: "Two")
        owner.split.sidebar.activeSpaceID = first.id
        owner.showSidebarOverview(first)
        let old = owner.sidebarSpaceTask
        #expect(await next.next() == "One")
        owner.split.sidebar.activeSpaceID = second.id
        owner.showSidebarOverview(second)
        let current = owner.sidebarSpaceTask
        #expect(await next.next() == "Two")
        await gate.finish("Two"); await current?.value
        #expect(owner.browser.statusText.contains("Two"))
        await gate.finish("One"); await old?.value
        #expect(owner.browser.statusText.contains("Two"))
    }

    @Test func overviewIncludesPinnedLinksAndOnlyTheRequestedGroups() async throws {
        let tree = try TestTree("a.txt", "b.txt")
        let link = URL(string: "https://example.com/project")!
        let space = SidebarSpace(name: "Project", groups: [SidebarSpaceGroup(name: "Files", urls: [tree.url("a.txt")])],
                                 pinned: [link], favorites: [tree.url("b.txt")])
        let rows = await SidebarSpaceReads.groups(space)
        #expect(rows.count == 3)
        #expect(rows[0].entries.map(\.url) == [link])
        #expect(rows[1].entries.map(\.url) == [tree.url("a.txt")])
        #expect(rows[2].entries.map(\.url) == [tree.url("b.txt")])
    }
}
