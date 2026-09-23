import SwiftUI

/// ShotScribe's own colour.
///
/// It used `Color.accentColor` — the *system* accent — which meant its tint was
/// whatever the operator had set in System Settings, and matched the app's own
/// icon only by coincidence. Taking the colour from the icon means the tab, the
/// Dock and the artwork agree, and a machine with a green system accent no
/// longer makes ShotScribe look like a different app.
public enum ShotPalette {
    /// From this app's own icon (2026-08-24): the lavender of its head.
    /// Darkened a step in light mode so it holds against paper-white.
    public static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.447, green: 0.365, blue: 0.729, alpha: 1)   // #725DBA
            : NSColor(srgbRed: 0.361, green: 0.286, blue: 0.639, alpha: 1)
    })

    public static let warning = Color.orange

    /// The mark on the landing zone's default action — the tile a plain click
    /// performs. Green on purpose, not the accent: it has to be unmistakable
    /// at a glance, in light and dark alike, and the accent is what everything
    /// else already wears.
    public static let chosen = Color(nsColor: .systemGreen)

    /// The name on the capture card the moment it lands. Green, a step
    /// darker than the system's in light mode so it holds on glass over a
    /// bright desktop, a step lighter in dark so it is not the badge's fill
    /// again. The generic word is never set in it.
    public static let named = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.33, green: 0.87, blue: 0.43, alpha: 1)   // #54DE6E
            : NSColor(srgbRed: 0.09, green: 0.49, blue: 0.24, alpha: 1)   // #177D3D
    })
}
