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
}

