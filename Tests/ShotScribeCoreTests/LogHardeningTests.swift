import XCTest
@testable import ShotScribeUI

/// The log is the second file ShotScribe writes that carries text read off the
/// user's screen — titles, tags, old→new name pairs — so it follows the same
/// owner-only rule `HardeningTests` pins on the index.
final class LogHardeningTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Log.urlOverride = dir.appendingPathComponent("ShotScribe.log")
    }

    override func tearDownWithError() throws {
        Log.urlOverride = nil
        try? FileManager.default.removeItem(at: dir)
    }

    func testTheLogIsReadableByItsOwnerOnly() throws {
        Log.write("new capture Screenshot.png: ocr=42 chars")
        let attrs = try FileManager.default.attributesOfItem(atPath: Log.url.path)
        XCTAssertEqual((attrs[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o600)
        let body = try String(contentsOf: Log.url, encoding: .utf8)
        XCTAssertTrue(body.contains("ocr=42 chars"))
    }

    /// A log created before the rule sits at 644; the next line tightens it
    /// without losing what is already there.
    func testAWideOpenLogTightensOnTheNextLine() throws {
        FileManager.default.createFile(atPath: Log.url.path,
                                       contents: Data("[old] earlier line\n".utf8),
                                       attributes: [.posixPermissions: 0o644])
        Log.write("appended line")
        let attrs = try FileManager.default.attributesOfItem(atPath: Log.url.path)
        XCTAssertEqual((attrs[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o600)
        let body = try String(contentsOf: Log.url, encoding: .utf8)
        XCTAssertTrue(body.contains("earlier line"), "tightening must not truncate")
        XCTAssertTrue(body.contains("appended line"))
    }
}
