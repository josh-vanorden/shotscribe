import SwiftUI
import AppKit
import ShotScribeCore
import ShotScribeUI

/// Owns the model. An `NSApplicationDelegateAdaptor` (not `@StateObject` on
/// the App) because the adaptor is instantiated **at launch** — a
/// `@StateObject` referenced only inside the MenuBarExtra content closure
/// isn't created until the menu first opens, which would mean no folder
/// watching until the first click. Found the hard way.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = ShotScribeModel()
    let presence = PresenceController.shared

    /// The Library: the one surface that truly needs a window. The app's own
    /// `NSWindow` rather than a SwiftUI scene, so it opens from the Dock, the
    /// menu, the card and a relaunch alike — and stays shut at launch when
    /// ShotScribe lives in the menu bar only.
    private(set) lazy var library = HostedWindow(
        title: "ShotScribe", autosaveName: "ShotScribeLibrary", legacyAutosaveName: "shotscribe.main",
        size: CGSize(width: 900, height: 860), minSize: CGSize(width: 620, height: 520)) { [model] in
        AnyView(ShotScribeView(model: model, chrome: .hosted).frame(minWidth: 620, minHeight: 520))
    }

    private(set) lazy var settings = HostedWindow(
        title: "ShotScribe Settings", autosaveName: "ShotScribeSettings",
        size: CGSize(width: 400, height: 240)) { [model, presence] in
        AnyView(PresenceSettings(presence: presence, model: model))
    }

    /// The card that slides up when the watcher names a capture. Started here,
    /// in the app — `ShotScribeUI` must never put a panel on a host's screen by
    /// itself. Its "Go to Library" is handed in because only the app knows how.
    private lazy var captureCard = CaptureCardPresenter(model: model) { [weak self] in self?.library.show() }

    /// The editor's windows. Started here for the same reason the card is.
    private lazy var editor = EditorPresenter(model: model)

    static let libraryOpenAtQuitKey = "shotscribe.libraryOpenAtQuit"

    /// The Dock icon, or not, before anything can appear.
    func applicationWillFinishLaunching(_ notification: Notification) {
        presence.applyAtLaunch()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ShotScribeDefaults.appearance().apply()
        captureCard.start()
        editor.start()
        // As a Dock app it comes up the way it always has: with the Library,
        // unless it was closed when ShotScribe last quit. In the menu bar only,
        // launch is silent — the Library opens when asked for.
        let suite = ShotScribeDefaults.suite
        let wasOpen = suite.object(forKey: Self.libraryOpenAtQuitKey) == nil || suite.bool(forKey: Self.libraryOpenAtQuitKey)
        if presence.value.dock, wasOpen { library.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ShotScribeDefaults.suite.set(library.isOpen, forKey: Self.libraryOpenAtQuitKey)
    }

    /// Clicking the Dock icon, or launching again from Spotlight or Finder —
    /// which is also a way in when there is no Dock icon — opens the Library.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        library.show()
        return false
    }

    /// Closing the Library is not quitting: the whole point is a watcher that
    /// outlives the window it is configured from. Quit is Cmd-Q, the app menu,
    /// or "Quit ShotScribe" in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// ShotScribe — a Library you can actually look at, and a menu bar item that
/// keeps watching once you close it. Either can be switched off in Settings;
/// never both.
@main
struct ShotScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var presence = PresenceController.shared

    var body: some Scene {
        MenuBarExtra("ShotScribe", systemImage: "text.viewfinder", isInserted: presence.menuBarBinding) {
            ShotScribeMenu(model: delegate.model,
                           goToLibrary: { delegate.library.show() },
                           openSettings: { delegate.settings.show() },
                           quit: { NSApplication.shared.terminate(nil) })
        }
        .menuBarExtraStyle(.menu)
        .commands {
            // With a Dock icon there is an app menu, and Settings belongs in it.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { delegate.settings.show() }.keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .windowList) {
                Button("Library") { delegate.library.show() }.keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
