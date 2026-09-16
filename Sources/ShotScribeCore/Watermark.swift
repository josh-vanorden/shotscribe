import Foundation
import CoreGraphics
import CoreText

/// **A mark of ownership over the whole picture** — a line of text or a logo,
/// in a corner, in the middle, or tiled across everything.
///
/// Two things make a watermark hard, and both are decided here rather than
/// left to the operator (Josh, 2026-09-16: "its own challenge in the contrast
/// department and the image placement"):
///
/// - **Contrast.** With `ink` on `auto`, the picture under the watermark is
///   sampled and the watermark is set in white or near-black, whichever reads
///   against it, with a soft halo of the other. A logo becomes a silhouette in
///   that ink. `own` keeps the logo's colours (or the chosen text colour) and
///   still gets the halo.
/// - **Placement.** Sizes are fractions of the picture's short side, so one
///   watermark looks the same on a 1x capture and a Retina one, and the same
///   again after a crop or a resize.
public struct Watermark: Equatable, Sendable, Codable {
    public enum Placement: String, Codable, CaseIterable, Sendable {
        case topLeft, topRight, bottomLeft, bottomRight, centre, tiled
        public var name: String {
            switch self {
            case .topLeft: return "Top left";       case .topRight: return "Top right"
            case .bottomLeft: return "Bottom left"; case .bottomRight: return "Bottom right"
            case .centre: return "Centre";          case .tiled: return "Tiled"
            }
        }
    }
    public enum Ink: String, Codable, Sendable { case auto, own }

    /// Shown when there is no picture.
    public var text: String
    /// A picture kept in `WatermarkImages`, by name.
    public var imageName: String?
    public var placement: Placement
    /// The side of the box the watermark fits, as a fraction of the short side.
    public var size: CGFloat
    public var opacity: CGFloat
    public var font: TextFont
    /// The text colour when `ink` is `own`.
    public var color: MarkColor
    public var ink: Ink

    public static let sizeRange: ClosedRange<CGFloat> = 0.06...0.6
    public static let opacityRange: ClosedRange<CGFloat> = 0.1...1

    public init(text: String = "", imageName: String? = nil, placement: Placement = .bottomRight,
                size: CGFloat = 0.2, opacity: CGFloat = 0.6, font: TextFont = .system,
                color: MarkColor = .white, ink: Ink = .auto) {
        self.text = text; self.imageName = imageName; self.placement = placement
        self.size = min(max(size, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        self.opacity = min(max(opacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
        self.font = font; self.color = color; self.ink = ink
    }

    /// Nothing to draw: no picture and no words.
    public var isEmpty: Bool { imageName == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Where a new one starts.
    public static let suggested = Watermark()

    // MARK: Set once, used on every edit

    public static let storedKey = "shotscribe.watermark"
    public static let everyEditKey = "shotscribe.watermarkEveryEdit"

    /// The watermark kept in settings — the one "Use on every edit" applies.
    public static func stored() -> Watermark? {
        guard let data = ShotScribeDefaults.suite.data(forKey: storedKey) else { return nil }
        return try? JSONDecoder().decode(Watermark.self, from: data)
    }

    public static func store(_ watermark: Watermark?) {
        if let watermark, !watermark.isEmpty, let data = try? JSONEncoder().encode(watermark) {
            ShotScribeDefaults.suite.set(data, forKey: storedKey)
        } else {
            ShotScribeDefaults.suite.removeObject(forKey: storedKey)
        }
    }

    /// Whether every edit opened from now on starts with the stored watermark.
    public static var onEveryEdit: Bool {
        get { ShotScribeDefaults.suite.bool(forKey: everyEditKey) }
        set { ShotScribeDefaults.suite.set(newValue, forKey: everyEditKey) }
    }

    /// The one a fresh edit begins with, if the operator asked for that.
    public static func forNewEdit() -> Watermark? {
        guard onEveryEdit, let kept = stored(), !kept.isEmpty else { return nil }
        return kept
    }
}

/// Logos brought in to watermark with, kept beside the frame backgrounds.
public enum WatermarkImages {
    public static var rootOverride: URL?
    public static var root: URL { rootOverride ?? KeptPictures.support("Watermarks") }
    @discardableResult
    public static func add(_ url: URL) throws -> String { try KeptPictures.add(url, to: root) }
    public static func url(for name: String) -> URL { root.appendingPathComponent(name) }
    public static func load(_ name: String) -> CGImage? { ImageEditor.load(url(for: name)) }
    public static func names() -> [String] { KeptPictures.names(in: root) }
    public static func remove(_ name: String) { try? FileManager.default.removeItem(at: url(for: name)) }
}

extension ImageEditor {
    /// `picture` with `watermark` on it. The picture is sampled for the ink.
    public static func stamped(_ picture: CGImage, with watermark: Watermark) -> CGImage? {
        guard !watermark.isEmpty else { return picture }
        let w = picture.width, h = picture.height
        guard w > 0, h > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(picture, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        drawWatermark(watermark, in: ctx, size: CGSize(width: w, height: h), under: picture,
                      logo: watermark.imageName.flatMap(WatermarkImages.load))
        return ctx.makeImage()
    }

    /// Draw `watermark` over a picture of `size` in a top-down context whose
    /// origin is the picture's top-left. `under` is that picture, for the
    /// auto ink; `logo` is the kept picture already decoded, if there is one.
    public static func drawWatermark(_ watermark: Watermark, in ctx: CGContext, size: CGSize,
                                     under: CGImage?, underOrigin: CGPoint = .zero, logo: CGImage?) {
        guard !watermark.isEmpty, size.width > 0, size.height > 0 else { return }
        let short = min(size.width, size.height)
        let side = (short * watermark.size).rounded()
        let margin = (short * 0.035).rounded()

        // What is being drawn, and how big it is.
        let content: WatermarkContent
        if let logo, watermark.imageName != nil {
            let s = min(side / CGFloat(logo.width), side / CGFloat(logo.height))
            content = .picture(logo, CGSize(width: CGFloat(logo.width) * s, height: CGFloat(logo.height) * s))
        } else if watermark.imageName == nil {
            let font = watermark.font.font(size: max(8, side * 0.3))
            // CoreText draws black unless told to take the context's fill —
            // which is where the ink goes, once what is under it is known.
            let attrs: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true,
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: watermark.text.trimmingCharacters(in: .whitespacesAndNewlines), attributes: attrs))
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
            content = .words(line, CGSize(width: width, height: ascent + descent), ascent)
        } else {
            return   // a picture that is gone: draw nothing rather than the wrong thing
        }
        let extent = content.size

        // Where.
        let box: CGRect
        switch watermark.placement {
        case .topLeft:     box = CGRect(x: margin, y: margin, width: extent.width, height: extent.height)
        case .topRight:    box = CGRect(x: size.width - margin - extent.width, y: margin, width: extent.width, height: extent.height)
        case .bottomLeft:  box = CGRect(x: margin, y: size.height - margin - extent.height, width: extent.width, height: extent.height)
        case .bottomRight: box = CGRect(x: size.width - margin - extent.width, y: size.height - margin - extent.height, width: extent.width, height: extent.height)
        case .centre, .tiled:
            box = CGRect(x: (size.width - extent.width) / 2, y: (size.height - extent.height) / 2, width: extent.width, height: extent.height)
        }

        // The ink: against what is under the watermark — the whole picture when tiled.
        // `under` may be the whole base while `size` is the cropped part of it.
        let sampleRect = (watermark.placement == .tiled ? CGRect(origin: .zero, size: size) : box)
            .offsetBy(dx: underOrigin.x, dy: underOrigin.y)
        let luma = under.map { luminance(of: $0, in: sampleRect) } ?? 0.5
        let lightInk = luma < 0.55
        let autoInk = lightInk ? CGColor(gray: 1, alpha: 1) : CGColor(srgbRed: 0.09, green: 0.09, blue: 0.09, alpha: 1)
        let ownIsLight: Bool
        switch content {
        case .words: ownIsLight = watermark.color.wantsLightText == false   // a light colour is "light"
        case .picture: ownIsLight = lightInk
        }
        let halo = (watermark.ink == .auto ? lightInk : ownIsLight)
            ? CGColor(gray: 0, alpha: 0.55) : CGColor(gray: 1, alpha: 0.6)

        ctx.saveGState()
        ctx.setAlpha(watermark.opacity)
        ctx.setShadow(offset: .zero, blur: max(2, side * 0.06), color: halo)
        if watermark.placement == .tiled {
            // A diagonal lattice across the whole picture, one copy per cell.
            let stepX = extent.width * 1.7 + short * 0.05, stepY = extent.height * 2.6 + short * 0.05
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: -.pi / 6)
            let reach = hypot(size.width, size.height) / 2
            var y = -reach, row = 0
            while y < reach {
                var x = -reach - (row % 2 == 1 ? stepX / 2 : 0)
                while x < reach {
                    draw(content, at: CGRect(x: x, y: y, width: extent.width, height: extent.height),
                         ink: watermark.ink, autoInk: autoInk, color: watermark.color.cgColor, in: ctx)
                    x += stepX
                }
                y += stepY; row += 1
            }
        } else {
            draw(content, at: box, ink: watermark.ink, autoInk: autoInk, color: watermark.color.cgColor, in: ctx)
        }
        ctx.restoreGState()
    }

    private enum WatermarkContent {
        case words(CTLine, CGSize, CGFloat)
        case picture(CGImage, CGSize)
        var size: CGSize {
            switch self {
            case .words(_, let s, _): return s
            case .picture(_, let s): return s
            }
        }
    }

    private static func draw(_ content: WatermarkContent, at box: CGRect, ink: Watermark.Ink,
                             autoInk: CGColor, color: CGColor, in ctx: CGContext) {
        switch content {
        case .words(let line, _, let ascent):
            ctx.saveGState()
            ctx.setFillColor(ink == .auto ? autoInk : color)
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            ctx.textPosition = CGPoint(x: box.minX, y: box.minY + ascent)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        case .picture(let logo, _):
            // Through the logo's shape either way, so a logo on a flat
            // background is the logo, never the box it came in.
            ctx.saveGState()
            ctx.translateBy(x: box.minX, y: box.maxY)
            ctx.scaleBy(x: 1, y: -1)
            let r = CGRect(origin: .zero, size: box.size)
            if let mask = logoMask(of: logo) { ctx.clip(to: r, mask: mask) }
            if ink == .auto, logoMask(of: logo) != nil {
                ctx.setFillColor(autoInk)
                ctx.fill(r)
            } else {
                ctx.draw(logo, in: r)
            }
            ctx.restoreGState()
        }
    }

    /// The logo's shape as a grey picture for clipping — white shows, black
    /// hides. Its alpha when it has any worth the name; otherwise whatever is
    /// not the colour of its edges, so a logo exported on a white square is
    /// the logo, not the square (Josh, 2026-09-16: "made a shaded box").
    /// Remembered for the last logo asked about; the canvas asks on every paint.
    static func logoMask(of image: CGImage) -> CGImage? {
        maskLock.lock(); defer { maskLock.unlock() }
        if let c = maskCache, c.image === image { return c.mask }
        let mask = alphaMask(of: image) ?? keyedMask(of: image)
        maskCache = (image, mask)
        return mask
    }
    private static var maskCache: (image: CGImage, mask: CGImage?)?
    private static let maskLock = NSLock()

    /// The alpha channel, when at least a little of the picture is see-through.
    static func alphaMask(of image: CGImage) -> CGImage? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return nil
        default: break
        }
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let alpha = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
        else { return nil }
        alpha.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let bytes = alpha.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var clear = 0
        for i in 0..<(w * h) where bytes[i] < 250 { clear += 1 }
        // An alpha channel that is opaque everywhere is a box, not a shape.
        guard clear * 100 >= w * h else { return nil }
        return grayImage(Data(bytes: bytes, count: w * h), width: w, height: h)
    }

    /// Everything that is not the colour of the picture's edges.
    static func keyedMask(of image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 2, h > 2,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let px = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        // The background is the typical edge colour: the median of each channel along the border.
        var rs: [Int] = [], gs: [Int] = [], bs: [Int] = []
        func edge(_ x: Int, _ y: Int) { let i = (y * w + x) * 4; rs.append(Int(px[i])); gs.append(Int(px[i + 1])); bs.append(Int(px[i + 2])) }
        for x in 0..<w { edge(x, 0); edge(x, h - 1) }
        for y in 1..<(h - 1) { edge(0, y); edge(w - 1, y) }
        rs.sort(); gs.sort(); bs.sort()
        let bg = (rs[rs.count / 2], gs[gs.count / 2], bs[bs.count / 2])
        var out = Data(count: w * h)
        out.withUnsafeMutableBytes { raw in
            let m = raw.bindMemory(to: UInt8.self)
            for i in 0..<(w * h) {
                let p = i * 4
                let d = max(abs(Int(px[p]) - bg.0), abs(Int(px[p + 1]) - bg.1), abs(Int(px[p + 2]) - bg.2))
                // Fully the logo 96 steps away from the background; soft below that.
                m[i] = UInt8(min(255, d * 255 / 96))
            }
        }
        return grayImage(out, width: w, height: h)
    }

    private static func grayImage(_ data: Data, width w: Int, height h: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// How light the picture is inside `rect`, 0 dark … 1 light. `rect` is in
    /// the picture's own pixels, top-left origin. Remembered for the last
    /// picture asked about, since the canvas asks on every paint.
    public static func luminance(of image: CGImage, in rect: CGRect) -> CGFloat {
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let r = rect.intersection(full).integral
        guard !r.isEmpty else { return 0.5 }
        lumaLock.lock(); defer { lumaLock.unlock() }
        if let c = lumaCache, c.image === image, c.rect == r { return c.value }
        guard let part = image.cropping(to: r),
              let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let bytes = ctx.data?.assumingMemoryBound(to: UInt8.self)
        else { return 0.5 }
        // Under the watermark of a see-through picture is white — the page.
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        ctx.interpolationQuality = .high
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: 4, height: 4))
        var sum: CGFloat = 0
        for i in 0..<16 {
            let p = i * 4
            sum += 0.2126 * CGFloat(bytes[p]) + 0.7152 * CGFloat(bytes[p + 1]) + 0.0722 * CGFloat(bytes[p + 2])
        }
        let value = sum / (16 * 255)
        lumaCache = (image, r, value)
        return value
    }
    private static var lumaCache: (image: CGImage, rect: CGRect, value: CGFloat)?
    private static let lumaLock = NSLock()
}
