import SwiftUI
import AppKit
import ShotScribeUI

/// Owns the model. An `NSApplicationDelegateAdaptor` (not `@StateObject` on
/// the App) because the adaptor is instantiated **at launch** — a
/// `@StateObject` referenced only inside the MenuBarExtra content closure
/// isn't created until the panel first opens, which would mean no folder
/// watching until the first click. Found the hard way.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = ShotScribeModel()

    /// Clicking the Dock icon, or launching again from Spotlight, brings the
    /// window back. SwiftUI keeps a closed `Window` scene around, so ordering
    /// the existing one front is enough; returning true lets AppKit restore it
    /// on the first launch after a quit, when there is nothing to order yet.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// Closing the window is not quitting: the whole point is a watcher that
    /// outlives the window it is configured from. Quit is Cmd-Q, the app menu,
    /// or "Quit" in the menu bar panel.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// ShotScribe — a window you can actually look at, and a menu bar item that
/// keeps watching once you close it.
///
/// It was menu-bar-only until 2026-09-11, which meant the roomy surface (Keep,
/// Name, File, search, the tiles) had no home outside a host like Toolbelt: the
/// popover only ever showed the toggles and the recent list.
@main
struct ShotScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    static let mainWindowID = "shotscribe.main"

    var body: some Scene {
        Window("ShotScribe", id: Self.mainWindowID) {
            ShotScribeView(model: delegate.model, chrome: .hosted)
                .frame(minWidth: 620, minHeight: 520)
        }
        .defaultSize(width: 900, height: 860)

        MenuBarExtra("ShotScribe", systemImage: "text.viewfinder") {
            MenuBarPanel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The popover, plus the one thing it cannot do for itself: open the window.
/// `openWindow` is an environment value, so it has to be read inside a view —
/// and it stays in the app target, since `ShotScribeUI` must never know what is
/// hosting it.
private struct MenuBarPanel: View {
    @ObservedObject var model: ShotScribeModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ShotScribeView(model: model, chrome: .menuBar) {
            openWindow(id: ShotScribeApp.mainWindowID)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
