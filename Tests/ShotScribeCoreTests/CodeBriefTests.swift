import XCTest
import AppKit
@testable import ShotScribeCore

/// The brief the app hands Claude Code. It must carry the file, the exact
/// strings with their positions, and the working discipline, and it must stand
/// on its own with or without the MCP server.
final class CodeBriefTests: XCTestCase {

    private func shot(saying text: String) throws -> URL {
        let size = NSSize(width: 800, height: 400)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        (text as NSString).draw(at: NSPoint(x: 40, y: 300), withAttributes: [
            .font: NSFont.systemFont(ofSize: 40, weight: .bold), .foregroundColor: NSColor.black])
        image.unlockFocus()
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brief-\(UUID().uuidString).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testTheBriefCarriesTheFileTheStringsAndTheDiscipline() throws {
        let url = try shot(saying: "Deploy Dashboard")
        let brief = CodeBrief.text(forImageAt: url.path)
        XCTAssertTrue(brief.contains("Image: \(url.path)"))
        XCTAssertTrue(brief.contains("Deploy Dashboard"), "the exact string, from the layout")
        XCTAssertTrue(brief.contains("Layout ("), "positions come along")
        for phrase in ["Create once, then edit", "Extract, don't redraw", "Render and verify", "Pick the stack"] {
            XCTAssertTrue(brief.contains(phrase), "missing: \(phrase)")
        }
        XCTAssertFalse(brief.contains("—"), "the brief is pasted into a terminal; plain punctuation only")
    }

    func testAFileThatCannotBeReadStillGetsABrief() {
        let brief = CodeBrief.text(forImageAt: "/nonexistent/shot.png")
        XCTAssertTrue(brief.contains("Image: /nonexistent/shot.png"))
        XCTAssertTrue(brief.contains("work from the image alone"))
    }
}
