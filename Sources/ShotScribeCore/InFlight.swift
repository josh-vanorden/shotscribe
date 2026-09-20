import Foundation

/// **A durable record that a rename is underway.**
///
/// Today, a capture interrupted mid-rename — the app quits while the titler
/// is still thinking — leaves no trace that anything was ever attempted: the
/// file is still sitting under its raw macOS name, so it silently joins the
/// backlog like any other never-touched capture, with no memory that a rename
/// was started and abandoned. This is that memory.
///
/// `Renamer.rename` writes a record here *before* the slow work (OCR +
/// titling) starts, and clears it once the attempt is over — renamed, skipped,
/// or failed — via `defer`, so nothing on the normal return path can skip the
/// clear. Only a real crash, where no `defer` runs at all, leaves a record
/// behind, which is exactly the case this exists to catch: a fresh process
/// reads what the dead one wrote and can retry it. `Backlog` (p1b) is the
/// reader; it treats a leftover record the way it treats a raw capture name,
/// but now with a start time to say how long it has been stuck.
///
/// **Where it lives:** `~/.shotscribe/inflight.json`, beside `ShotIndex`'s
/// `~/.shotscribe/index.json`. Both are ShotScribe's own bookkeeping about
/// captures, not a user-facing asset the operator brought in (that is
/// `KeptPictures`, under Application Support) — so this follows the index's
/// convention rather than starting a second one.
///
/// **Kept small, on purpose:** a path and a timestamp. Enough for `Backlog` to
/// name the capture and say how stale the attempt is; anything more (the
/// label so far, the step reached) would need a reason this decision doesn't
/// have yet.
public enum InFlight {
    /// One capture mid-rename: which one, and when work on it began.
    public struct Record: Codable, Equatable, Sendable {
        public var path: String
        public var startedAt: Date

        public init(path: String, startedAt: Date) {
            self.path = path
            self.startedAt = startedAt
        }
    }

    struct Store: Codable {
        var version: Int = 1
        var records: [String: Record] = [:]
    }

    /// Tests point this at a scratch file, so they never touch the operator's
    /// real state — the same seam as `ShotIndex.storeOverride`.
    public static var storeOverride: URL?

    public static var storeURL: URL {
        storeOverride ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".shotscribe/inflight.json")
    }

    /// Every load-modify-save goes through this, the same reason
    /// `ShotIndex` does: two renames finishing close together must not race
    /// each other's read-modify-write and drop a record.
    private static let lock = NSLock()

    /// Record that `url` is about to be worked on. Call before the slow part
    /// (OCR + titling) starts, never after. Idempotent — recording the same
    /// URL again just refreshes the timestamp, which is harmless since a
    /// retry starting over is exactly what should reset the clock.
    public static func begin(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        var store = load()
        store.records[url.path] = Record(path: url.path, startedAt: Date())
        save(store)
    }

    /// Forget `url` — the attempt is over, whatever the outcome. Safe to call
    /// even when there is nothing to clear (a URL never begun, or cleared
    /// already), so a caller never needs to check first.
    public static func end(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        var store = load()
        guard store.records.removeValue(forKey: url.path) != nil else { return }
        save(store)
    }

    /// Every capture currently recorded as mid-rename, oldest first — what
    /// `Backlog` reads to find one an interrupted process never got back to.
    public static func records() -> [Record] {
        load().records.values.sorted { $0.startedAt < $1.startedAt }
    }

    private static func load() -> Store {
        guard let data = try? Data(contentsOf: storeURL) else { return Store() }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(Store.self, from: data)) ?? Store()
    }

    private static func save(_ store: Store) {
        let dir = storeURL.deletingLastPathComponent()
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        // Seal the folder before any bytes land in it, the same reason
        // `ShotIndex.save` does: `createDirectory` only applies permissions
        // when it creates, so a folder from an older build could still be
        // traversable while the atomic write's temp file sits inside it.
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(store) else { return }
        try? data.write(to: storeURL, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
    }
}
