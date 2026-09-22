import XCTest
import AppKit
@testable import ShotScribeCore

/// "Send to Claude": the line the app copies must be a form the `/screenshot`
/// skill says it takes, or the paste lands as a question instead of a shot.
final class SendToClaudeTests: XCTestCase {

    func testTheLineIsTheSkillsQuotedPathForm() {
        XCTAssertEqual(SendToClaude.line(forImageAt: "/Users/me/Pictures/Screenshots/2026-09-11 2244 Name Folder.png"),
                       "/screenshot \"/Users/me/Pictures/Screenshots/2026-09-11 2244 Name Folder.png\"")
        XCTAssertEqual(SendToClaude.line(forImageAt: "/a/say \"hi\".png"), "/screenshot \"/a/say \\\"hi\\\".png\"",
                       "a quote in the path stays inside the quotes")
        XCTAssertEqual(SendToClaude.line(forImageAt: "/a/back\\slash.png"), "/screenshot \"/a/back\\\\slash.png\"",
                       "a backslash is escaped too, so a path ending in one cannot eat the closing quote")
    }

    /// For a chat that cannot see this Mac, the pasteboard carries the picture:
    /// PNG data a web composer attaches, the file for apps that take one, and
    /// the file's name — never its path — as the text.
    func testThePictureItemCarriesTheImageAndTheNameButNeverThePath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("send-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.5, blue: 0.9, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        let url = dir.appendingPathComponent("2026-09-22 0912 Command Result.png")
        try ImageEditor.save(try XCTUnwrap(ctx.makeImage()), over: url)

        let item = try XCTUnwrap(SendToClaude.picture(forImageAt: url))
        XCTAssertEqual(Set(item.types), [.png, .fileURL, .string])
        let png = try XCTUnwrap(item.data(forType: .png))
        let back = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        XCTAssertEqual(back.width, 120); XCTAssertEqual(back.height, 80)
        XCTAssertEqual(item.string(forType: .fileURL), url.absoluteString)
        XCTAssertEqual(item.string(forType: .string), "2026-09-22 0912 Command Result.png", "the name, for a text-only field")
        XCTAssertFalse(try XCTUnwrap(item.string(forType: .string)).contains("/"), "and never the path")
        XCTAssertNil(SendToClaude.picture(forImageAt: dir.appendingPathComponent("missing.png")))
    }

    func testTheSkillDocumentsThePathArgumentTheAppCopies() throws {
        let skill = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("skills/screenshot/SKILL.md")
        let text = try String(contentsOf: skill, encoding: .utf8)
        XCTAssertTrue(text.contains("/screenshot \""), "the skill shows the quoted-path form the app copies")
        XCTAssertTrue(text.contains("Send to Claude"), "the skill says where that line comes from")
    }
}
