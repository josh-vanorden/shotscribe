import Foundation

/// **Where ShotScribe can be reached from: the Dock, the menu bar, or both.**
///
/// Both by default, which is what every install before 1.7 had — so an upgrade
/// with nothing stored changes nothing. Never neither: an app with no Dock icon
/// and no menu bar item is running and unreachable, so the last one on cannot
/// be turned off. The guard lives here, not in the checkboxes, so every door
/// that writes the setting gets it.
public struct Presence: Equatable, Sendable {
    public enum Part: String, Sendable { case dock, menuBar }

    public private(set) var dock: Bool
    public private(set) var menuBar: Bool

    public static let both = Presence(dock: true, menuBar: true)

    /// Both off is not a state; it reads as both on — the default — rather
    /// than guessing which one was meant.
    public init(dock: Bool, menuBar: Bool) {
        if !dock && !menuBar { self.dock = true; self.menuBar = true }
        else { self.dock = dock; self.menuBar = menuBar }
    }

    public func isOn(_ part: Part) -> Bool { part == .dock ? dock : menuBar }

    /// Whether `part` may be switched off — not when it is the only one on.
    public func canTurnOff(_ part: Part) -> Bool {
        isOn(part) && isOn(part == .dock ? .menuBar : .dock)
    }

    /// This presence with `part` set — unchanged when that would leave neither.
    public func setting(_ part: Part, _ on: Bool) -> Presence {
        guard on || canTurnOff(part) else { return self }
        return part == .dock ? Presence(dock: on, menuBar: menuBar) : Presence(dock: dock, menuBar: on)
    }
}

extension ShotScribeDefaults {
    public static let showInDockKey = "shotscribe.showInDock"
    public static let showInMenuBarKey = "shotscribe.showInMenuBar"

    /// A key that was never stored is on: that is the whole migration.
    public static func presence() -> Presence {
        func on(_ key: String) -> Bool { suite.object(forKey: key) == nil ? true : suite.bool(forKey: key) }
        return Presence(dock: on(showInDockKey), menuBar: on(showInMenuBarKey))
    }

    public static func setPresence(_ presence: Presence) {
        suite.set(presence.dock, forKey: showInDockKey)
        suite.set(presence.menuBar, forKey: showInMenuBarKey)
    }
}
