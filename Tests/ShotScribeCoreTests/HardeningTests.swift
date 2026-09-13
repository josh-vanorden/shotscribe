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
}
