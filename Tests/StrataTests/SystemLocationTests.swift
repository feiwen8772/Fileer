import AppKit
import Testing
@testable import Strata
@testable import StrataFiles

@MainActor struct SystemLocationTests {
    private func page(_ location: SidebarSystemLocation) -> SystemLocationViewController {
        SystemLocationViewController(location: location, discoveryEnabled: false,
                                     mounts: ServerMountSession(mounter: ServerMounter { _, _ in nil }))
    }

    @Test func virtualPagesReplaceEachOtherAndStopOnNavigationAndClose() throws {
        let environment = try IndependentEnvironment()
        let pane = Pane(location: URL(fileURLWithPath: "/tmp"), services: environment.services)
        pane.host.loadViewIfNeeded()
        pane.navigate(to: .systemLocation(.network))
        let network = page(.network)
        pane.host.showSystemPage(network)
        #expect(pane.host.systemPage === network)
        #expect(pane.browser.view.isHidden)
        pane.navigate(to: .systemLocation(.airDrop))
        #expect(network.stopped)
        let airDrop = page(.airDrop)
        pane.host.showSystemPage(airDrop)
        pane.stopBackgroundWork()
        #expect(airDrop.stopped)
        #expect(pane.host.systemPage == nil)
        #expect(!pane.browser.view.isHidden)
    }

    @Test func systemDestinationsParticipateInHistoryAndHaveMatchingTitles() throws {
        var history = PaneHistory()
        let folder = Destination.folder(URL(fileURLWithPath: "/tmp"))
        history.leave(folder)
        history.leave(.systemLocation(.network))
        #expect(history.step(.back, from: .systemLocation(.airDrop)) == .systemLocation(.network))
        #expect(history.step(.back, from: .systemLocation(.network)) == folder)
        #expect(history.step(.forward, from: folder) == .systemLocation(.network))
        for location in SidebarSystemLocation.allCases {
            let title = try #require(ResultsTitle(.systemLocation(location)))
            #expect(title.window == location.title)
            #expect(title.symbol == location.symbol)
        }
    }
}
