import XCTest
import CoreGraphics
@testable import ShotScribeCore

/// The watermark: ink that reads against what is under it, placement as
/// fractions of the picture, logos kept by ShotScribe, and the one watermark
/// set once and used on every edit.
final class WatermarkTests: XCTestCase {
    private var root: URL!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("shotscribe-wm-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        WatermarkImages.rootOverride = root.appendingPathComponent("logos")
        EditStore.rootOverride = root.appendingPathComponent("edits")
        suiteName = "shotscribe-wm-\(UUID().uuidString)"
        ShotScribeDefaults.suiteOverride = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        ShotScribeDefaults.suiteOverride?.removePersistentDomain(forName: suiteName)
        ShotScribeDefaults.suiteOverride = nil
        WatermarkImages.rootOverride = nil
        EditStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    // MARK: Fixtures

    private func flat(_ gray: CGFloat, width: Int = 800, height: Int = 500) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// A red disc on a transparent square, written as a PNG.
    private func logoFile() throws -> URL {
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.05, blue: 0.05, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 2, y: 2, width: 60, height: 60))
        let url = root.appendingPathComponent("disc.png")
        try ImageEditor.save(ctx.makeImage()!, over: url)
        return url
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return (Int(p[0]), Int(p[1]), Int(p[2]))
    }

    /// The darkest and lightest sample on a grid inside `rect`, top-left origin.
    private func range(_ image: CGImage, in rect: CGRect) -> (darkest: Int, lightest: Int, reddest: (r: Int, g: Int, b: Int)) {
        var darkest = 255 * 3, lightest = 0, reddest = (r: 0, g: 255, b: 255)
        for i in 0..<24 {
            for j in 0..<24 {
                let x = Int(rect.minX + rect.width * (CGFloat(i) + 0.5) / 24)
                let y = Int(rect.minY + rect.height * (CGFloat(j) + 0.5) / 24)
                let p = pixel(image, x, y)
                let sum = p.r + p.g + p.b
                darkest = min(darkest, sum); lightest = max(lightest, sum)
                if p.r - max(p.g, p.b) > reddest.r - max(reddest.g, reddest.b) { reddest = p }
            }
        }
        return (darkest, lightest, reddest)
    }

    private var corner: CGRect { CGRect(x: 520, y: 360, width: 280, height: 140) }
    private var farCorner: CGRect { CGRect(x: 0, y: 0, width: 300, height: 150) }

    // MARK: Ink and placement

    /// Words in the bottom-right, and only there. On a white picture the ink
    /// is dark; on a dark one, light — nobody chose a colour.
    func testWordsAreSetInInkThatReadsAgainstThePicture() throws {
        let wm = Watermark(text: "ACME", placement: .bottomRight, size: 0.3, opacity: 1)
        let onWhite = try XCTUnwrap(ImageEditor.stamped(flat(1), with: wm))
        XCTAssertLessThan(range(onWhite, in: corner).darkest, 300, "dark ink on a white picture")
        XCTAssertGreaterThan(range(onWhite, in: farCorner).darkest, 740, "and nothing in the opposite corner")

        let onDark = try XCTUnwrap(ImageEditor.stamped(flat(0.1), with: wm))
        XCTAssertGreaterThan(range(onDark, in: corner).lightest, 500, "light ink on a dark picture")
        XCTAssertLessThan(range(onDark, in: farCorner).lightest, 120, "and the far corner untouched")
    }

    func testAChosenColourIsHonoured() throws {
        let wm = Watermark(text: "ACME", placement: .topLeft, size: 0.3, opacity: 1, color: .scarlet, ink: .own)
        let out = try XCTUnwrap(ImageEditor.stamped(flat(1), with: wm))
        let red = range(out, in: farCorner).reddest
        XCTAssertGreaterThan(red.r, 180, "scarlet type: \(red)")
        XCTAssertLessThan(red.g, 90, "not the auto ink: \(red)")
    }

    func testTiledCoversTheWholePicture() throws {
        let wm = Watermark(text: "ACME", placement: .tiled, size: 0.18, opacity: 1)
        let out = try XCTUnwrap(ImageEditor.stamped(flat(1), with: wm))
        let quadrants = [CGRect(x: 0, y: 0, width: 400, height: 250), CGRect(x: 400, y: 0, width: 400, height: 250),
                         CGRect(x: 0, y: 250, width: 400, height: 250), CGRect(x: 400, y: 250, width: 400, height: 250)]
        for q in quadrants {
            XCTAssertLessThan(range(out, in: q).darkest, 400, "ink in every quadrant: \(q)")
        }
    }

    func testAnEmptyWatermarkDrawsNothing() throws {
        XCTAssertTrue(Watermark(text: "   ").isEmpty)
        let out = try XCTUnwrap(ImageEditor.stamped(flat(1), with: Watermark(text: " ")))
        XCTAssertGreaterThan(range(out, in: corner).darkest, 740)
    }

    // MARK: Logos

    /// A logo is kept by ShotScribe, drawn as it is when asked, and as a
    /// silhouette in the auto ink otherwise — so a red logo still reads on red.
    func testALogoIsKeptAndDrawnAsItselfOrAsASilhouette() throws {
        let name = try WatermarkImages.add(try logoFile())
        XCTAssertEqual(WatermarkImages.names(), [name])

        let asIs = Watermark(imageName: name, placement: .bottomRight, size: 0.3, opacity: 1, ink: .own)
        let own = try XCTUnwrap(ImageEditor.stamped(flat(1), with: asIs))
        let red = range(own, in: corner).reddest
        XCTAssertGreaterThan(red.r - max(red.g, red.b), 120, "the disc in its own red: \(red)")

        let silhouette = try XCTUnwrap(ImageEditor.stamped(flat(1), with: Watermark(imageName: name, placement: .bottomRight, size: 0.3, opacity: 1, ink: .auto)))
        let s = range(silhouette, in: corner)
        XCTAssertLessThan(s.darkest, 200, "the disc's shape in dark ink")
        XCTAssertLessThan(s.reddest.r - max(s.reddest.g, s.reddest.b), 40, "and none of its red: \(s.reddest)")

        WatermarkImages.remove(name)
        XCTAssertTrue(WatermarkImages.names().isEmpty)
        let gone = try XCTUnwrap(ImageEditor.stamped(flat(1), with: asIs))
        XCTAssertGreaterThan(range(gone, in: corner).darkest, 740, "a logo that is gone draws nothing rather than the wrong thing")
    }

    /// A logo exported on a white square — no transparency at all — is drawn
    /// as the logo: the square is keyed out, whichever ink is chosen.
    func testALogoOnAFlatBackgroundLosesTheBackground() throws {
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.05, blue: 0.05, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 6, y: 6, width: 52, height: 52))
        let flatURL = root.appendingPathComponent("flat.png")
        try ImageEditor.save(ctx.makeImage()!, over: flatURL)
        let name = try WatermarkImages.add(flatURL)
        XCTAssertNil(ImageEditor.alphaMask(of: try XCTUnwrap(WatermarkImages.load(name))), "no transparency to speak of")

        // On a mid-grey picture, so both the square and the ink would show.
        let grey = flat(0.5)
        let box = CGRect(x: 800 - 28 - 150, y: 500 - 28 - 150, width: 150, height: 150)   // size 0.3 of 500, margin 3.5%
        let cornerOfBox = CGRect(x: box.minX, y: box.minY, width: 14, height: 14)
        let centreOfBox = CGRect(x: box.midX - 10, y: box.midY - 10, width: 20, height: 20)

        let own = try XCTUnwrap(ImageEditor.stamped(grey, with: Watermark(imageName: name, placement: .bottomRight, size: 0.3, opacity: 1, ink: .own)))
        let ownCentre = range(own, in: centreOfBox).reddest
        XCTAssertGreaterThan(ownCentre.r - max(ownCentre.g, ownCentre.b), 120, "the disc in its own red: \(ownCentre)")
        let ownCorner = range(own, in: cornerOfBox)
        XCTAssertLessThan(ownCorner.lightest, 3 * 200, "no white square around it: \(ownCorner)")

        let auto = try XCTUnwrap(ImageEditor.stamped(grey, with: Watermark(imageName: name, placement: .bottomRight, size: 0.3, opacity: 1, ink: .auto)))
        XCTAssertLessThan(range(auto, in: centreOfBox).darkest, 3 * 60, "the disc as a dark silhouette on mid grey")
        let autoCorner = range(auto, in: cornerOfBox)
        XCTAssertGreaterThan(autoCorner.darkest, 3 * 90, "and no box in the ink either: \(autoCorner)")
    }

    // MARK: Kept with the edit, and set once for every edit

    func testAnEditKeepsItsWatermarkAndOlderEditsHaveNone() throws {
        let url = root.appendingPathComponent("shot.png")
        try ImageEditor.save(flat(1), over: url)
        let wm = Watermark(text: "ACME", placement: .bottomRight, size: 0.3, opacity: 1, font: .serif)
        let doc = try EditStore.commit(source: flat(1), marks: [], frame: .plain, watermark: wm,
                                       sourceIsOriginal: true, to: url)
        XCTAssertEqual(doc.watermark, wm)
        let kept = try XCTUnwrap(EditStore.load(for: url))
        XCTAssertEqual(kept.document.watermark, wm, "reopened with the same watermark")
        let saved = try XCTUnwrap(ImageEditor.load(url))
        XCTAssertLessThan(range(saved, in: corner).darkest, 300, "and the file on disk carries it")

        let older = #"{"marks":[],"frame":\#(String(decoding: try JSONEncoder().encode(FrameStyle.plain), as: UTF8.self)),"baseIsOriginal":true,"saved":0}"#
        XCTAssertNil(try JSONDecoder().decode(EditDocument.self, from: Data(older.utf8)).watermark)
    }

    func testTheKeptWatermarkStartsEveryEditOnlyWhenAsked() {
        let wm = Watermark(text: "ACME", placement: .centre, size: 0.25, opacity: 0.5)
        XCTAssertNil(Watermark.stored())
        Watermark.store(wm)
        XCTAssertEqual(Watermark.stored(), wm)
        XCTAssertNil(Watermark.forNewEdit(), "kept, but not yet asked for on every edit")
        Watermark.onEveryEdit = true
        XCTAssertEqual(Watermark.forNewEdit(), wm)
        Watermark.store(Watermark(text: ""))
        XCTAssertNil(Watermark.stored(), "an empty one is not kept")
        XCTAssertNil(Watermark.forNewEdit())
    }

    // MARK: Fonts

    func testAFaceIsKeptWithTheMarkAndAMissingOneFallsBack() throws {
        let label = Mark(kind: .text, a: .zero, b: .zero, fontSize: 24, text: "Hello", font: .serif)
        let kept = try JSONDecoder().decode(Mark.self, from: try JSONEncoder().encode(label))
        XCTAssertEqual(kept.font, .serif)
        XCTAssertEqual(TextFont(stored: "family:Avenir Next"), .family("Avenir Next"))
        XCTAssertEqual(TextFont(stored: "nonsense"), .system)

        let system = CTFontCopyFamilyName(TextFont.system.font(size: 20)) as String
        XCTAssertNotEqual(CTFontCopyFamilyName(TextFont.serif.font(size: 20)) as String, system, "serif is another face")
        XCTAssertNotEqual(CTFontCopyFamilyName(TextFont.mono.font(size: 20)) as String, system, "so is mono")
        let missing = TextFont.family("No Such Face 1234")
        XCTAssertFalse(missing.isInstalled)
        XCTAssertEqual(CTFontCopyFamilyName(missing.font(size: 20)) as String, system, "a face that is gone falls back to the system's")

        let narrow = ImageEditor.labelFrame(text: "iiiiiiii", fontSize: 24, font: .system, at: .zero).width
        let mono = ImageEditor.labelFrame(text: "iiiiiiii", fontSize: 24, font: .mono, at: .zero).width
        XCTAssertGreaterThan(mono, narrow * 1.3, "the label's box follows the face: \(mono) vs \(narrow)")
    }
}
