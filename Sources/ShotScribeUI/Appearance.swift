import AppKit
import ShotScribeCore

extension ShotScribeDefaults.Appearance {
    /// Put it on the whole app at once: the window, the editor, the capture
    /// card and the menu-bar panel all take the app's appearance.
    @MainActor public func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
