import AppKit
import SwiftUI
import ShotScribeCore
import ShotScribeUI

/// **Dock, menu bar, or both — applied live.** The rule (never neither) is
/// `Presence`'s; this puts a choice on the running app: the activation policy
/// for the Dock, a binding for the menu bar item, and the one line said when
/// the Dock icon goes away mid-session.
@MainActor
final class PresenceController: ObservableObject {
    static let shared = PresenceController()

    @Published private(set) var value = ShotScribeDefaults.presence()
    /// "The Library now opens from the menu bar." — shown where the switch was
    /// flipped, and gone again by itself.
    @Published private(set) var notice: String?
    private var noticeTask: Task<Void, Never>?

    /// Before any window: the bundle starts as an agent (`LSUIElement`), and a
    /// Dock app is what it becomes here — never the other way round, which
    /// would flash a Dock icon on every menu-bar-only launch.
    func applyAtLaunch() {
        NSApp.setActivationPolicy(value.dock ? .regular : .accessory)
    }

    func set(_ part: Presence.Part, _ on: Bool) {
        let next = value.setting(part, on)
        guard next != value else { return }
        let hadDock = value.dock
        let key = NSApp.keyWindow
        value = next
        ShotScribeDefaults.setPresence(next)
        guard hadDock != next.dock else { return }

        NSApp.setActivationPolicy(next.dock ? .regular : .accessory)
        // A policy change drops the app's focus; whatever was in front — the
        // Settings window, the Library behind it — comes straight back.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            key?.makeKeyAndOrderFront(nil)
        }
        if !next.dock { say("The Library now opens from the menu bar.") }
        else { notice = nil; MenuBarPointer.dismiss() }
    }

    /// For the menu bar item's `isInserted`: macOS writes false when the item
    /// is dragged out of the menu bar, and the same guard answers.
    var menuBarBinding: Binding<Bool> {
        Binding(get: { self.value.menuBar }, set: { self.set(.menuBar, $0) })
    }

    private func say(_ line: String) {
        notice = line
        MenuBarPointer.show(line)
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}

/// A small callout under ShotScribe's menu bar icon. `MenuBarExtra` does not
/// hand out its status item, so the icon is found by its window — the app's
/// one status-bar window — and if that is ever not there, nothing is shown:
/// the line in Settings has already said it.
@MainActor
enum MenuBarPointer {
    private static var panel: NSPanel?
    private static var dismissal: Task<Void, Never>?

    static func show(_ text: String, for seconds: Double = 7) {
        dismiss()
        // The item may have just been inserted; give the menu bar a beat.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // One status window per display; the one on the display being
            // looked at — where Settings is — is the one to point at.
            let items = NSApp.windows.filter { $0.className.contains("StatusBar") && $0.isVisible && $0.frame.height <= 40 }
            let looking = NSApp.keyWindow?.screen ?? NSScreen.main
            guard let item = items.first(where: { $0.screen == looking }) ?? items.first else { return }
            let host = NSHostingView(rootView: Callout(text: text))
            let size = host.fittingSize
            let anchor = item.frame
            let screen = item.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            var x = anchor.midX - size.width / 2
            x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
            let frame = NSRect(x: x, y: anchor.minY - size.height - 2, width: size.width, height: size.height)
            let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.level = .statusBar; p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .transient]
            host.frame = NSRect(origin: .zero, size: size)
            p.contentView = host
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; p.animator().alphaValue = 1 }
            panel = p
            dismissal = Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                dismiss()
            }
        }
    }

    static func dismiss() {
        dismissal?.cancel(); dismissal = nil
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 },
                                             completionHandler: { p.orderOut(nil) })
    }

    private struct Callout: View {
        let text: String
        var body: some View {
            VStack(spacing: 0) {
                Image(systemName: "arrowtriangle.up.fill").font(.system(size: 9))
                    .foregroundStyle(Color.accentColor)
                Text(text).font(.callout.weight(.medium)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .padding(6)
            .fixedSize()
        }
    }
}

/// Settings: where ShotScribe lives, and whether it starts with the Mac.
struct PresenceSettings: View {
    @ObservedObject var presence: PresenceController
    @ObservedObject var model: ShotScribeModel

    var body: some View {
        Form {
            Section {
                toggle("Show in Dock", .dock)
                toggle("Show in menu bar", .menuBar)
                Text(presence.notice ?? "One of the two is always on, so ShotScribe can always be reached.")
                    .font(.caption)
                    .foregroundStyle(presence.notice == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeOut(duration: 0.2), value: presence.notice)
            }
            Section {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin },
                                                        set: { model.setLaunchAtLogin($0) }))
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The last one on is disabled rather than refused: a checkbox that
    /// cannot be unticked says why without an alert.
    private func toggle(_ title: String, _ part: Presence.Part) -> some View {
        Toggle(title, isOn: Binding(get: { presence.value.isOn(part) }, set: { presence.set(part, $0) }))
            .disabled(presence.value.isOn(part) && !presence.value.canTurnOff(part))
            .help(presence.value.isOn(part) && !presence.value.canTurnOff(part)
                  ? "This is the only way in right now — turn the other one on first." : "")
    }
}
