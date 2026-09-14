import AppKit
import Foundation
import Vision

/// A searchable index of what your screenshots actually say.
///
/// ShotScribe already reads every screenshot — that is how it names them — and
/// then throws the text away, keeping a three-word title. A title is a thin hook
/// a month later: you remember the error message, the hostname, the ticket
/// number, and none of those are in "Real Belt Rail".
///
/// ## Why this OCRs again rather than reusing the label's text
///
/// `OCR.recognizeText` is tuned for *labelling*: `.fast` recognition, no
/// language correction, capped at 900 characters. Right for a title, wrong for
/// search — 900 characters stops partway down most screenshots, and `.fast`
/// misreads precisely the strings you would search for (`i-0a3f`, `NXDOMAIN`,
/// `PROJ-4821`). The index pays for an accurate pass once per file. It is local
/// Vision, so the cost is time on your own machine, not money or privacy.
///
/// ## Where it lives, and why that matters
///
/// `~/.shotscribe/index.json`, never inside the watched folder and never in a
/// repo. **The index is more sensitive than the screenshots it describes.**
/// Tokens, hostnames and customer names get caught in screenshots in passing;
/// in a PNG they are buried in pixels, and in an index they are greppable and
/// durable. It stays on this machine, like everything else ShotScribe does.
public struct IndexedShot: Codable, Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var captured: Date
    public var indexed: Date
    /// Byte size at index time — a cheap way to notice a file changed underneath.
    public var size: Int64
    public var text: String
    /// The raw capture name this shot arrived with, when ShotScribe renamed
    /// it — what an undo puts back. nil for a shot that was never renamed here.
    public var original: String? = nil

    /// The Finder tags on the file when it was last read. A cache, not the
    /// record: the file carries the tags, and a sweep re-reads them, so a tag
    /// added by hand in Finder turns up here too.
    ///
    /// Optional so an index written before tags existed still decodes — a
    /// non-optional would throw, and `load`'s `try?` would quietly hand back an
    /// empty store, costing the operator their whole index.
    public var tags: [String]? = nil

    public var url: URL { URL(fileURLWithPath: path) }
}

public struct SearchHit: Identifiable, Equatable, Sendable {
    public var id: String { shot.path }
    public var shot: IndexedShot
    public var score: Double
    /// The matched text in context, for showing why this result is here.
    public var snippet: String
    public var matchedInName: Bool
}

public enum ShotIndex {

    public struct Store: Codable, Sendable {
        public var version: Int = 1
        public var shots: [String: IndexedShot] = [:]
    }

    /// Overrides `indexURL`. **Exists so tests do not write to the real index.**
    ///
    /// There was no seam here, so exercising `reindex` meant mutating
    /// `~/.shotscribe/index.json` — the operator's actual searchable history.
    /// A first run of the new sweep tests put 42 temp-folder entries into it
    /// (2026-08-24). Data a test can reach is data a test will eventually
    /// corrupt; the fix is a seam, not care.
    public static var storeOverride: URL?

    /// Every load-modify-save goes through this. `reindex` used to hold a
    /// store across minutes of OCR and then save it, so a capture renamed and
    /// recorded meanwhile was overwritten — and with it the original name that
    /// makes its undo possible (QA, 2026-09-04).
    private static let lock = NSLock()

    public static var indexURL: URL {
        if let override = storeOverride { return override }
        // An escape hatch for trying the CLI against a scratch folder: without
        // it, one exploratory `shotscribe index /tmp/…` writes those files into
        // the operator's real searchable history, where they linger.
        if let path = ProcessInfo.processInfo.environment["SHOTSCRIBE_INDEX"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".shotscribe/index.json")
    }

    // MARK: - Persistence

    public static func load() -> Store {
        guard let data = try? Data(contentsOf: indexURL) else { return Store() }
        let dec = JSONDecoder()
        // Must match `save`. A plain decoder expects the default numeric date
        // format, so it threw on every ISO-8601 field and `try?` turned that
        // into an empty store — leaving "indexed 125" and "found 0" both
        // looking correct.
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(Store.self, from: data)) ?? Store()
    }

    public static func save(_ store: Store) {
        let dir = indexURL.deletingLastPathComponent()
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        // Seal the folder BEFORE any bytes land in it: `createDirectory` only
        // applies its permissions when it creates, so a folder made by an
        // older build could still be traversable while `.atomic`'s adjacent
        // temp file (default permissions) and the fresh index sit inside it.
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(store) {
            try? data.write(to: indexURL, options: .atomic)
            // The index is the most sensitive thing ShotScribe writes — text
            // caught in passing, greppable — so it is readable by its owner
            // only, and an index written before this rule is tightened on the
            // next save. `.atomic` writes a fresh file, so this runs every time.
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
        }
    }

    // MARK: - Reading a screenshot properly

    /// Accurate OCR for search. Synchronous — call it off the main thread.
    public static func searchText(atPath path: String, maxChars: Int = 8_000) -> String {
        // A still is one frame; a recording is a couple, so the text of a
        // screen someone recorded is as findable as one they captured.
        var lines: [String] = []
        for cg in OCR.frames(atPath: path) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false   // hostnames and IDs are not words
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            guard (try? handler.perform([request])) != nil else { continue }
            lines += (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }
        return String(lines.joined(separator: "\n").prefix(maxChars))
    }

    // MARK: - Building

    public static func imageFiles(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        return urls.filter(Capture.isCapture)
    }

    /// Index every screenshot in `folder` that is not already current.
    ///
    /// Indexes the **folder**, not ShotScribe's rename history: that history is
    /// capped and holds no paths, so a search built on it would only ever see
    /// the most recent handful. The folder is the source of truth.
    @discardableResult
    public static func reindex(folder: URL, force: Bool = false,
                               progress: ((Int, Int) -> Void)? = nil) -> (indexed: Int, skipped: Int, pruned: Int) {
        let snapshot = load()          // read-only: decides what to skip
        let files = imageFiles(in: folder)
        var indexed = 0, skipped = 0
        var updates: [String: IndexedShot] = [:]

        for (i, url) in files.enumerated() {
            progress?(i + 1, files.count)
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            let tags = Tagging.finderTags(of: url)
            if !force, let existing = snapshot.shots[url.path], existing.size == size {
                // Tags change without the bytes changing — somebody files a shot
                // in Finder — and re-reading them is one syscall against the OCR
                // this branch exists to skip. So they refresh even here.
                if existing.tags ?? [] != tags {
                    var refreshed = existing
                    refreshed.tags = tags
                    updates[url.path] = refreshed
                }
                skipped += 1; continue
            }
            let text = searchText(atPath: url.path)
            let captured = (attrs?[.creationDate] as? Date)
                ?? (attrs?[.modificationDate] as? Date) ?? Date()
            updates[url.path] = IndexedShot(
                path: url.path, name: url.deletingPathExtension().lastPathComponent,
                captured: captured, indexed: Date(), size: size, text: text,
                original: nil, tags: tags)
            indexed += 1
        }

        // Merge onto whatever the store says NOW, under the lock — a record
        // made during the sweep survives, and so does its original name.
        lock.lock(); defer { lock.unlock() }
        var store = load()
        for (path, shot) in updates {
            var merged = shot
            merged.original = store.shots[path]?.original
            store.shots[path] = merged
        }

        // A renamed or deleted file leaves a stale entry pointing nowhere.
        //
        // **Compare resolved paths.** `contentsOfDirectory` hands back
        // symlink-resolved URLs, so a key is stored as `/private/var/…` while
        // the caller's `folder.path` may still read `/var/…`. The prefix test
        // then matches nothing and the prune silently does nothing — stale
        // entries accumulate for deleted screenshots and search keeps returning
        // them. Found 2026-08-24 by a test whose temp folder took exactly that
        // form; `/Users/…` paths hid it because they resolve to themselves.
        // **Canonicalise the folder through the filesystem.**
        //
        // Keys are stored from `imageFiles`, and `contentsOfDirectory` hands back
        // canonical URLs — `/private/var/…`. The caller's `folder` may still say
        // `/var/…`, so the prefix test matched nothing and the prune silently did
        // nothing: deleted screenshots stayed searchable forever. Measured
        // 2026-08-24, none of `resolvingSymlinksInPath()`, `standardizedFileURL`
        // or `NSString.resolvingSymlinksInPath` performs that mapping — only
        // asking the filesystem does. `/Users/…` folders hid the bug because they
        // are already canonical.
        let root = (try? folder.resourceValues(forKeys: [.canonicalPathKey]))?
            .canonicalPath ?? folder.path
        let live = Set(files.map(\.path))
        let dead = store.shots.keys.filter { !live.contains($0) && $0.hasPrefix(root) }
        dead.forEach { store.shots.removeValue(forKey: $0) }

        save(store)
        return (indexed, skipped, dead.count)
    }

    /// Record one screenshot immediately — used right after a rename, so a shot
    /// is findable the moment it is named rather than at the next sweep.
    public static func record(_ url: URL, original: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        var store = load()
        // Key by the canonical path, as `reindex` does. `record` used to key by
        // whatever path it was handed, so under `/var/…` (which the filesystem
        // spells `/private/var/…`) a later sweep found no existing entry, built
        // a second one, and the original name rode along with neither. Caught
        // by the undo test on 2026-09-03; `/Users/…` paths had hidden it.
        let path = canonicalPath(url)
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        store.shots[path] = IndexedShot(
            path: path, name: url.deletingPathExtension().lastPathComponent,
            captured: (attrs?[.creationDate] as? Date) ?? Date(), indexed: Date(),
            size: (attrs?[.size] as? NSNumber)?.int64Value ?? 0,
            text: searchText(atPath: url.path), original: original,
            tags: Tagging.finderTags(of: url))
        save(store)
    }

    /// Drop an entry whose file has moved away under a rename.
    public static func forget(_ path: String) { forget([path]) }

    /// What the filesystem calls `url`, which is what the index keys by. A
    /// file that no longer exists cannot be asked, so its path is used as given.
    static func canonicalPath(_ url: URL) -> String {
        (try? url.resourceValues(forKeys: [.canonicalPathKey]))?.canonicalPath ?? url.path
    }

    /// Drop several at once — one load and one save, not one per shot.
    public static func forget(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var store = load()
        for p in paths {
            store.shots.removeValue(forKey: p)
            // The file is usually gone by now, so the canonical form cannot be
            // asked for; try the one spelling the filesystem is known to use.
            if p.hasPrefix("/var/") { store.shots.removeValue(forKey: "/private" + p) }
        }
        save(store)
    }

    // MARK: - Searching

    /// Rank by where the query matched, then how recent the shot is.
    ///
    /// The **name is weighted above the body** on purpose: it is the one part a
    /// human (or the titler) chose deliberately, so a hit there is far more
    /// likely to be the shot you meant than an incidental word on screen.
    public static func search(_ query: String, in store: Store? = nil, limit: Int = 50) -> [SearchHit] {
        let store = store ?? load()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let terms = q.split(separator: " ").map(String.init).filter { !$0.isEmpty }

        var hits: [SearchHit] = []
        for shot in store.shots.values {
            let name = shot.name.lowercased()
            let body = shot.text.lowercased()
            // A tag was chosen for this shot deliberately, so it ranks with the
            // name rather than with text that merely passed across the screen.
            let tags = (shot.tags ?? []).map { $0.lowercased() }
            var score = 0.0
            var matchedName = false

            if name.contains(q) { score += 100; matchedName = true }
            if tags.contains(q) { score += 90 }
            if body.contains(q) { score += 40 }
            let inName = terms.filter { name.contains($0) }.count
            let inTags = terms.filter { tags.contains($0) }.count
            let inBody = terms.filter { body.contains($0) }.count
            if inName == terms.count { score += 50; matchedName = true }
            if inTags == terms.count { score += 45 }
            if inBody == terms.count { score += 25 }
            score += Double(inName) * 8 + Double(inTags) * 8 + Double(inBody) * 3

            guard score > 0 else { continue }
            hits.append(SearchHit(shot: shot, score: score,
                                  snippet: snippet(of: shot.text, matching: terms),
                                  matchedInName: matchedName))
        }
        return hits.sorted {
            $0.score == $1.score ? $0.shot.captured > $1.shot.captured : $0.score > $1.score
        }.prefix(limit).map { $0 }
    }

    /// The matched text with a little room either side, so a result explains
    /// itself instead of asking you to open the file to find out why it matched.
    static func snippet(of text: String, matching terms: [String], window: Int = 70) -> String {
        let lower = text.lowercased()
        guard let term = terms.first(where: { lower.contains($0) }),
              let r = lower.range(of: term) else {
            return String(text.prefix(window * 2)).replacingOccurrences(of: "\n", with: " ")
        }
        let start = text.index(r.lowerBound, offsetBy: -window, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(r.upperBound, offsetBy: window, limitedBy: text.endIndex) ?? text.endIndex
        var s = String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if start != text.startIndex { s = "…" + s }
        if end != text.endIndex { s += "…" }
        return s
    }
}
