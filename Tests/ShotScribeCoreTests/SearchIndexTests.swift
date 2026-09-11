import XCTest
@testable import ShotScribeCore

final class SearchIndexTests: XCTestCase {

    private func shot(_ name: String, _ text: String, daysAgo: Int = 0) -> IndexedShot {
        IndexedShot(path: "/tmp/\(name).png", name: name,
                    captured: Date().addingTimeInterval(TimeInterval(-86_400 * daysAgo)),
                    indexed: Date(), size: 1, text: text)
    }

    private func tagged(_ name: String, _ text: String, _ tags: [String]) -> IndexedShot {
        var shot = self.shot(name, text)
        shot.tags = tags
        return shot
    }

    private func store(_ shots: [IndexedShot]) -> ShotIndex.Store {
        var s = ShotIndex.Store()
        for x in shots { s.shots[x.path] = x }
        return s
    }

    /// The whole point of the index: finding a capture by something that was
    /// never in its name.
    func testFindsTextThatIsNotInTheFilename() {
        let s = store([shot("Real Belt Rail", "mounted onstage Export Rendered 10:41")])
        let hits = ShotIndex.search("onstage", in: s)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.shot.name, "Real Belt Rail")
        XCTAssertFalse(hits.first!.matchedInName)
    }

    /// Filing is findable: the tag is nowhere in the name or the text.
    func testATagIsSearchable() {
        let s = store([tagged("Console output", "nothing relevant in this body", ["error"])])
        XCTAssertEqual(ShotIndex.search("error", in: s).count, 1)
    }

    /// A tag was chosen for the shot; body text merely crossed the screen.
    func testATagOutranksAPassingMentionInTheBody() {
        let s = store([
            tagged("Filed shot", "unrelated body text of a reasonable length", ["error"]),
            shot("Other shot", "an error appears somewhere in this long body text"),
        ])
        XCTAssertEqual(ShotIndex.search("error", in: s).first?.shot.name, "Filed shot")
    }

    /// An index written before tags existed has to load. A non-optional `tags`
    /// would throw here, and `load`'s `try?` would turn that into an empty
    /// store — the whole searchable history, silently gone.
    func testAnIndexWrittenBeforeTagsStillDecodes() throws {
        let json = Data("""
        {"version":1,"shots":{"/tmp/a.png":{"path":"/tmp/a.png","name":"a",\
        "captured":"2026-08-11T15:41:00Z","indexed":"2026-08-11T15:41:00Z",\
        "size":1,"text":"hello"}}}
        """.utf8)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let store = try dec.decode(ShotIndex.Store.self, from: json)
        XCTAssertEqual(store.shots["/tmp/a.png"]?.text, "hello")
        XCTAssertNil(store.shots["/tmp/a.png"]?.tags)
    }

    /// A hit in the name outranks a hit in the body: the name is the one part
    /// somebody chose deliberately.
    func testNameMatchesOutrankBodyMatches() {
        let s = store([
            shot("Random console", "a passing mention of jumpcloud in the logs"),
            shot("JumpCloud drift", "unrelated body text"),
        ])
        let hits = ShotIndex.search("jumpcloud", in: s)
        XCTAssertEqual(hits.first?.shot.name, "JumpCloud drift")
        XCTAssertTrue(hits.first!.matchedInName)
    }

    func testAllTermsBeatSomeTerms() {
        let s = store([
            shot("one", "certificate expired on the gateway"),
            shot("two", "certificate renewed"),
        ])
        let hits = ShotIndex.search("certificate expired", in: s)
        XCTAssertEqual(hits.first?.shot.name, "one")
    }

    /// A result has to explain itself, or you must open the file to learn why
    /// it matched.
    func testSnippetShowsTheMatchInContext() {
        let long = String(repeating: "padding ", count: 40) + "NXDOMAIN resolving vpn.internal " + String(repeating: "tail ", count: 40)
        let s = store([shot("dns", long)])
        let hit = ShotIndex.search("NXDOMAIN", in: s).first
        XCTAssertNotNil(hit)
        XCTAssertTrue(hit!.snippet.contains("NXDOMAIN"))
        XCTAssertTrue(hit!.snippet.hasPrefix("…"), "a mid-text match should show it is excerpted")
        XCTAssertLessThan(hit!.snippet.count, 200)
    }

    func testEmptyQueryReturnsNothingRatherThanEverything() {
        let s = store([shot("a", "text"), shot("b", "text")])
        XCTAssertTrue(ShotIndex.search("", in: s).isEmpty)
        XCTAssertTrue(ShotIndex.search("   ", in: s).isEmpty)
    }

    func testEqualScoresBreakTowardTheMoreRecentShot() {
        let s = store([shot("older", "gateway", daysAgo: 30), shot("newer", "gateway", daysAgo: 1)])
        XCTAssertEqual(ShotIndex.search("gateway", in: s).first?.shot.name, "newer")
    }

    /// The round trip that silently broke search once: the encoder wrote
    /// ISO-8601 dates and the decoder expected the numeric default, so `load`
    /// returned an empty store while indexing reported success.
    func testStoreSurvivesARoundTripToDisk() throws {
        var s = ShotIndex.Store()
        let one = shot("round trip", "findable text")
        s.shots[one.path] = one

        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(s)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(ShotIndex.Store.self, from: data)

        XCTAssertEqual(back.shots.count, 1)
        XCTAssertEqual(ShotIndex.search("findable", in: back).count, 1)
    }
}

/// The failure that made ShotScribe look broken when it was only logged out.
final class ClaudeTitlerErrorTests: XCTestCase {
    func testExpiredSessionGetsAnActionableMessage() {
        let e = ClaudeTitler.CLIError.failed("Failed to authenticate: OAuth session expired and could not be refreshed")
        XCTAssertEqual(e.errorDescription,
                       "Claude is signed out — run `claude` in a terminal to sign in again.")
    }

    func testOtherFailuresKeepTheirText() {
        let e = ClaudeTitler.CLIError.failed("model overloaded")
        XCTAssertEqual(e.errorDescription, "Claude CLI: model overloaded")
    }
}

/// The sweep that finds screenshots this app did not rename.
///
/// `reindex` was complete, correct, and **had no caller anywhere in the app**
/// for weeks — so the browser only ever held captures ShotScribe itself had
/// named, and pointing it at a folder of existing screenshots produced an empty
/// list with nothing to say why. These assert the behaviour the callers now
/// depend on.
final class ReindexSweepTests: XCTestCase {

    /// **Never the real index.** `ShotIndex` writes to `~/.shotscribe/index.json`
    /// by default — the operator's actual searchable history — so without this
    /// every run of these tests edits live data. The first run of them did
    /// exactly that, leaving 42 temp-folder entries behind.
    private var storeDir: URL!

    override func setUpWithError() throws {
        storeDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shotscribe-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        ShotIndex.storeOverride = storeDir.appendingPathComponent("index.json")
    }

    override func tearDownWithError() throws {
        ShotIndex.storeOverride = nil
        try? FileManager.default.removeItem(at: storeDir)
    }

    private func makeFolder() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shotscribe-sweep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Canonical, the only way that actually works: a temp dir is handed out
        // as `/var/…` and read back as `/private/var/…`, and none of the URL
        // resolution APIs bridge the two — only asking the filesystem does.
        let canon = (try? dir.resourceValues(forKeys: [.canonicalPathKey]))?.canonicalPath
        return canon.map { URL(fileURLWithPath: $0) } ?? dir
    }

    /// A one-pixel PNG: real enough to be an image file, cheap enough for a test.
    private func writeImage(_ url: URL) throws {
        let png: [UInt8] = [
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
            0x89,0x00,0x00,0x00,0x0A,0x49,0x44,0x41,0x54,0x78,0x9C,0x63,0x00,0x01,0x00,0x00,
            0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
            0x42,0x60,0x82]
        try Data(png).write(to: url)
    }

    /// Filing a shot by hand in Finder changes no bytes, so the sweep skips the
    /// file — but the tag still has to arrive, or the app would never see what
    /// the operator filed until something forced a whole re-read.
    func testASweepPicksUpATagAddedByHand() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("one.png")
        try writeImage(url)
        XCTAssertEqual(ShotIndex.reindex(folder: dir).indexed, 1)
        XCTAssertEqual(ShotIndex.load().shots[url.path]?.tags ?? [], [])

        Tagging.add(["error"], to: url)
        let second = ShotIndex.reindex(folder: dir)
        XCTAssertEqual(second.skipped, 1, "unchanged bytes, so the OCR is still skipped")
        XCTAssertEqual(ShotIndex.load().shots[url.path]?.tags ?? [], ["error"])
    }

    func testRecordingARenameCarriesTheFilesTags() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("2026-08-11 1541 Some Shot.png")
        try writeImage(url)
        Tagging.add(["dashboard"], to: url)
        ShotIndex.record(url, original: "Screenshot 2026-08-11 at 3.41.07 PM.png")
        XCTAssertEqual(ShotIndex.load().shots[url.path]?.tags ?? [], ["dashboard"])
    }

    /// The whole point: images already sitting in the folder get indexed.
    func testExistingScreenshotsAreIndexed() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        for n in ["one.png", "two.png", "three.png"] {
            try writeImage(dir.appendingPathComponent(n))
        }

        XCTAssertEqual(ShotIndex.imageFiles(in: dir).count, 3, "files must be on disk first")
        let result = ShotIndex.reindex(folder: dir)
        XCTAssertEqual(result.indexed, 3,
                       "pre-existing captures must be picked up (skipped=\(result.skipped))")
        XCTAssertEqual(result.skipped, 0)

        let store = ShotIndex.load()
        let indexed = store.shots.keys.filter { $0.hasPrefix(dir.path) }
        XCTAssertEqual(indexed.count, 3)
    }

    /// What makes calling this on every launch affordable: the second pass reads
    /// nothing. If this regresses, launch starts doing OCR over the whole folder
    /// every time.
    func testSecondSweepSkipsUnchangedFiles() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeImage(dir.appendingPathComponent("one.png"))

        XCTAssertEqual(ShotIndex.reindex(folder: dir).indexed, 1)
        let second = ShotIndex.reindex(folder: dir)
        XCTAssertEqual(second.indexed, 0, "unchanged files must not be re-read")
        XCTAssertEqual(second.skipped, 1)
    }

    /// `force` is what the manual re-scan button passes.
    func testForceReReadsEvenUnchangedFiles() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeImage(dir.appendingPathComponent("one.png"))

        _ = ShotIndex.reindex(folder: dir)
        XCTAssertEqual(ShotIndex.reindex(folder: dir, force: true).indexed, 1)
    }

    /// A deleted capture must not linger in search results.
    func testDeletedFilesArePruned() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gone = dir.appendingPathComponent("gone.png")
        try writeImage(gone)
        try writeImage(dir.appendingPathComponent("stays.png"))
        _ = ShotIndex.reindex(folder: dir)

        try FileManager.default.removeItem(at: gone)
        let after = ShotIndex.reindex(folder: dir)
        XCTAssertEqual(after.pruned, 1)
        XCTAssertFalse(ShotIndex.load().shots.keys.contains(gone.path))
    }

    /// Progress drives a visible readout, so it has to be reported per file.
    func testProgressIsReportedForEveryFile() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        for n in ["a.png", "b.png"] { try writeImage(dir.appendingPathComponent(n)) }

        var seen: [(Int, Int)] = []
        _ = ShotIndex.reindex(folder: dir) { i, n in seen.append((i, n)) }
        XCTAssertEqual(seen.count, 2)
        XCTAssertEqual(seen.last?.0, 2)
        XCTAssertEqual(seen.last?.1, 2)
    }
}

