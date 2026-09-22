import XCTest
import AppKit
@testable import ShotScribeCore

/// `{app}`, read off the capture's own chrome: the menu bar of a full-screen
/// shot, the title bar of a window shot. Metadata never records it.
final class ChromeTests: XCTestCase {

    /// A line as Vision would report it: percent positions, top-left origin.
    private func line(_ text: String, top: Double, left: Double, width: Double, height: Double = 2.5) -> OCR.TextLine {
        OCR.TextLine(text: text, box: CGRect(x: left / 100, y: 1 - (top + height) / 100, width: width / 100, height: height / 100))
    }

    func testTheMenuBarNamesTheAppWhetherVisionSplitsItOrNot() {
        let split = [line("Finder", top: 0.5, left: 3, width: 4), line("File", top: 0.5, left: 8, width: 3),
                     line("Edit", top: 0.5, left: 12, width: 3), line("Documents", top: 30, left: 10, width: 20)]
        XCTAssertEqual(Chrome.app(in: split), "Finder")
        XCTAssertEqual(Chrome.body(of: split).map(\.text), ["Documents"], "the titler never sees the menu bar")
        let whole = [line("Ú Google Chrome File Edit View History Bookmarks", top: 0.6, left: 1, width: 45)]
        XCTAssertEqual(Chrome.app(in: whole), "Google Chrome", "the Apple mark is junk, the menus are not the app")
        // Apps whose names are also words: never treated as menus.
        XCTAssertEqual(Chrome.app(in: [line("Terminal Shell Edit View Window Help", top: 0.5, left: 3, width: 40)]), "Terminal")
        XCTAssertEqual(Chrome.app(in: [line("Code File Edit Selection View Go Run Terminal Help", top: 0.5, left: 3, width: 50)]), "Code")
    }

    func testAWindowsTitleBarIsTheFallback() {
        let xcode = [line("shotscribe — ShotScribeSurface.swift", top: 1.2, left: 34, width: 30),
                     line("import SwiftUI", top: 8, left: 5, width: 12)]
        XCTAssertEqual(Chrome.app(in: xcode), "shotscribe")
        let plain = [line("Untitled", top: 1, left: 44, width: 10)]
        XCTAssertEqual(Chrome.app(in: plain), "Untitled")
    }

    func testAShotWithNoChromeHasNoApp() {
        let body = [line("terminal error: connection refused", top: 44, left: 3, width: 70)]
        XCTAssertNil(Chrome.app(in: body))
        XCTAssertNil(Chrome.app(in: []))
    }

    // MARK: The token

    func testTheAppTokenRendersOrClosesTheGap() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 15, minute: 41))!
        let t = NameTemplate(layout: "{date} {app} {title}")
        XCTAssertEqual(Naming.filename(label: "AWS Billing Console", app: "Safari", capturedAt: date, ext: "png", template: t),
                       "2026-08-11 Safari AWS Billing Console.png")
        XCTAssertEqual(Naming.filename(label: "AWS Billing Console", app: nil, capturedAt: date, ext: "png", template: t),
                       "2026-08-11 AWS Billing Console.png", "no app, no gap")
        XCTAssertNil(Naming.validate(NameTemplate(layout: "{app}-{title}")), "{app} is a known token")
    }

    /// End to end on a real image: a menu bar drawn along the top, a body below.
    func testARenameReadsTheAppOffTheImage() async throws {
        let size = NSSize(width: 1200, height: 700)
        // Drawn at 2x, because a real capture is: a 15pt menu-bar label lands on
        // ~30 device pixels on a Retina screen, and `OCR.recognizeLines` reads
        // with no language correction. At 1x the same label is ~15px — near the
        // reader's threshold, where "Terminal" came back as "Terniinal" and the
        // test failed for a reason that is nothing to do with `Chrome.app`.
        // `lockFocus` took its scale from whichever display was
        // attached, so the fixture changed when the operator changed monitors
        // (2026-09-14: two 1x externals, and this went red on every commit).
        let rep2x = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep2x.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep2x)
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        NSColor(white: 0.93, alpha: 1).setFill(); NSRect(x: 0, y: size.height - 28, width: size.width, height: 28).fill()
        let bar: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.black]
        let menu: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.black]
        ("Terminal" as NSString).draw(at: NSPoint(x: 40, y: size.height - 22), withAttributes: bar)
        ("Shell   Edit   View   Window   Help" as NSString).draw(at: NSPoint(x: 130, y: size.height - 22), withAttributes: menu)
        ("deploy finished with warnings" as NSString).draw(at: NSPoint(x: 60, y: 340), withAttributes: [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(rep2x.representation(using: .png, properties: [:]))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chrome-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let raw = dir.appendingPathComponent("Screenshot 2026-08-11 at 3.41.07 PM.png")
        try png.write(to: raw)

        let lines = OCR.recognizeLines(atPath: raw.path)
        XCTAssertEqual(Chrome.app(in: lines), "Terminal",
                       "read off the bar; lines were \(lines.map { "\($0.text)@top\(Int($0.top)) h\(Int($0.height))" })")
        let renamer = Renamer(titler: KeywordTitler(), template: NameTemplate(layout: "{date} {app} {title}"))
        let outcome = try await renamer.rename(fileAt: raw, dryRun: true)
        guard case .wouldRename(_, let to) = outcome else { return XCTFail("got \(outcome)") }
        let name = to.lastPathComponent
        XCTAssertNotNil(name.range(of: #"^\d{4}-\d{2}-\d{2} Terminal "#, options: .regularExpression),
                        "the app slot holds the menu bar's first item: \(name)")
        XCTAssertFalse(name.contains("Shell"), "the menus reach neither the app nor the title: \(name)")
    }
}
