import XCTest
@testable import ShotScribeCore

/// The two boundaries the QA pass of 2026-09-12 tightened: the index is the
/// owner's alone on disk, and a title cannot smuggle a path component.
final class HardeningTests: XCTestCase {

    func testTheIndexIsReadableByItsOwnerOnly() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("idx-\(UUID().uuidString)")
        ShotIndex.storeOverride = dir.appendingPathComponent("index.json")
        defer { ShotIndex.storeOverride = nil; try? FileManager.default.removeItem(at: dir) }
        ShotIndex.save(ShotIndex.Store())
        let file = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("index.json").path)
        let folder = try FileManager.default.attributesOfItem(atPath: dir.path)
        XCTAssertEqual((file[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o600)
        XCTAssertEqual((folder[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o700)
    }

    func testATitleCannotCarryAPathComponent() {
        XCTAssertEqual(Naming.sanitize("../../etc/passwd Title"), "etc passwd Title")
        XCTAssertEqual(Naming.sanitize(". .. ... Real"), "Real")
        XCTAssertEqual(Naming.sanitize("v1.5.0 notes"), "v1.5.0 notes", "dots inside a word are words")
    }

    /// `force` waives the raw-name rule for a capture; it never makes a PDF a
    /// capture. An MCP caller talked into `force: true` still cannot scramble
    /// arbitrary files.
    func testForceNeverRenamesAFileThatIsNotACapture() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("force-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("notes.pdf")
        try Data("%PDF-1.4".utf8).write(to: doc)
        let outcome = try await Renamer(titler: KeywordTitler()).rename(fileAt: doc, label: "Anything", force: true, dryRun: true)
        XCTAssertEqual(outcome, .skippedNotACapture(doc))
        XCTAssertTrue(FileManager.default.fileExists(atPath: doc.path))
    }

    /// A titler reply is untrusted — the model read whatever was on screen — so
    /// neither boundary lets a control or invisible-format character through: a
    /// bidi override (U+202E) makes Finder display a name backwards, and a raw
    /// ESC in a printed label can drive the terminal it lands in.
    func testALabelCannotSmuggleControlOrBidiCharacters() {
        XCTAssertEqual(Naming.sanitize("Report\u{202E}gnp.png"), "Report gnp.png")
        XCTAssertEqual(Naming.sanitize("Login\u{1B}[31m Page"), "Login [31m Page")
        XCTAssertEqual(Naming.sanitize("Foo\u{0}Bar"), "Foo Bar")
        XCTAssertEqual(LabelCleaner.clean("Slack\u{202E} Thread"), "Slack Thread")
        XCTAssertEqual(LabelCleaner.clean("Terminal\u{1B}[2J Output"), "Terminal [2J Output")
        // macOS's own narrow no-break space (U+202F, a space, not a control)
        // stays: capture-name detection depends on names keeping it.
        XCTAssertEqual(Naming.sanitize("3.16.12\u{202F}PM"), "3.16.12\u{202F}PM")
    }

    /// A titler's *failure text* is shown too — CLI stderr, panel, log — and a
    /// hostile endpoint's error body (or a child CLI's streams) could carry the
    /// same escapes a label can. `CommandRunner.printable` is the rule the
    /// three titlers apply before an error is thrown.
    func testFailureTextIsPrintableBeforeItIsShown() {
        XCTAssertEqual(CommandRunner.printable("boom\u{1B}[2J\u{1B}]0;owned\u{7}done"),
                       "boom [2J ]0;owned done")
        XCTAssertEqual(CommandRunner.printable("rate\u{202E}timil"), "rate timil")
        XCTAssertEqual(CommandRunner.printable("line one\nline two"), "line one line two")
        XCTAssertEqual(CommandRunner.printable("HTTP 500: upstream timeout"),
                       "HTTP 500: upstream timeout", "ordinary punctuation is untouched")
    }

    /// `stop()` must take the pending debounced scan with it: the dispatch
    /// source dies on cancel, but a scan already queued would fire up to half
    /// a second later and report a capture to a caller who said stop — the
    /// exact two-watchers-one-capture race the hosted copy stands down to
    /// avoid.
    func testAStoppedWatcherNeverReports() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fired = expectation(description: "a stopped watcher reported a file")
        fired.isInverted = true
        let watcher = FolderWatcher(directory: dir) { _ in fired.fulfill() }
        XCTAssertTrue(watcher.start())
        // A capture lands — the directory event fires, the scan gets queued —
        // and the caller stops the watch inside the debounce window.
        FileManager.default.createFile(
            atPath: dir.appendingPathComponent("Screenshot 2026-08-11 at 3.41.07 PM.png").path,
            contents: Data([0x89]))
        watcher.stop()
        wait(for: [fired], timeout: 1.2)
    }

    /// A folder made by an older build (default permissions) is sealed by the
    /// next save — before the bytes land, so the atomic temp file and the
    /// fresh index are never inside a traversable directory.
    func testSaveSealsAPreexistingLooseIndexFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("idx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        ShotIndex.storeOverride = dir.appendingPathComponent("index.json")
        defer { ShotIndex.storeOverride = nil; try? FileManager.default.removeItem(at: dir) }
        ShotIndex.save(ShotIndex.Store())
        let folder = try FileManager.default.attributesOfItem(atPath: dir.path)
        XCTAssertEqual((folder[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o700)
    }
}

