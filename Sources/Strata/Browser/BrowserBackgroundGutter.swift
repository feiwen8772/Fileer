import AppKit

extension BrowserViewController {
    func backgroundContextMenu() -> NSMenu? {
        view.window?.makeFirstResponder(focusView)
        if effectiveMode == .columns { return columnController?.backgroundContextMenu() }
        select([], scroll: false)
        return makeContextMenu()
    }
}
