import AppKit
import Testing
@testable import StrataSupport
@testable import Strata
@testable import StrataFiles
@testable import StrataModel

struct BrowserGroupingTests {
    private func entry(_ name: String, folder: Bool = false, size: Int64? = nil, modified: Date? = nil) -> FileEntry {
        FileEntry(url: URL(fileURLWithPath: "/group-fixture/" + name), name: name, isDirectory: folder,
                  isPackage: false, isHidden: false, isSymlink: false, isVolume: false, size: size,
                  modified: modified, created: nil, added: nil, kind: "", contentType: nil)
    }

    @Test func groupsKeepOriginalNodeIdentityAndNeverDuplicateTaggedItems() {
        let grouping = BrowserGrouping()
        let file = FileNode(entry: entry("a.txt")), folder = FileNode(entry: entry("ab", folder: true))
        for key in BrowserGroupKey.allCases {
            grouping.rebuild([file, folder], by: key) { _ in ["Red", "Blue"] }
            let children = grouping.headers.flatMap { $0.children ?? [] }
            #expect(children.count == 2)
            #expect(children.contains { $0 === file })
            #expect(children.contains { $0 === folder })
            #expect(file.parent == nil && folder.parent == nil)
            #expect(file.groupTitle == nil && folder.groupTitle == nil)
        }
        grouping.rebuild([file, folder], by: nil) { _ in [] }
        #expect(grouping.headers.isEmpty)
    }

    @Test func sizeBucketsHaveNumericOrderAndDatesHaveNewestMonthFirst() {
        let grouping = BrowserGrouping()
        let tiny = FileNode(entry: entry("tiny", size: 1)), large = FileNode(entry: entry("large", size: 2_000_000))
        let folder = FileNode(entry: entry("folder", folder: true))
        grouping.rebuild([folder, large, tiny], by: .size) { _ in [] }
        #expect(grouping.headers.compactMap { $0.children?.first?.entry.name } == ["tiny", "large", "folder"])
        let old = FileNode(entry: entry("old", modified: Date(timeIntervalSince1970: 0)))
        let recent = FileNode(entry: entry("recent", modified: Date(timeIntervalSince1970: 1_700_000_000)))
        grouping.rebuild([old, recent, folder], by: .modified) { _ in [] }
        #expect(grouping.headers.compactMap { $0.children?.first?.entry.name } == ["recent", "old", "folder"])
    }

    @Test func groupedGridHeadersOccupySpaceWithoutBecomingSelectableItems() {
        let layout = GridLayout()
        let collection = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        collection.collectionViewLayout = layout
        layout.prepare()
        layout.itemCount = 3
        layout.groups = [FileCollectionGroup(title: "A", count: 1), FileCollectionGroup(title: "B", count: 2)]
        // A real data source supplies the item count when prepare runs.
        let source = GridSource()
        collection.dataSource = source
        collection.reloadData()
        layout.prepare()
        let first = layout.frame(for: 0), second = layout.frame(for: 1)
        #expect(second.minY > first.maxY)
        #expect(layout.index(at: NSPoint(x: first.midX, y: first.midY)) == 0)
        #expect(layout.index(at: NSPoint(x: first.midX, y: 12)) == nil)
        #expect(layout.layoutAttributesForElements(in: collection.bounds).contains { $0.representedElementCategory == .supplementaryView })
        withExtendedLifetime(source) {}
    }

    private final class GridSource: NSObject, NSCollectionViewDataSource {
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { 3 }
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem { NSCollectionViewItem() }
    }

    @Test func groupingFollowsTheCurrentSortWithoutOfferingAnotherCriterion() async throws {
        let file = entry("a.txt"), folder = entry("ab", folder: true)
        let environment = try IndependentEnvironment(directories: DirectoryReader { _, _, _ in [file, folder] })
        let browser = BrowserViewController(services: environment.services)
        browser.load(URL(fileURLWithPath: "/group-fixture"))
        await browser.directoryReads.task?.value
        browser.chooseGrouping(NSMenuItem())
        for key in [SortKey.name, .kind, .modified, .created, .added, .size, .tags] {
            browser.applySort(key, ascending: true)
            #expect(browser.groupKey == BrowserGroupKey(sort: key))
        }
        let menu = BrowserGrouping.menu(target: browser)
        #expect(menu.submenu == nil)
        #expect(menu.action == #selector(BrowserViewController.chooseGrouping(_:)))
        browser.stopBackgroundWork()
    }

    private func columns(in view: NSView) -> [ColumnPane] {
        (view as? ColumnPane).map { [$0] } ?? view.subviews.flatMap { columns(in: $0) }
    }

    @Test func groupedColumnsMapHeadersAndDeeperSelectionsToTheirExactFiles() async throws {
        let tree = try TestTree("a.txt", "ab/child.txt", "ab/child2.txt", "z.txt")
        let environment = try IndependentEnvironment()
        let browser = BrowserViewController(services: environment.services)
        browser.view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        browser.load(tree.root)
        await browser.directoryReads.task?.value
        browser.setMode(.columns)
        browser.chooseGrouping(NSMenuItem())
        let root = try #require(columns(in: browser.columns.view).first { $0.isRoot })
        let chosen = tree.url("a.txt")
        let row = try #require(root.row(for: chosen))
        #expect(row > 0)
        #expect(root.entry(at: row)?.url == chosen)
        #expect(root.entry(at: 0) == nil)
        #expect(!root.tableView(root.tableView, shouldSelectRow: 0))
        #expect(root.tableView(root.tableView, pasteboardWriterForRow: 0) == nil)
        root.select([chosen], scroll: false)
        #expect(root.selectedEntries.map(\.url) == [chosen])
        let folderRow = try #require(root.row(for: tree.url("ab")))
        #expect(root.dropTarget(row: folderRow, operation: .on).fileViewKey == tree.url("ab").fileViewKey)
        #expect(root.dropTarget(row: 0, operation: .on) == tree.root)
        browser.columns.select([tree.url("ab")], scroll: false)
        let deeper = try #require(columns(in: browser.columns.view).first { !$0.isRoot })
        await deeper.directoryReads.task?.value
        browser.columns.select([tree.url("ab/child.txt")], scroll: false)
        #expect(browser.selectedURLs == [tree.url("ab/child.txt")])
        #expect(browser.columns.preview == nil)
        browser.applySort(.name, ascending: false)
        #expect(browser.selectedURLs == [tree.url("ab/child.txt")])
        #expect(browser.columns.preview == nil)
        #expect(deeper.entry(at: 0) == nil)
        deeper.layoutSubtreeIfNeeded()
        #expect(deeper.tableView.style == .fullWidth)
        let menu = try #require(browser.backgroundContextMenu())
        #expect(browser.selectedURLs.isEmpty)
        #expect(browser.targetDirectory?.fileViewKey == tree.url("ab").fileViewKey)
        #expect(menu.items.contains { $0.action == StrataCommand.newFolder.action })
        #expect(!menu.items.contains { $0.action == StrataCommand.moveToTrash.action })
        browser.view.layoutSubtreeIfNeeded()
        #expect(browser.columns.view.frame.maxX == browser.view.bounds.maxX)
        browser.stopBackgroundWork()
    }

    @Test func nativeGroupingKeepsSelectionFilteringAndResultsBoundToRealFiles() async throws {
        let file = entry("a.txt"), folder = entry("ab", folder: true)
        let environment = try IndependentEnvironment(directories: DirectoryReader { _, _, _ in [file, folder] })
        let browser = BrowserViewController(services: environment.services)
        browser.view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        browser.load(URL(fileURLWithPath: "/group-fixture"))
        await browser.directoryReads.task?.value
        for mode in [BrowserViewMode.list, .grid, .columns] {
            browser.setMode(mode)
            browser.select([file.url], scroll: false)
            let item = NSMenuItem()
            browser.chooseGrouping(item)
            #expect(browser.showsFolderGroups)
            #expect(browser.selectedURLs == [file.url])
            #expect(browser.displayedRows.flatMap { $0.children ?? [] }.map(\.url).count == 2)
            browser.applySort(.name, ascending: false)
            #expect(browser.selectedURLs == [file.url])
            browser.setFilter("a.txt")
            #expect(browser.displayedRows.flatMap { $0.children ?? [] }.map(\.url) == [file.url])
            browser.clearFilter()
            browser.chooseGrouping(item)
            #expect(!browser.showsFolderGroups)
        }
        browser.showResults([file, folder], total: 2)
        #expect(!browser.canGroup)
        #expect(browser.displayedRows.map(\.url) == [file.url, folder.url])
        browser.stopBackgroundWork()
    }
}
