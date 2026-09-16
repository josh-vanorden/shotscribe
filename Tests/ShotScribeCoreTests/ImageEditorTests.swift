import XCTest
import AppKit
@testable import ShotScribeCore

/// The editor's engine. What has to hold: a redacted region stops being
/// readable — to OCR as well as to a person — and saving an edit leaves the
/// file being the same capture it was.
final class ImageEditorTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("editor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// A 2x capture with a secret on one line and something harmless on another.
    private func capture(named name: String = "2026-08-06 0922 Api Keys Page.png") throws -> URL {
        let size = NSSize(width: 900, height: 420)
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1800, pixelsHigh: 840,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        let big: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 34, weight: .semibold),
                                                   .foregroundColor: NSColor.black]
        ("Account settings" as NSString).draw(at: NSPoint(x: 60, y: 300), withAttributes: big)
        ("SECRET KEY HUNTER42" as NSString).draw(at: NSPoint(x: 60, y: 120), withAttributes: big)
        NSGraphicsContext.restoreGraphicsState()
        let url = dir.appendingPathComponent(name)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    /// Where the secret line sits, in image pixels, top-left origin: drawn at
    /// y 120pt from the bottom of a 420pt canvas, at 2x.
    private let secretLine = CGRect(x: 100, y: 840 - 2 * (120 + 46), width: 1500, height: 2 * 60)

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return (p[0], p[1], p[2])
    }

    func testTheSecretIsReadableBeforeAndNotAfterPixelating() throws {
        let url = try capture()
        XCTAssertTrue(ShotIndex.searchText(atPath: url.path).uppercased().contains("HUNTER42"),
                      "the fixture must actually be readable, or the next check proves nothing")

        let source = try XCTUnwrap(ImageEditor.load(url))
        let edited = try XCTUnwrap(ImageEditor.render(source, marks: [pixelate(secretLine)]))
        try ImageEditor.save(edited, over: url)

        let text = ShotIndex.searchText(atPath: url.path).uppercased()
        XCTAssertFalse(text.contains("HUNTER42"), "the key survived as text: \(text)")
        XCTAssertFalse(text.contains("SECRET"), "and so did the word beside it: \(text)")
        XCTAssertTrue(text.contains("ACCOUNT"), "the line nobody covered is still there: \(text)")
    }

    func testBlackOutLeavesNothingToRead() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        let edited = try XCTUnwrap(ImageEditor.render(source, marks: [Mark(kind: .blackOut, a: secretLine.origin, b: CGPoint(x: secretLine.maxX, y: secretLine.maxY))]))
        let mid = pixel(edited, Int(secretLine.midX), Int(secretLine.midY))
        // The palette's black is Josh's dark grey (#171717), so the cover is
        // dark and neutral rather than pure zero.
        XCTAssertLessThan(Int(mid.r) + Int(mid.g) + Int(mid.b), 90, "solid, not tinted: \(mid)")
        XCTAssertLessThan(abs(Int(mid.r) - Int(mid.b)), 6, "and neutral")
        let outside = pixel(edited, 20, 20)
        XCTAssertGreaterThan(Int(outside.r), 240, "and only inside the region")
    }

    /// A black-out in a colour is still a cover: opaque, in that colour, and
    /// the text under it is gone. Josh, 2026-09-16: "Why does the blackout not
    /// allow for another color selection?"
    func testBlackOutTakesAColourAndStaysOpaque() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        let cover = Mark(kind: .blackOut, a: secretLine.origin, b: CGPoint(x: secretLine.maxX, y: secretLine.maxY),
                         color: MarkColor(red: 0.88, green: 0.02, blue: 0, alpha: 0.3))
        let edited = try XCTUnwrap(ImageEditor.render(source, marks: [cover]))
        let mid = pixel(edited, Int(secretLine.midX), Int(secretLine.midY))
        XCTAssertGreaterThan(Int(mid.r), 200, "the cover is the chosen scarlet: \(mid)")
        XCTAssertLessThan(Int(mid.g), 40, "and opaque even when the colour carried alpha: \(mid)")
        try ImageEditor.save(edited, over: url)
        let text = ShotIndex.searchText(atPath: url.path).uppercased()
        XCTAssertFalse(text.contains("HUNTER42"), "the key survived as text: \(text)")
    }

    func testPixelateTouchesOnlyItsRegion() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        let edited = try XCTUnwrap(ImageEditor.render(source, marks: [pixelate(secretLine)]))
        XCTAssertEqual(edited.width, source.width)
        XCTAssertEqual(edited.height, source.height)
        // The top line is untouched pixel for pixel at a sample of points.
        for (x, y) in [(120, 250), (400, 260), (700, 240), (20, 20)] {
            let a = pixel(source, x, y), b = pixel(edited, x, y)
            XCTAssertEqual([a.r, a.g, a.b], [b.r, b.g, b.b], "changed outside the region at \(x),\(y)")
        }
    }

    /// Fine tiles, wide sampling: each tile a fifth of the region's short side,
    /// each shaded from three tiles' width around it.
    func testTilesAreFineButEachSamplesAWideArea() {
        let line = CGRect(x: 0, y: 0, width: 800, height: 120)
        XCTAssertEqual(ImageEditor.blockSize(for: line), 24)
        XCTAssertEqual(ImageEditor.sampleSpan(for: line), 72,
                       "wider than a line of type is tall, so no tile holds a glyph's outline")
        XCTAssertEqual(ImageEditor.blockSize(for: CGRect(x: 0, y: 0, width: 20, height: 20)), 8,
                       "a small region still gets a floor, not a one-pixel grid")
    }

    // MARK: Marks stay editable

    /// A mark is picked up where it is drawn — and only there.
    func testAMarkIsHitWhereItIsAndMissedWhereItIsNot() {
        let box = Mark(kind: .rectangle, a: CGPoint(x: 100, y: 100), b: CGPoint(x: 300, y: 200))
        XCTAssertTrue(box.hit(CGPoint(x: 200, y: 150), tolerance: 4), "inside")
        XCTAssertTrue(box.hit(CGPoint(x: 97, y: 150), tolerance: 4), "just outside its edge, within reach")
        XCTAssertFalse(box.hit(CGPoint(x: 400, y: 150), tolerance: 4))

        let line = Mark(kind: .line, a: CGPoint(x: 0, y: 0), b: CGPoint(x: 100, y: 100), lineWidth: 4)
        XCTAssertTrue(line.hit(CGPoint(x: 51, y: 49), tolerance: 4), "on the segment")
        XCTAssertFalse(line.hit(CGPoint(x: 90, y: 10), tolerance: 4), "inside its bounds but far from the line")
        XCTAssertFalse(line.hit(CGPoint(x: 140, y: 140), tolerance: 4), "past its end")

        let label = Mark(kind: .text, a: CGPoint(x: 10, y: 10), b: CGPoint(x: 10, y: 10), fontSize: 20, text: "Look")
        XCTAssertTrue(label.hit(CGPoint(x: 20, y: 20), tolerance: 2))
        XCTAssertFalse(label.hit(CGPoint(x: 400, y: 20), tolerance: 2), "a label is as wide as its words")
    }

    func testMovingAMarkMovesBothEnds() {
        var arrow = Mark(kind: .arrow, a: CGPoint(x: 10, y: 20), b: CGPoint(x: 110, y: 70))
        arrow.move(dx: 5, dy: -10)
        XCTAssertEqual(arrow.a, CGPoint(x: 15, y: 10))
        XCTAssertEqual(arrow.b, CGPoint(x: 115, y: 60))
    }

    /// A shape dragged up and to the left is the same shape as one dragged the
    /// other way.
    func testARectangleIsTheSameWhicheverWayItWasDragged() {
        let a = Mark(kind: .ellipse, a: CGPoint(x: 300, y: 200), b: CGPoint(x: 100, y: 50))
        XCTAssertEqual(a.rect, CGRect(x: 100, y: 50, width: 200, height: 150))
    }

    /// Every kind draws, in its own colour, where it says it is.
    func testEveryKindDrawsItsColourInPlace() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        let blue = MarkColor.blue
        let filled = Mark(kind: .rectangle, a: CGPoint(x: 1300, y: 40), b: CGPoint(x: 1500, y: 140),
                          color: blue, filled: true)
        let ring = Mark(kind: .ellipse, a: CGPoint(x: 1300, y: 600), b: CGPoint(x: 1700, y: 800),
                        color: .green, lineWidth: 12, filled: true)
        let marker = Mark(kind: .highlight, a: CGPoint(x: 20, y: 700), b: CGPoint(x: 400, y: 800), color: .yellow)
        let out = try XCTUnwrap(ImageEditor.render(source, marks: [filled, ring, marker]))

        let f = pixel(out, 1400, 90)
        // The palette blue is Josh's sapphire — deep, not bright — so the check
        // is that blue dominates, not that it is loud.
        XCTAssertLessThan(Int(f.r), 40, "a filled blue box is blue: \(f)")
        XCTAssertGreaterThan(Int(f.b), Int(f.r) + 60)
        XCTAssertGreaterThan(Int(f.b), 80)
        let e = pixel(out, 1500, 700)
        XCTAssertGreaterThan(Int(e.g), Int(e.r) + 60, "a filled green ellipse is green at its centre: \(e)")
        let h = pixel(out, 200, 750)
        XCTAssertGreaterThan(Int(h.r), 200, "a highlight on white stays light: \(h)")
        XCTAssertLessThan(Int(h.b), 200, "and takes the marker's yellow")
    }

    /// A label on a light colour gets dark type, so it can still be read.
    func testALabelPicksTypeThatReadsOnItsColour() {
        XCTAssertTrue(MarkColor.purple.wantsLightText)
        XCTAssertTrue(MarkColor.red.wantsLightText)
        XCTAssertFalse(MarkColor.yellow.wantsLightText)
        XCTAssertFalse(MarkColor.white.wantsLightText)
    }

    // MARK: What a press does

    private let redaction = Mark(kind: .pixelate, a: CGPoint(x: 100, y: 100), b: CGPoint(x: 700, y: 300))
    private let box = Mark(kind: .rectangle, a: CGPoint(x: 400, y: 200), b: CGPoint(x: 500, y: 260))

    /// Josh's case: a pixelation covers an area, then a label is started on it.
    /// A drawing tool must draw — never pick the redaction up.
    func testADrawingToolDrawsOverARedaction() {
        let press = EditorPress.at(CGPoint(x: 300, y: 200), drawing: true, selected: nil,
                                   marks: [redaction], reach: 8)
        XCTAssertEqual(press, .draw)
    }

    /// Even over the mark that is selected — the body is not a handle.
    func testADrawingToolDrawsOverTheSelectedMarkToo() {
        let press = EditorPress.at(CGPoint(x: 300, y: 200), drawing: true, selected: redaction,
                                   marks: [redaction], reach: 8)
        XCTAssertEqual(press, .draw)
    }

    /// A handle is a handle in any tool: it is only shown on the selected mark.
    func testAVisibleHandleResizesInAnyTool() {
        for drawing in [true, false] {
            let press = EditorPress.at(CGPoint(x: 703, y: 297), drawing: drawing, selected: redaction,
                                       marks: [redaction], reach: 8)
            XCTAssertEqual(press, .resize(redaction.id, .bottomRight), "drawing: \(drawing)")
        }
    }

    /// A handle of a mark that is *not* selected is not shown, so not grabbed.
    func testAnUnselectedMarksCornerIsNotAHandle() {
        let press = EditorPress.at(CGPoint(x: 700, y: 300), drawing: true, selected: nil,
                                   marks: [redaction], reach: 8)
        XCTAssertEqual(press, .draw)
    }

    /// Select picks up the topmost mark: the box drawn over the redaction.
    func testSelectPicksTheTopmostMark() {
        let press = EditorPress.at(CGPoint(x: 450, y: 230), drawing: false, selected: nil,
                                   marks: [redaction, box], reach: 8)
        XCTAssertEqual(press, .move(box.id))
        let under = EditorPress.at(CGPoint(x: 150, y: 150), drawing: false, selected: nil,
                                   marks: [redaction, box], reach: 8)
        XCTAssertEqual(under, .move(redaction.id), "and the one underneath where the top one isn't")
    }

    func testSelectOnNothingDeselects() {
        let press = EditorPress.at(CGPoint(x: 900, y: 900), drawing: false, selected: box,
                                   marks: [redaction, box], reach: 8)
        XCTAssertEqual(press, .deselect)
    }

    /// Dragging a corner moves that corner only; the opposite one stays put.
    func testResizingHoldsTheOppositeCorner() {
        let bigger = box.resized(.topLeft, to: CGPoint(x: 350, y: 150))
        XCTAssertEqual(bigger.rect, CGRect(x: 350, y: 150, width: 150, height: 110))
        let flipped = box.resized(.bottomRight, to: CGPoint(x: 380, y: 180))
        XCTAssertEqual(flipped.rect, CGRect(x: 380, y: 180, width: 20, height: 20),
                       "dragged past the other corner, it turns inside out rather than breaking")
        let arrow = Mark(kind: .arrow, a: CGPoint(x: 0, y: 0), b: CGPoint(x: 10, y: 10))
        XCTAssertEqual(arrow.resized(.b, to: CGPoint(x: 50, y: 5)).b, CGPoint(x: 50, y: 5))
        XCTAssertEqual(arrow.resized(.b, to: CGPoint(x: 50, y: 5)).a, .zero)
    }

    /// A line or arrow has a middle handle. Dragging it bends the mark through
    /// that point; dragging it back to the middle straightens it again; the
    /// bend travels with the mark, and an edit kept before curves is straight.
    func testAnArrowBendsThroughItsMiddleHandle() throws {
        let arrow = Mark(kind: .arrow, a: CGPoint(x: 0, y: 0), b: CGPoint(x: 200, y: 0), lineWidth: 4)
        XCTAssertEqual(arrow.handles.map(\.0), [.a, .bend, .b])
        XCTAssertEqual(arrow.handles[1].1, CGPoint(x: 100, y: 0), "straight: the handle sits mid-way")

        let bent = arrow.resized(.bend, to: CGPoint(x: 100, y: 60))
        XCTAssertEqual(bent.bend, CGPoint(x: 100, y: 60))
        XCTAssertEqual(bent.point(at: 0.5), CGPoint(x: 100, y: 60), "the curve passes through the handle")
        XCTAssertEqual(bent.handles[1].1, CGPoint(x: 100, y: 60), "which is where the handle now is")
        XCTAssertTrue(bent.hit(CGPoint(x: 100, y: 58), tolerance: 4), "so it can be picked up on the curve")
        XCTAssertFalse(bent.hit(CGPoint(x: 100, y: 0), tolerance: 4), "and not on the straight path it left")
        XCTAssertGreaterThan(bent.length, 200, "a bent arrow is longer than its chord")

        var moved = bent; moved.move(dx: 10, dy: 10)
        XCTAssertEqual(moved.bend, CGPoint(x: 110, y: 70), "the bend travels with the mark")
        XCTAssertNil(bent.resized(.bend, to: CGPoint(x: 101, y: 3)).bend, "back at the middle it snaps straight")

        let kept = try JSONDecoder().decode(Mark.self, from: JSONEncoder().encode(bent))
        XCTAssertEqual(kept.bend, bent.bend, "the bend is kept with the edit")
        let json = String(decoding: try JSONEncoder().encode(arrow), as: UTF8.self)
        XCTAssertFalse(json.contains("bend"), "a straight one writes no bend — the shape older edits have")
        XCTAssertNil(try JSONDecoder().decode(Mark.self, from: Data(json.utf8)).bend)
    }

    /// The paint follows the bend: ink at the handle, none where the chord was.
    func testABentLineIsDrawnThroughItsBend() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        let white = try XCTUnwrap(ctx.makeImage())
        for kind in [Mark.Kind.line, .arrow] {
            let mark = Mark(kind: kind, a: CGPoint(x: 40, y: 40), b: CGPoint(x: 360, y: 40), color: .scarlet,
                            lineWidth: 6, bend: CGPoint(x: 200, y: 140))
            let out = try XCTUnwrap(ImageEditor.render(white, marks: [mark]))
            let at = pixel(out, 200, 140)
            XCTAssertGreaterThan(Int(at.r), 180, "\(kind): ink at the bend: \(at)")
            XCTAssertLessThan(Int(at.g), 80, "\(kind): in the mark's scarlet: \(at)")
            let chord = pixel(out, 200, 40)
            XCTAssertGreaterThan(Int(chord.g), 240, "\(kind): nothing where the straight line would have been: \(chord)")
        }
    }

    func testALabelHasNoHandles() {
        let label = Mark(kind: .text, a: .zero, b: .zero, text: "Hi")
        XCTAssertTrue(label.handles.isEmpty)
    }

    private func pixelate(_ r: CGRect) -> Mark {
        Mark(kind: .pixelate, a: r.origin, b: CGPoint(x: r.maxX, y: r.maxY))
    }

    /// Saving an edit must not make the file a different capture.
    func testSavingKeepsTheNameTheDayAndTheTags() throws {
        let url = try capture()
        let taken = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 9, minute: 22))!
        try FileManager.default.setAttributes([.creationDate: taken, .modificationDate: taken], ofItemAtPath: url.path)
        XCTAssertTrue(Tagging.add(["settings", "code"], to: url))
        let before = try Data(contentsOf: url)

        let source = try XCTUnwrap(ImageEditor.load(url))
        let edited = try XCTUnwrap(ImageEditor.render(source, marks: [
            Mark(kind: .rectangle, a: CGPoint(x: 40, y: 40), b: CGPoint(x: 340, y: 160), lineWidth: 6),
            Mark(kind: .arrow, a: CGPoint(x: 600, y: 600), b: CGPoint(x: 360, y: 120), lineWidth: 8),
            Mark(kind: .text, a: CGPoint(x: 900, y: 60), b: CGPoint(x: 900, y: 60), fontSize: 40, text: "Look here"),
        ]))
        try ImageEditor.save(edited, over: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "same name")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [url.lastPathComponent],
                       "and nothing left beside it")
        XCTAssertNotEqual(try Data(contentsOf: url), before, "the content did change")
        XCTAssertEqual(Set(Tagging.finderTags(of: url)), ["settings", "code"], "the filing survived")
        let v = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        XCTAssertEqual(v.creationDate?.timeIntervalSince1970 ?? 0, taken.timeIntervalSince1970, accuracy: 1,
                       "still the day it was taken")
        XCTAssertGreaterThan(v.contentModificationDate ?? .distantPast, taken.addingTimeInterval(60),
                             "but modified now, so QuickLook draws the new picture")
    }

    func testAnEmptyEditListIsTheSamePicture() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        let same = try XCTUnwrap(ImageEditor.render(source, marks: []))
        for (x, y) in [(120, 250), (300, 700), (900, 500)] {
            let a = pixel(source, x, y), b = pixel(same, x, y)
            XCTAssertEqual([a.r, a.g, a.b], [b.r, b.g, b.b])
        }
    }
}
