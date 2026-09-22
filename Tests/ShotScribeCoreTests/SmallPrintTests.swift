import XCTest
import AppKit
@testable import ShotScribeCore

/// Small print on a big picture — an org chart, a wide dashboard — is where
/// the fast OCR pass reads noise and a shot gets titled "Screenshot". The
/// engine re-reads such a picture at the accurate level, so the words reach
/// the titler.
final class SmallPrintTests: XCTestCase {

    /// A 2,000-pixel-wide chart whose labels are set at nine pixels.
    private func orgChart() throws -> URL {
        let w = 2000, h = 600
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        let tiny: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .medium),
                                                    .foregroundColor: NSColor.black]
        let boxes = [("Matt Blumberg", "Chief Executive Officer"), ("Britta Muhlenberg", "Chief Operating Officer"),
                     ("Maria Sodan", "Director of Accounting"), ("Steven Lopatin", "Senior Director Legal"),
                     ("Kelly Ferko", "Director People and Talent"), ("Louis Bucciarelli", "Chief Revenue Officer")]
        for (i, (name, role)) in boxes.enumerated() {
            let x = 60 + CGFloat(i) * 310, y = CGFloat(300 - (i % 2) * 120)
            NSColor(white: 0.85, alpha: 1).setStroke()
            NSBezierPath(roundedRect: NSRect(x: x - 10, y: y - 8, width: 200, height: 40), xRadius: 4, yRadius: 4).stroke()
            (name as NSString).draw(at: NSPoint(x: x, y: y + 16), withAttributes: tiny)
            (role as NSString).draw(at: NSPoint(x: x, y: y + 2), withAttributes: tiny)
        }
        NSGraphicsContext.restoreGraphicsState()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("smallprint-\(UUID().uuidString).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    func testTinyLabelsOnAWideChartReachTheTitler() throws {
        let url = try orgChart()
        defer { try? FileManager.default.removeItem(at: url) }
        let text = OCR.recognizeText(atPath: url.path)
        XCTAssertGreaterThanOrEqual(text.count, OCR.sparseChars, "a chart of six boxes is not sparse: \(text.prefix(120))")
        // Nine-pixel type is at the edge of what any pass reads; the point is
        // that the words reach the titler, not that every one is letter-perfect.
        let read = ["Executive", "Operating", "Accounting", "Revenue", "Legal", "Talent"]
            .filter { text.localizedCaseInsensitiveContains($0) }
        XCTAssertGreaterThanOrEqual(read.count, 4, "only \(read) read from: \(text.prefix(200))")
    }

    /// The fallback is for pictures big enough to hold small print; a tiny
    /// picture with little text is simply a tiny picture.
    func testASmallEmptyPictureIsNotReReadForever() {
        XCTAssertLessThan(160 * 160, OCR.sparseArea)
        XCTAssertGreaterThanOrEqual(2000 * 600, OCR.sparseArea)
    }
}
