import AppKit
import SwiftUI

/// A window the app owns outright — the Library, Settings — rather than a
/// SwiftUI scene. A `Window` scene opens itself at launch and can only be
/// opened from inside a view; in menu-bar-only mode the Library must *not*
/// open at launch, and the capture card, the Dock icon and the menu all have
/// to be able to open it from anywhere. One object, made on demand, kept when
/// closed so its size and place survive.
@MainActor
final class HostedWindow: NSObject, NSWindowDelegate {
    private let title: String
    private let autosaveName: String
    /// The name an earlier build kept this window's place under, adopted once.
    private let legacyAutosaveName: String?
    private let size: CGSize
    private let minSize: CGSize?
    private let content: () -> AnyView
    private(set) var window: NSWindow?

    init(title: String, autosaveName: String, legacyAutosaveName: String? = nil, size: CGSize,
         minSize: CGSize? = nil, content: @escaping () -> AnyView) {
        self.title = title; self.autosaveName = autosaveName; self.legacyAutosaveName = legacyAutosaveName
        self.size = size; self.minSize = minSize; self.content = content
    }

    var isOpen: Bool { window?.isVisible ?? false }

    /// Open it, or bring it forward. Activates the app explicitly: with no
    /// Dock presence nothing else will, and the window would open behind
    /// whatever is in front.
    func show() {
        let window = self.window ?? make()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if minSize != nil { style.insert(.resizable) }
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style,
                         backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: content())
        if let minSize { w.contentMinSize = minSize }
        w.delegate = self
        // Where it was last time. Once, that means where the SwiftUI scene it
        // replaces left it — an upgrade must not move anyone's window.
        let adopted = "\(autosaveName).adoptedSceneFrame"
        let defaults = UserDefaults.standard
        if let legacyAutosaveName, !defaults.bool(forKey: adopted), w.setFrameUsingName(legacyAutosaveName) {
            // Kept under the new name *before* autosave is switched on: naming
            // the autosave re-applies whatever is stored there, and would put
            // the window straight back where the new name last had it.
            w.saveFrame(usingName: autosaveName)
        } else if !w.setFrameUsingName(autosaveName) {
            w.center()
        }
        defaults.set(true, forKey: adopted)
        w.setFrameAutosaveName(autosaveName)
        self.window = w
        return w
    }
}
