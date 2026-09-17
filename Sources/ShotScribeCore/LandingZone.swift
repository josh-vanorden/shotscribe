import Foundation

/// How the landing zone under the latest capture is laid out: which action
/// tiles the row shows, in what order, and how often each one has been used.
///
/// **The order is stored as names, never indices.** A tile a later version
/// adds then appears in the row instead of shifting everything after it, and a
/// tile a later version drops is ignored instead of leaving a hole.
/// `resolve(order:)` is the one place that reconciles what is stored with what
/// this build knows about — the same forgiving shape `IndexedShot.tags` has,
/// and for the same reason: a settings file written by another version must
/// never be the thing that empties the row.
///
/// **Hidden is a set beside the order, not a removal.** A tile put away keeps
/// its place, so bringing it back returns it where it was rather than at the
/// end.
///
/// **The counts are a tally on this Mac.** They answer the only question that
/// use can answer — which tiles earn their room — and they live in this app's
/// own preferences. Nothing counts them anywhere else and nothing leaves the
/// machine.
public struct LandingZone: Equatable, Sendable {
    /// Every action the landing zone can offer. The declaration order is the
    /// row as it ships, and the order a reset returns to.
    /// **`rebuild` was a tile of its own until 2026-09-15.** It and `sendTo`
    /// hand the same shot to the same assistant — one saying "look at this",
    /// the other "rebuild this layout as code" — so they are two jobs with one
    /// destination, and they now share one mark: Rebuild sits under Send to's
    /// right-click. A stored order still naming it is simply ignored, which is
    /// what `resolve` is for.
    ///
    /// **`markUp` is Edit with ShotScribe** since 2026-09-16: it opens ShotScribe's
    /// own editor, and Preview sits under its right-click.
    public enum Tile: String, CaseIterable, Codable, Sendable {
        case reveal, markUp, share, sendTo, editTitle, fileAs
    }

    public static let shipped: [Tile] = Tile.allCases

    /// Every tile exactly once, hidden ones included.
    public private(set) var order: [Tile]
    public private(set) var hidden: Set<Tile>
    private var counts: [Tile: Int]

    public init(order: [Tile] = LandingZone.shipped,
                hidden: Set<Tile> = [],
                uses: [Tile: Int] = [:]) {
        self.order = LandingZone.complete(order)
        // A stored set that hides everything would leave a row with nothing to
        // right-click, and right-click is the way back in. Refuse it.
        self.hidden = hidden.count >= self.order.count ? [] : hidden
        self.counts = uses
    }

    /// The tiles the row actually shows.
    public var visible: [Tile] { order.filter { !hidden.contains($0) } }

    public var uses: [Tile: Int] { counts }
    public func uses(of tile: Tile) -> Int { counts[tile] ?? 0 }

    /// One more use of this tile, from wherever it was reached — the row, the
    /// right-click menu, or a plain click that has this action as its default.
    public mutating func note(_ tile: Tile) { counts[tile, default: 0] += 1 }

    /// Puts a tile away, or brings it back. Hiding the **last** visible tile is
    /// refused: the row's own right-click is how arranging is reached, and an
    /// empty row has nothing to right-click.
    @discardableResult
    public mutating func setHidden(_ tile: Tile, _ away: Bool) -> Bool {
        if away {
            guard visible.count > 1 else { return false }
            hidden.insert(tile)
        } else {
            hidden.remove(tile)
        }
        return true
    }

    /// Moves a tile to where another one sits — what dragging one tile onto a
    /// neighbour means. Dragging right lands after the neighbour, dragging
    /// left lands in its place; both read as "put it here".
    public mutating func move(_ tile: Tile, onto other: Tile) {
        guard tile != other,
              let from = order.firstIndex(of: tile),
              let target = order.firstIndex(of: other) else { return }
        order.remove(at: from)
        guard let landing = order.firstIndex(of: other) else { return }
        order.insert(tile, at: from < target ? landing + 1 : landing)
    }

    /// Back to the row ShotScribe ships. The counts stay: the arrangement is
    /// the setting, the tally is evidence about it.
    public mutating func reset() {
        order = LandingZone.shipped
        hidden = []
    }

    /// Known names in the order they were stored, then everything this build
    /// knows that the stored list did not carry.
    public static func resolve(order stored: [String]) -> [Tile] {
        complete(stored.compactMap(Tile.init(rawValue:)))
    }

    private static func complete(_ partial: [Tile]) -> [Tile] {
        var out: [Tile] = []
        for tile in partial where !out.contains(tile) { out.append(tile) }
        for tile in shipped where !out.contains(tile) { out.append(tile) }
        return out
    }
}
