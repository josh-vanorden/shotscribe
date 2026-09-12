import XCTest
import AppKit
@testable import ShotScribeCore

/// The layout read: text with positions, in reading order. What the MCP hands a
/// model that wants to rebuild a screen, and the half of "extract structure"
/// that never needs the pixels to leave the machine.
final class LayoutTests: XCTestCase {

    /// A real PNG with two lines at known places: a title near the top, a
    /// button label near the bottom-right.
    private func renderedShot() throws -> URL {
        let size = NSSize(width: 800, height: 400)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        let big: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 40, weight: .bold), .foregroundColor: NSColor.black]
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black]
        ("AWS Billing Console" as NSString).draw(at: NSPoint(x: 40, y: 320), withAttributes: big)   // AppKit: y up
        ("Sign out" as NSString).draw(at: NSPoint(x: 600, y: 30), withAttributes: small)
        image.unlockFocus()
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("layout-\(UUID().uuidString).png")
        try png.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testLinesComeBackInReadingOrderWithPositions() throws {
        let (size, lines) = OCR.recognizeLayout(atPath: try renderedShot().path)
        // Pixels, not points: on a Retina display the render is 2x, and the
        // tool reports what the file holds. The ratio is what the test knows.
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertEqual(size.width / size.height, 2, accuracy: 0.01)
        let texts = lines.map(\.text)
        XCTAssertEqual(texts.count, 2, "got \(texts)")
        XCTAssertEqual(texts.first, "AWS Billing Console", "the title is read first")
        XCTAssertEqual(texts.last, "Sign out")

        let title = try XCTUnwrap(lines.first), button = try XCTUnwrap(lines.last)
        XCTAssertLessThan(title.top, 30, "the title sits in the top of the image")
        XCTAssertGreaterThan(button.top, 70, "the button sits in the bottom")
        XCTAssertGreaterThan(button.left, 60, "and to the right")
        XCTAssertGreaterThan(title.width, button.width, "a wider string spans more of the image")
    }

    func testANonImageIsAnEmptyLayout() {
        let (size, lines) = OCR.recognizeLayout(atPath: "/nonexistent/shot.png")
        XCTAssertEqual(size, .zero)
        XCTAssertTrue(lines.isEmpty)
    }
}
