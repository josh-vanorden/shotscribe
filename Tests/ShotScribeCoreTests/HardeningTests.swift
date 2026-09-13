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
}
