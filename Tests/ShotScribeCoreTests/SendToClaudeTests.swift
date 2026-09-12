import XCTest
@testable import ShotScribeCore

/// "Send to Claude": the line the app copies must be a form the `/screenshot`
/// skill says it takes, or the paste lands as a question instead of a shot.
final class SendToClaudeTests: XCTestCase {

    func testTheLineIsTheSkillsQuotedPathForm() {
        XCTAssertEqual(SendToClaude.line(forImageAt: "/Users/me/Pictures/Screenshots/2026-09-11 2244 Name Folder.png"),
                       "/screenshot \"/Users/me/Pictures/Screenshots/2026-09-11 2244 Name Folder.png\"")
        XCTAssertEqual(SendToClaude.line(forImageAt: "/a/say \"hi\".png"), "/screenshot \"/a/say \\\"hi\\\".png\"",
                       "a quote in the path stays inside the quotes")
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
