import XCTest
import AppKit
@testable import ShotScribeCore

/// Saved edits stay editable, and the frame is part of the edit. What has to
/// hold: marks come back as objects, the link survives a rename, a revert gives
/// back the real original — and a redaction is never kept anywhere.
final class EditStoreTests: XCTestCase {
    private var dir: URL!
    private var store: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("editstore-\(UUID().uuidString)")
        store = dir.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        EditStore.rootOverride = store
        BackgroundImages.rootOverride = dir.appendingPathComponent("backgrounds")
        ShotScribeDefaults.suiteOverride = UserDefaults(suiteName: "editstore-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        EditStore.rootOverride = nil
        BackgroundImages.rootOverride = nil
        ShotScribeDefaults.suiteOverride = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func capture(_ name: String = "2026-08-06 0922 Api Keys Page.png") throws -> URL {
        let size = NSSize(width: 900, height: 420)
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1800, pixelsHigh: 840,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        let font: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 34, weight: .semibold),
                                                   .foregroundColor: NSColor.black]
        ("Account settings" as NSString).draw(at: NSPoint(x: 60, y: 300), withAttributes: font)
        ("SECRET KEY HUNTER42" as NSString).draw(at: NSPoint(x: 60, y: 120), withAttributes: font)
        NSGraphicsContext.restoreGraphicsState()
        let url = dir.appendingPathComponent(name)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    private let secretLine = CGRect(x: 100, y: 840 - 2 * (120 + 46), width: 1500, height: 120)
    private let arrow = Mark(kind: .arrow, a: CGPoint(x: 1400, y: 700), b: CGPoint(x: 1000, y: 400),
                             color: .blue, lineWidth: 8)
    private let label = Mark(kind: .text, a: CGPoint(x: 1000, y: 60), b: CGPoint(x: 1000, y: 60),
                             color: .purple, fontSize: 40, text: "Look here")

    func testMarksComeBackAsObjects() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        try EditStore.commit(source: source, marks: [arrow, label], frame: .plain, sourceIsOriginal: true, to: url)

        XCTAssertTrue(EditStore.hasEdit(url))
        let (base, doc) = try XCTUnwrap(EditStore.load(for: url))
        XCTAssertEqual(doc.marks, [arrow, label], "the same marks, ids and all")
        XCTAssertTrue(doc.baseIsOriginal)
        XCTAssertEqual(base.width, source.width)
    }

    /// The link is on the file, not its path.
    func testTheEditFollowsTheFileThroughARename() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        try EditStore.commit(source: source, marks: [arrow], frame: .plain, sourceIsOriginal: true, to: url)
        let renamed = dir.appendingPathComponent("2026-08-06 0922 Renamed Later.png")
        try FileManager.default.moveItem(at: url, to: renamed)
        XCTAssertEqual(try XCTUnwrap(EditStore.load(for: renamed)).document.marks, [arrow])
    }

    /// And through a second save, which replaces the file's contents.
    func testReEditingKeepsOneEditNotTwo() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        try EditStore.commit(source: source, marks: [arrow], frame: .plain, sourceIsOriginal: true, to: url)
        let first = EditStore.id(of: url)
        let (base, _) = try XCTUnwrap(EditStore.load(for: url))
        try EditStore.commit(source: base, marks: [arrow, label], frame: .plain, sourceIsOriginal: true, to: url)
        XCTAssertEqual(EditStore.id(of: url), first, "same edit, updated")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.path).count, 1)
        XCTAssertEqual(try XCTUnwrap(EditStore.load(for: url)).document.marks.count, 2)
    }

    /// The whole point of a redaction: the secret is not in the file, not in
    /// the kept picture, and the redaction cannot be lifted off as an object.
    func testARedactionIsNeverKept() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        let hide = Mark(kind: .pixelate, a: secretLine.origin, b: CGPoint(x: secretLine.maxX, y: secretLine.maxY))
        try EditStore.commit(source: source, marks: [hide, arrow], frame: .plain, sourceIsOriginal: true, to: url)

        XCTAssertFalse(ShotIndex.searchText(atPath: url.path).uppercased().contains("HUNTER42"), "not in the file")
        let id = try XCTUnwrap(EditStore.id(of: url))
        let kept = store.appendingPathComponent(id.uuidString).appendingPathComponent("base.png")
        let keptText = ShotIndex.searchText(atPath: kept.path).uppercased()
        XCTAssertFalse(keptText.contains("HUNTER42"), "not in the kept picture either: \(keptText)")
        XCTAssertTrue(keptText.contains("ACCOUNT"), "which is otherwise the real capture")

        let (_, doc) = try XCTUnwrap(EditStore.load(for: url))
        XCTAssertEqual(doc.marks, [arrow], "the arrow is still editable; the redaction is not an object")
        XCTAssertFalse(doc.baseIsOriginal)
        XCTAssertFalse(try EditStore.revert(url), "and there is no original to go back to")
    }

    func testRevertPutsTheRealOriginalBack() throws {
        let url = try capture()
        let before = try Data(contentsOf: url)
        let beforeText = ShotIndex.searchText(atPath: url.path)
        let source = try XCTUnwrap(ImageEditor.load(url))
        try EditStore.commit(source: source, marks: [arrow, label], frame: .suggested, sourceIsOriginal: true, to: url)
        XCTAssertNotEqual(try Data(contentsOf: url), before)

        XCTAssertTrue(try EditStore.revert(url))
        let reverted = try XCTUnwrap(ImageEditor.load(url))
        XCTAssertEqual(reverted.width, source.width, "unframed again")
        XCTAssertEqual(ShotIndex.searchText(atPath: url.path), beforeText, "and the same picture")
        XCTAssertFalse(EditStore.hasEdit(url), "the edit is forgotten")
        XCTAssertNil(EditStore.id(of: url))
    }

    /// A saved redaction stays out, even across a later re-edit.
    func testALaterReEditCannotRevertPastARedaction() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        let hide = Mark(kind: .blackOut, a: secretLine.origin, b: CGPoint(x: secretLine.maxX, y: secretLine.maxY))
        try EditStore.commit(source: source, marks: [hide], frame: .plain, sourceIsOriginal: true, to: url)
        let (base, doc) = try XCTUnwrap(EditStore.load(for: url))
        try EditStore.commit(source: base, marks: doc.marks + [label], frame: .plain,
                             sourceIsOriginal: doc.baseIsOriginal, to: url)
        XCTAssertFalse(try XCTUnwrap(EditStore.load(for: url)).document.baseIsOriginal)
        XCTAssertFalse(try EditStore.revert(url))
    }

    func testAnUneditedCaptureHasNoEdit() throws {
        let url = try capture()
        XCTAssertFalse(EditStore.hasEdit(url))
        XCTAssertNil(EditStore.load(for: url))
        XCTAssertFalse(try EditStore.revert(url))
    }

    // MARK: Frames

    func testAFrameAddsItsMarginOnEverySide() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        let framed = try XCTUnwrap(ImageEditor.render(source, marks: [], frame: .suggested))
        let inset = FrameStyle.suggested.inset(for: CGSize(width: 1800, height: 840))
        XCTAssertEqual(inset, 67)
        XCTAssertEqual(framed.width, 1800 + 2 * 67)
        XCTAssertEqual(framed.height, 840 + 2 * 67)
        let plain = try XCTUnwrap(ImageEditor.render(source, marks: [], frame: .plain))
        XCTAssertEqual(plain.width, 1800, "a plain frame is the capture as it was")
    }

    func testRoundedCornersWithNoBackgroundAreTransparent() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        let style = FrameStyle(cornerRadius: 0.07, padding: 0, background: .none, shadow: 0)
        let out = try XCTUnwrap(ImageEditor.render(source, marks: [], frame: style))
        XCTAssertEqual(alpha(out, 1, 1), 0, "the very corner is cut away")
        XCTAssertEqual(alpha(out, 900, 420), 255, "the middle is untouched")
    }

    func testTheBackgroundFillsTheMargin() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        let style = FrameStyle(cornerRadius: 0.02, padding: 0.1, background: .solid(.sapphire), shadow: 0)
        let out = try XCTUnwrap(ImageEditor.render(source, marks: [], frame: style))
        let edge = rgba(out, 10, 10)
        XCTAssertLessThan(Int(edge.0), 20, "sapphire in the margin: \(edge)")
        XCTAssertGreaterThan(Int(edge.2), 80)
        XCTAssertGreaterThan(Int(edge.2), Int(edge.0) + 60)
    }

    /// A gradient runs the way its angle says: at 0° the left edge is the first
    /// colour and the right edge the second; at 90° it is top to bottom.
    func testAGradientRunsAlongItsAngle() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        let across = FrameStyle(cornerRadius: 0, padding: 0.1,
                                background: .gradient(.scarlet, .sapphire, angle: 0), shadow: 0)
        let out = try XCTUnwrap(ImageEditor.render(source, marks: [], frame: across))
        let left = rgba(out, 5, out.height / 2), right = rgba(out, out.width - 6, out.height / 2)
        XCTAssertGreaterThan(Int(left.0), 150, "scarlet on the left: \(left)")
        XCTAssertGreaterThan(Int(right.2), Int(right.0) + 40, "sapphire on the right: \(right)")

        let down = FrameStyle(cornerRadius: 0, padding: 0.1,
                              background: .gradient(.scarlet, .sapphire, angle: 90), shadow: 0)
        let out2 = try XCTUnwrap(ImageEditor.render(source, marks: [], frame: down))
        let top = rgba(out2, out2.width / 2, 5), bottom = rgba(out2, out2.width / 2, out2.height - 6)
        XCTAssertGreaterThan(Int(top.0), 150, "scarlet at the top: \(top)")
        XCTAssertGreaterThan(Int(bottom.2), Int(bottom.0) + 40, "sapphire at the bottom: \(bottom)")
    }

    /// A deeper shadow is darker just below the picture than a lighter one.
    func testShadowStrengthIsAStrength() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        func under(_ s: CGFloat) throws -> Int {
            let style = FrameStyle(cornerRadius: 0, padding: 0.12, background: .solid(.white), shadow: s)
            let out = try XCTUnwrap(ImageEditor.render(source, marks: [], frame: style))
            let inset = style.inset(for: CGSize(width: 1800, height: 840))
            let p = rgba(out, out.width / 2, Int(inset) + 840 + 8)
            return Int(p.0) + Int(p.1) + Int(p.2)
        }
        let none = try under(0), light = try under(0.3), deep = try under(1)
        XCTAssertGreaterThan(none, 750, "no shadow: still white under the picture")
        XCTAssertLessThan(deep, light, "deeper is darker")
        XCTAssertLessThan(light, none)
    }

    func testTheHexPaletteRoundTrips() {
        XCTAssertEqual(MarkColor(hex: "#E10600").hex, "#E10600")
        XCTAssertEqual(MarkColor.sapphire.hex, "#034060")
        XCTAssertEqual(MarkColor.tiffany.name, "Tiffany")
        XCTAssertEqual(FrameStyle.combos.count, 6)
        XCTAssertTrue(FrameStyle.combos.allSatisfy { $0.background.kind == .gradient })
    }

    // MARK: Steps

    func testStepsCountUpFromTheHighestAndRenumberInOrder() {
        var marks: [Mark] = []
        XCTAssertEqual(Mark.nextStep(after: marks), 1)
        marks.append(Mark(kind: .step, a: .zero, b: .zero, number: 1))
        marks.append(Mark(kind: .arrow, a: .zero, b: CGPoint(x: 9, y: 9)))
        marks.append(Mark(kind: .step, a: .zero, b: .zero, number: 2))
        marks.append(Mark(kind: .step, a: .zero, b: .zero, number: 7))
        XCTAssertEqual(Mark.nextStep(after: marks), 8, "one past the highest, whatever the gaps")
        let tidy = Mark.renumbered(marks)
        XCTAssertEqual(tidy.filter { $0.kind == .step }.map(\.number), [1, 2, 3], "gaps closed, order kept")
        XCTAssertEqual(tidy[1].kind, .arrow, "other marks untouched")
    }

    /// Every badge shape draws in its colour where its number sits, and is hit
    /// where it is drawn.
    func testEveryBadgeDrawsItsColourAndIsHitWhereItIs() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        for badge in Mark.Badge.allCases {
            let step = Mark(kind: .step, a: CGPoint(x: 900, y: 420), b: CGPoint(x: 900, y: 420),
                            color: .scarlet, fontSize: 40, number: 3, badge: badge)
            let out = try XCTUnwrap(ImageEditor.render(source, marks: [step]))
            let f = ImageEditor.badgeFrame(step)
            // Sample near the badge's body, off the number's glyph.
            let probe: CGPoint
            switch badge {
            case .bubble, .square: probe = CGPoint(x: f.minX + f.width * 0.18, y: f.midY)
            case .pin:             probe = CGPoint(x: f.minX + f.width * 0.18, y: f.minY + f.width / 2)
            case .flag:            probe = CGPoint(x: f.minX + f.width * 0.25, y: f.minY + f.height * 0.15)
            case .chevron:         probe = CGPoint(x: f.minX + f.width * 0.45, y: f.minY + f.height * 0.15)
            }
            let p = rgba(out, Int(probe.x), Int(probe.y))
            XCTAssertGreaterThan(Int(p.0), 180, "\(badge) is scarlet at \(probe): \(p)")
            XCTAssertLessThan(Int(p.1), 60)
            XCTAssertTrue(step.hit(CGPoint(x: f.midX, y: f.midY), tolerance: 2), "\(badge) is hit at its centre")
            XCTAssertFalse(step.hit(CGPoint(x: f.maxX + 60, y: f.midY), tolerance: 2), "\(badge) is missed beside itself")
        }
    }

    // MARK: Crop and scale

    /// A crop cuts the picture and moves the marks with it — a mark ten pixels
    /// inside the crop is ten pixels inside the result.
    func testACropCutsThePictureAndMovesTheMarksWithIt() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        let crop = CGRect(x: 400, y: 200, width: 800, height: 400)
        let box = Mark(kind: .rectangle, a: CGPoint(x: 410, y: 210), b: CGPoint(x: 600, y: 300),
                       color: .scarlet, lineWidth: 8, filled: true)
        let out = try XCTUnwrap(ImageEditor.render(source, marks: [box], crop: crop, scale: 1, frame: .plain))
        XCTAssertEqual(out.width, 800)
        XCTAssertEqual(out.height, 400)
        let inside = rgba(out, 100, 50)
        XCTAssertGreaterThan(Int(inside.0), 180, "the box landed where the crop put it: \(inside)")
        let outside = rgba(out, 5, 5)
        XCTAssertGreaterThan(Int(outside.1), 200, "and not where it would have been uncropped: \(outside)")
    }

    func testScaleResizesTheOutput() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        let half = try XCTUnwrap(ImageEditor.render(source, marks: [], crop: nil, scale: 0.5, frame: .plain))
        XCTAssertEqual(half.width, 900)
        XCTAssertEqual(half.height, 420)
        let cropAndHalf = try XCTUnwrap(ImageEditor.render(source, marks: [],
                                                            crop: CGRect(x: 0, y: 0, width: 600, height: 400),
                                                            scale: 0.5, frame: .plain))
        XCTAssertEqual(cropAndHalf.width, 300)
        XCTAssertEqual(cropAndHalf.height, 200)
    }

    /// Crop and scale are part of the kept edit, and a base pixel is not lost:
    /// undoing the crop later brings the whole picture back.
    func testCropAndScaleAreKeptAndReversible() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        let crop = CGRect(x: 200, y: 100, width: 1000, height: 500)
        try EditStore.commit(source: source, marks: [arrow], frame: .plain, crop: crop, scale: 0.5,
                             sourceIsOriginal: true, to: url)
        let saved = try XCTUnwrap(ImageEditor.load(url))
        XCTAssertEqual(saved.width, 500, "the file on disk is cropped and scaled")
        let (base, doc) = try XCTUnwrap(EditStore.load(for: url))
        XCTAssertEqual(base.width, 1800, "the kept base is the whole picture")
        XCTAssertEqual(doc.crop, crop)
        XCTAssertEqual(doc.scale, 0.5)
        XCTAssertTrue(doc.baseIsOriginal, "a crop is not a redaction; Revert still works")
        XCTAssertTrue(try EditStore.revert(url))
        XCTAssertEqual(try XCTUnwrap(ImageEditor.load(url)).width, 1800)
    }

    /// A brand picture behind the capture: kept by ShotScribe, drawn to fill
    /// the margin, and still there when the file it came from is gone.
    func testAnImageBackgroundIsKeptAndFillsTheMargin() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        // The brand picture: solid tiffany, as a file the operator "chose".
        let brand = dir.appendingPathComponent("brand.png")
        let size = NSSize(width: 300, height: 100)
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(red: 0x21 / 255, green: 0xF1 / 255, blue: 0xA8 / 255, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: brand)

        let name = try BackgroundImages.add(brand)
        try FileManager.default.removeItem(at: brand)
        XCTAssertEqual(BackgroundImages.names(), [name], "kept under its own name")

        let style = FrameStyle(cornerRadius: 0.02, padding: 0.12, background: .image(name), shadow: 0)
        let out = try XCTUnwrap(ImageEditor.render(source, marks: [], frame: style))
        let edge = rgba(out, 8, 8)
        XCTAssertGreaterThan(Int(edge.1), 200, "tiffany in the margin, from the kept copy: \(edge)")
        XCTAssertLessThan(Int(edge.0), 80)

        let second = try BackgroundImages.add(url)
        XCTAssertNotEqual(second, name)
        XCTAssertEqual(BackgroundImages.names().count, 2)
    }

    func testAMissingBackgroundImageIsAQuietNeutralNotAHole() throws {
        let url = try capture()
        let source = try XCTUnwrap(ImageEditor.load(url))
        let style = FrameStyle(cornerRadius: 0, padding: 0.1, background: .image("gone.png"), shadow: 0)
        let out = try XCTUnwrap(ImageEditor.render(source, marks: [], frame: style))
        let edge = rgba(out, 8, 8)
        XCTAssertGreaterThan(Int(edge.3), 250, "opaque")
        XCTAssertGreaterThan(Int(edge.2), 230, "frost, not black")
    }

    func testAspectFillCoversTheRectAndKeepsProportions() {
        let r = ImageEditor.aspectFill(CGSize(width: 300, height: 100), in: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertEqual(r.height, 200)
        XCTAssertEqual(r.width, 600)
        XCTAssertEqual(r.midX, 100)
    }

    /// The operator's own combos outlive the window they were made in.
    func testCustomCombosPersistBesideTheShippedOnes() {
        XCTAssertEqual(FrameStyle.customCombos(), [])
        let mine = FrameStyle.Combo(name: "Brand", background: .gradient(MarkColor(hex: "#112233"), .white, angle: 90))
        FrameStyle.setCustomCombos([mine])
        XCTAssertEqual(FrameStyle.customCombos(), [mine])
        XCTAssertEqual(FrameStyle.customCombos().first?.background.first.hex, "#112233")
        FrameStyle.setCustomCombos([])
        XCTAssertEqual(FrameStyle.customCombos(), [])
    }

    /// A kept edit written before steps, crop and scale existed still opens.
    func testAnOlderKeptEditStillDecodes() throws {
        let json = """
        {"version":1,"baseIsOriginal":true,"saved":0,
         "frame":{"cornerRadius":0,"padding":0,"shadow":0,
                  "background":{"kind":"none","first":{"red":0,"green":0,"blue":0,"alpha":1},
                                "second":{"red":0,"green":0,"blue":0,"alpha":1},"angle":45}},
         "marks":[{"id":"6BA7B810-9DAD-11D1-80B4-00C04FD430C8","kind":"arrow","a":[0,0],"b":[10,10],
                   "color":{"red":1,"green":0,"blue":0,"alpha":1},"lineWidth":4,"fontSize":18,"text":"","filled":false}]}
        """
        let doc = try JSONDecoder().decode(EditDocument.self, from: Data(json.utf8))
        XCTAssertNil(doc.crop)
        XCTAssertEqual(doc.scale, 1)
        XCTAssertEqual(doc.marks.first?.number, 1)
        XCTAssertEqual(doc.marks.first?.badge, .bubble)
    }

    private func rgba(_ image: CGImage, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return (p[0], p[1], p[2], p[3])
    }

    private func alpha(_ image: CGImage, _ x: Int, _ y: Int) -> UInt8 { rgba(image, x, y).3 }
}
