import XCTest
import AppKit
@testable import ShotScribeCore

/// Where a fast OCR pass reads noise and a shot gets titled "Screenshot":
/// small print on a big picture (an org chart, a wide dashboard) and a small
/// picture altogether (a 280-pixel capture of a slide). The engine reads at
/// the accurate level always, and doubles a small picture first, so the words
/// reach the titler either way.
final class SmallPrintTests: XCTestCase {

    private func bitmap(_ w: Int, _ h: Int) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: w, height: h)
        return rep
    }

    private func write(_ rep: NSBitmapImageRep, _ stem: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(stem)-\(UUID().uuidString).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    /// A 2,000-pixel-wide chart whose labels are set at nine pixels.
    private func orgChart() throws -> URL {
        let w = 2000, h = 600
        let rep = try bitmap(w, h)
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
        return try write(rep, "smallprint")
    }

    /// A 280-pixel capture of a slide: a title at sixteen pixels over a
    /// subtitle at seven and body copy at five — the shape of the five captures
    /// that were all titled "Screenshot" on 2026-09-22.
    private func smallSlide() throws -> URL {
        let w = 280, h = 370
        let rep = try bitmap(w, h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .bold), .foregroundColor: NSColor.black]
        let sub: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 7), .foregroundColor: NSColor.darkGray]
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 5), .foregroundColor: NSColor.darkGray]
        ("Orchestration Patterns" as NSString).draw(at: NSPoint(x: 40, y: 335), withAttributes: title)
        ("Coordinating multiple agents to solve bigger tasks." as NSString).draw(at: NSPoint(x: 40, y: 322), withAttributes: sub)
        for (i, line) in ["Research Agent finds destinations, flights, local info",
                          "Planning Agent creates a day-wise itinerary",
                          "Budget Agent estimates total cost and options",
                          "Review Agent validates results, handles errors"].enumerated() {
            (line as NSString).draw(at: NSPoint(x: 24, y: 260 - CGFloat(i) * 50), withAttributes: body)
        }
        NSGraphicsContext.restoreGraphicsState()
        return try write(rep, "smallslide")
    }

    func testTinyLabelsOnAWideChartReachTheTitler() throws {
        let url = try orgChart()
        defer { try? FileManager.default.removeItem(at: url) }
        let text = OCR.recognizeText(atPath: url.path)
        // Nine-pixel type is at the edge of what any pass reads; the point is
        // that the words reach the titler, not that every one is letter-perfect.
        let read = ["Executive", "Operating", "Accounting", "Revenue", "Legal", "Talent"]
            .filter { text.localizedCaseInsensitiveContains($0) }
        XCTAssertGreaterThanOrEqual(read.count, 4, "only \(read) read from: \(text.prefix(200))")
    }

    func testASmallCaptureOfASlideReadsItsTitle() throws {
        let url = try smallSlide()
        defer { try? FileManager.default.removeItem(at: url) }
        let text = OCR.recognizeText(atPath: url.path)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Orchestration Patterns"), "read: \(text.prefix(200))")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Coordinating"), "the subtitle too: \(text.prefix(200))")
    }

    /// Only a small picture is doubled; a capture of a whole screen is read as is.
    func testOnlyASmallPictureIsDoubled() throws {
        let small = try XCTUnwrap(bitmap(280, 370).cgImage)
        let big = try XCTUnwrap(bitmap(2000, 600).cgImage)
        XCTAssertEqual(OCR.enlarged(small).width, 560)
        XCTAssertEqual(OCR.enlarged(small).height, 740)
        XCTAssertEqual(OCR.enlarged(big).width, 2000, "a picture this size is not doubled")
    }
}
