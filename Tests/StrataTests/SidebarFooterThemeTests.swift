import AppKit
import Testing
@testable import Strata
@testable import StrataAI
@testable import StrataConnections
@testable import StrataDev
@testable import StrataFiles
@testable import StrataQueue
@testable import StrataModel
@testable import StrataSearch

extension ColorThemeTests {
    @Test func theKeyboardShortcutsFooterUsesTheSidebarBackground() throws {
        let saved = ThemeStyle.options, contrast = ThemeStyle.highContrast
        defer { ThemeStyle.apply(saved, windows: [], highContrast: contrast) }
        let environment = try IndependentEnvironment()
        let sidebar = SidebarViewController(services: environment.services)
        sidebar.loadViewIfNeeded()
        sidebar.view.frame = NSRect(x: 0, y: 0, width: 240, height: 700)
        sidebar.view.layoutSubtreeIfNeeded()
        let button = try #require(sidebar.spaceFooter.subviews.compactMap { $0 as? NSButton }.first {
            $0.action == #selector(AppDelegate.showShortcuts(_:))
        })
        let action = button.action
        for palette in ColorTheme.allCases {
            ThemeStyle.apply(ColorThemeOptions(palette: palette), windows: [], highContrast: false)
            ThemeStyle.refresh(sidebar.view)
            #expect(button.action == action && button.superview === sidebar.spaceFooter)
            #expect(button.title.isEmpty)
            #expect(sidebar.spaceFooter.frame.height == 36)
        }
    }
}
