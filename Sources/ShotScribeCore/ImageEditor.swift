import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// A colour a mark can be drawn in. Plain components rather than `CGColor`,
/// so a mark can be compared, stored and handed between threads.
public struct MarkColor: Hashable, Sendable, Codable {
    public var red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    public var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    /// Whether white type reads on this colour; a label on yellow or white
    /// gets dark type instead.
    public var wantsLightText: Bool { 0.2126 * red + 0.7152 * green + 0.0722 * blue < 0.62 }

    /// The type that reads on this colour: white on a dark one, near-black
    /// on a light one. Labels, step numbers and the watermark all use it.
    public var ink: CGColor { wantsLightText ? CGColor(gray: 1, alpha: 1) : Self.darkInk }
    public static let darkInk = CGColor(gray: 0.08, alpha: 1)

    /// `#RRGGBB` or `#RGB` with the digits checked; nil for anything else.
    public init?(validatingHex text: String) {
        let s = text.trimmingCharacters(in: .whitespaces)
        let digits = s.hasPrefix("#") ? String(s.dropFirst()) : s
        guard digits.count == 6 || digits.count == 3, UInt32(digits, radix: 16) != nil else { return nil }
        self.init(hex: s)
    }

    /// `#RRGGBB`, the way a palette is written down.
    public init(hex: String) {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let n = UInt32(s, radix: 16) ?? 0
        self.init(red: CGFloat((n >> 16) & 0xFF) / 255, green: CGFloat((n >> 8) & 0xFF) / 255,
                  blue: CGFloat(n & 0xFF) / 255)
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    // Josh's palette, 2026-09-16. Named as he named them.
    public static let scarlet     = MarkColor(hex: "#E10600")
    public static let vividYellow = MarkColor(hex: "#FFC107")
    public static let sage        = MarkColor(hex: "#8CA986")
    public static let sand        = MarkColor(hex: "#EADFCF")
    public static let frost       = MarkColor(hex: "#EEF2FF")
    public static let sapphire    = MarkColor(hex: "#034060")
    public static let cream       = MarkColor(hex: "#FAF3E0")
    public static let forest      = MarkColor(hex: "#2D6A4F")
    public static let tiffany     = MarkColor(hex: "#21F1A8")
    public static let darkGrey    = MarkColor(hex: "#171717")

    /// ShotScribe's own accent.
    public static let purple = MarkColor(red: 0.361, green: 0.286, blue: 0.639)
    public static let white  = MarkColor(red: 1.00, green: 1.00, blue: 1.00)
    public static let black  = MarkColor.darkGrey

    // Kept for the marks that already use them.
    public static let red    = scarlet
    public static let yellow = vividYellow
    public static let green  = forest
    public static let blue   = sapphire

    /// The swatches a mark can take: black first, then white, then his colours
    /// and the accent (Josh, 2026-09-16: "Black then white, then color").
    public static let palette: [MarkColor] = [.darkGrey, .white, .scarlet, .vividYellow, .sage, .sapphire, .forest, .tiffany, .purple]

    public static let names: [MarkColor: String] = [
        .scarlet: "Scarlet", .vividYellow: "Vivid Yellow", .sage: "Sage", .sand: "Sand", .frost: "Frost",
        .sapphire: "Sapphire", .cream: "Cream", .forest: "Forest", .tiffany: "Tiffany", .darkGrey: "Dark Grey",
        .purple: "Lavender", .white: "White",
    ]
    public var name: String { Self.names[self] ?? hex }
}

/// **One mark on a screenshot, kept as an object until the file is saved.**
///
/// The first editor baked each mark into the picture the moment the mouse came
/// up, so nothing could be selected, moved or recoloured afterwards (Josh,
/// 2026-09-16: "unable to edit any of the added items"). A mark is now a value
/// with an identity; the picture is only flattened on Save.
///
/// Geometry is two points, `a` and `b`, in **image pixels, top-left origin**.
/// A segment runs from one to the other; every other kind uses the rectangle
/// they span, except a label, which sits with its top-left corner at `a`.
public struct Mark: Identifiable, Equatable, Sendable, Codable {
    public enum Kind: String, CaseIterable, Sendable, Codable {
        case pixelate, blackOut, rectangle, ellipse, line, arrow, highlight, text, step

        /// Hides what is underneath rather than drawing on it.
        public var redacts: Bool { self == .pixelate || self == .blackOut }
        public var isSegment: Bool { self == .line || self == .arrow }
        /// Placed with a click, not a drag: it has a position, not an extent.
        public var isPoint: Bool { self == .text || self == .step }
        /// A black-out takes a colour — any opaque block hides what is under it;
        /// only pixelation has no colour to choose.
        public var takesColor: Bool { self != .pixelate }
        public var takesLineWidth: Bool { self == .rectangle || self == .ellipse || isSegment }
        public var takesFill: Bool { self == .rectangle || self == .ellipse }
        public var takesFontSize: Bool { isPoint }
    }

    /// How a step's number is worn. The known shapes people count with.
    public enum Badge: String, CaseIterable, Sendable, Codable {
        case bubble, square, chevron, flag, pin
        public var name: String {
            switch self {
            case .bubble:  return "Bubble"
            case .square:  return "Square"
            case .chevron: return "Chevron"
            case .flag:    return "Flag"
            case .pin:     return "Pin"
            }
        }
    }

    public let id: UUID
    public var kind: Kind
    public var a: CGPoint
    public var b: CGPoint
    public var color: MarkColor
    public var lineWidth: CGFloat
    public var fontSize: CGFloat
    public var text: String
    public var filled: Bool
    /// A step's number, and the shape it sits in.
    public var number: Int
    public var badge: Badge
    /// Where a line or arrow bows out to, if it is not straight: the curve
    /// passes through this point half-way along. `nil` is straight. The
    /// middle handle that macOS Preview gives an arrow (Josh, 2026-09-16).
    public var bend: CGPoint?
    /// The face a label or a step number is set in.
    public var font: TextFont

    public init(id: UUID = UUID(), kind: Kind, a: CGPoint, b: CGPoint, color: MarkColor = .black,
                lineWidth: CGFloat = 4, fontSize: CGFloat = 18, text: String = "", filled: Bool = false,
                number: Int = 1, badge: Badge = .bubble, bend: CGPoint? = nil, font: TextFont = .system) {
        self.id = id; self.kind = kind; self.a = a; self.b = b; self.color = color
        self.lineWidth = lineWidth; self.fontSize = fontSize; self.text = text; self.filled = filled
        self.number = number; self.badge = badge; self.bend = bend; self.font = font
    }

    // A kept edit from before steps existed has no number or badge; one from
    // before curves has no bend.
    private enum CodingKeys: String, CodingKey {
        case id, kind, a, b, color, lineWidth, fontSize, text, filled, number, badge, bend, font
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        a = try c.decode(CGPoint.self, forKey: .a)
        b = try c.decode(CGPoint.self, forKey: .b)
        color = try c.decode(MarkColor.self, forKey: .color)
        lineWidth = try c.decode(CGFloat.self, forKey: .lineWidth)
        fontSize = try c.decode(CGFloat.self, forKey: .fontSize)
        text = try c.decode(String.self, forKey: .text)
        filled = try c.decode(Bool.self, forKey: .filled)
        number = try c.decodeIfPresent(Int.self, forKey: .number) ?? 1
        badge = try c.decodeIfPresent(Badge.self, forKey: .badge) ?? .bubble
        bend = try c.decodeIfPresent(CGPoint.self, forKey: .bend)
        font = try c.decodeIfPresent(TextFont.self, forKey: .font) ?? .system
    }

    /// The next number a new step should take: one past the highest so far.
    public static func nextStep(after marks: [Mark]) -> Int {
        (marks.filter { $0.kind == .step }.map(\.number).max() ?? 0) + 1
    }

    /// Close the gaps: steps numbered 1, 2, 3… in the order they were placed.
    public static func renumbered(_ marks: [Mark]) -> [Mark] {
        var n = 0
        return marks.map { m in
            guard m.kind == .step else { return m }
            n += 1
            var s = m; s.number = n
            return s
        }
    }

    /// The rectangle `a` and `b` span, whichever way it was dragged.
    public var rect: CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// What a person grabs: a label's pill, a segment with its stroke, a shape's box.
    public var frame: CGRect {
        switch kind {
        case .text:             return ImageEditor.labelFrame(text: text, fontSize: fontSize, font: font, at: a)
        case .step:             return ImageEditor.badgeFrame(self)
        case .line, .arrow:     return curveBox.insetBy(dx: -lineWidth, dy: -lineWidth)
        default:                return rect
        }
    }

    public mutating func move(dx: CGFloat, dy: CGFloat) {
        a.x += dx; a.y += dy; b.x += dx; b.y += dy
        if let p = bend { bend = CGPoint(x: p.x + dx, y: p.y + dy) }
    }

    /// A step badge is about two lines of its number tall.
    public var badgeDiameter: CGFloat { (fontSize * 1.9).rounded() }

    // MARK: The curve

    /// The control point of the quadratic curve that passes through `bend`
    /// half-way from `a` to `b`; nil when the segment is straight.
    public var control: CGPoint? {
        guard kind.isSegment, let p = bend else { return nil }
        return CGPoint(x: 2 * p.x - (a.x + b.x) / 2, y: 2 * p.y - (a.y + b.y) / 2)
    }

    /// Where the segment is at `t` in 0…1, curved or not.
    public func point(at t: CGFloat) -> CGPoint {
        guard let c = control else { return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        return Self.quadPoint(a, c, b, t)
    }

    /// Half-way along, where the middle handle sits.
    public var midpoint: CGPoint { point(at: 0.5) }

    /// The box the whole curve fits in — the control point can lie beyond the bend.
    var curveBox: CGRect {
        guard let c = control else { return rect }
        return rect.union(CGRect(origin: c, size: .zero))
    }

    static func quadPoint(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x,
                       y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
    }

    /// The curve as a run of short straight pieces, for lengths and hit tests.
    func polyline(_ pieces: Int = 32) -> [CGPoint] {
        guard control != nil else { return [a, b] }
        return (0...pieces).map { point(at: CGFloat($0) / CGFloat(pieces)) }
    }

    public var length: CGFloat {
        let pts = polyline()
        return zip(pts, pts.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// Whether a point is on this mark. `tolerance` is in image pixels, so a
    /// caller can make the target a constant size on screen at any zoom.
    public func hit(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        if kind.isSegment {
            let pts = polyline()
            let d = zip(pts, pts.dropFirst()).map { Self.distance(from: p, toSegment: $0.0, $0.1) }.min() ?? .infinity
            return d <= max(tolerance, lineWidth / 2 + tolerance / 2)
        }
        return frame.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

/// **How the picture sits on the page**: its corners, the margin around it,
/// what fills that margin, and whether it casts a shadow onto it.
///
/// Sizes are fractions of the capture's short side, so one preset looks the
/// same on a 1x shot and a Retina one. A plain frame — square, no margin — is
/// the capture exactly as it was.
public struct FrameStyle: Equatable, Sendable, Codable {
    /// The margin's fill. A gradient runs between two colours along an angle
    /// — 0° is left to right, 90° is top to bottom, 45° is the diagonal.
    public struct Background: Equatable, Sendable, Codable {
        public enum Kind: String, Codable, Sendable { case none, solid, gradient, image }
        public var kind: Kind
        public var first: MarkColor
        public var second: MarkColor
        public var angle: CGFloat
        /// For `.image`: a file in `BackgroundImages`, by name — a branding
        /// picture the operator brought in, kept by ShotScribe so the frame
        /// still renders after the original moves.
        public var imageName: String?

        public init(kind: Kind = .none, first: MarkColor = .frost, second: MarkColor = .sapphire,
                    angle: CGFloat = 45, imageName: String? = nil) {
            self.kind = kind; self.first = first; self.second = second; self.angle = angle; self.imageName = imageName
        }

        public static let none = Background()
        public static func solid(_ c: MarkColor) -> Background { Background(kind: .solid, first: c, second: c) }
        public static func gradient(_ a: MarkColor, _ b: MarkColor, angle: CGFloat = 45) -> Background {
            Background(kind: .gradient, first: a, second: b, angle: angle)
        }
        public static func image(_ name: String) -> Background { Background(kind: .image, imageName: name) }
        // `imageName` is optional, so a background kept before pictures existed
        // decodes as it is — the synthesised decoder already reads it if present.
    }

    /// Fraction of the short side: 0 is square, 0.12 is very round.
    public var cornerRadius: CGFloat
    /// Fraction of the short side, each side.
    public var padding: CGFloat
    public var background: Background
    /// 0 is none, 1 is a deep shadow. A slider, not a switch.
    public var shadow: CGFloat

    public init(cornerRadius: CGFloat = 0, padding: CGFloat = 0,
                background: Background = .none, shadow: CGFloat = 0) {
        self.cornerRadius = cornerRadius; self.padding = padding
        self.background = background; self.shadow = shadow
    }

    public static let maxCornerRadius: CGFloat = 0.12
    public static let maxPadding: CGFloat = 0.25

    public static let plain = FrameStyle()
    public var isPlain: Bool { cornerRadius <= 0 && padding <= 0 }

    /// What turning the frame on starts from: rounded, a margin, one of Josh's
    /// combos behind it, and a soft shadow.
    public static let suggested = FrameStyle(cornerRadius: 0.035, padding: 0.08,
                                             background: combos[0].background, shadow: 0.55)

    /// Two colours together. The shipped list is Josh's; the operator's own are
    /// kept in the settings domain beside it.
    public struct Combo: Equatable, Sendable, Codable {
        public let name: String
        public let background: Background
        public init(name: String, background: Background) { self.name = name; self.background = background }
    }

    public static let customCombosKey = "shotscribe.frameCombos"

    public static func customCombos() -> [Combo] {
        guard let data = ShotScribeDefaults.suite.data(forKey: customCombosKey),
              let list = try? JSONDecoder().decode([Combo].self, from: data) else { return [] }
        return list
    }

    public static func setCustomCombos(_ list: [Combo]) {
        if list.isEmpty { ShotScribeDefaults.suite.removeObject(forKey: customCombosKey) }
        else if let data = try? JSONEncoder().encode(list) { ShotScribeDefaults.suite.set(data, forKey: customCombosKey) }
    }

    public static let combos: [Combo] = [
        Combo(name: "Sapphire & Frost",   background: .gradient(.sapphire, .frost, angle: 45)),
        Combo(name: "Scarlet & Yellow",   background: .gradient(.scarlet, .vividYellow, angle: 30)),
        Combo(name: "Sage & Sand",        background: .gradient(.sage, .sand, angle: 60)),
        Combo(name: "Forest & Cream",     background: .gradient(.forest, .cream, angle: 45)),
        Combo(name: "Tiffany & Dark Grey", background: .gradient(.tiffany, .darkGrey, angle: 135)),
        Combo(name: "Lavender",           background: .gradient(MarkColor(red: 0.60, green: 0.54, blue: 0.88),
                                                                 MarkColor(red: 0.29, green: 0.22, blue: 0.56), angle: 45)),
    ]

    /// The colours a frame's background can be picked from: his, plus white.
    public static let backgroundPalette: [MarkColor] = [.darkGrey, .white, .scarlet, .vividYellow, .sage, .sand, .frost, .sapphire, .cream, .forest, .tiffany]

    /// The margin, in pixels, for a capture of `size`.
    public func inset(for size: CGSize) -> CGFloat {
        (padding * min(size.width, size.height)).rounded()
    }

    public func radius(for size: CGSize) -> CGFloat {
        cornerRadius * min(size.width, size.height)
    }

    /// The finished picture's size: the capture plus its margin on every side.
    public func outputSize(for size: CGSize) -> CGSize {
        let i = inset(for: size)
        return CGSize(width: size.width + i * 2, height: size.height + i * 2)
    }
}

extension Mark {
    /// The grab points a selected mark shows: one at each end of a segment,
    /// one at each corner of anything boxed. A label has none; its size is a
    /// setting, not a drag.
    public enum Handle: Hashable, Sendable { case a, b, bend, topLeft, topRight, bottomLeft, bottomRight }

    /// A segment's ends and its middle; a shape's corners; a label has none.
    public var handles: [(Handle, CGPoint)] {
        if kind.isSegment { return [(.a, a), (.bend, midpoint), (.b, b)] }
        if kind == .text { return [] }
        let r = rect
        return [(.topLeft, CGPoint(x: r.minX, y: r.minY)), (.topRight, CGPoint(x: r.maxX, y: r.minY)),
                (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)), (.bottomRight, CGPoint(x: r.maxX, y: r.maxY))]
    }

    /// This mark with one handle moved to `p`, the opposite corner held still.
    public func resized(_ handle: Handle, to p: CGPoint) -> Mark {
        var m = self
        let r = rect
        switch handle {
        case .a:           m.a = p
        case .b:           m.b = p
        case .bend:
            // Back near the straight middle, it snaps straight again.
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            m.bend = hypot(p.x - mid.x, p.y - mid.y) <= max(6, lineWidth * 1.5) ? nil : p
        case .topLeft:     m.a = p;                             m.b = CGPoint(x: r.maxX, y: r.maxY)
        case .topRight:    m.a = CGPoint(x: r.minX, y: p.y);    m.b = CGPoint(x: p.x, y: r.maxY)
        case .bottomLeft:  m.a = CGPoint(x: p.x, y: r.minY);    m.b = CGPoint(x: r.maxX, y: p.y)
        case .bottomRight: m.a = CGPoint(x: r.minX, y: r.minY); m.b = p
        }
        return m
    }
}

/// **What a press on the picture does — the one rule the editor follows.**
///
/// 1. A handle on the selected mark resizes it, in any tool: handles are only
///    shown on the selected mark, and what can be seen can be grabbed.
/// 2. A drawing tool draws. Always — including on top of another mark.
/// 3. Only Select picks a mark up, the topmost one under the pointer.
///
/// Rule 2 is the one that was missing. Drawing tools used to pick up any mark
/// they were pressed on, and a pixelation is a big rectangle, so nothing could
/// be started over one (Josh, 2026-09-16).
public enum EditorPress: Equatable, Sendable {
    case resize(UUID, Mark.Handle)
    case move(UUID)
    case draw
    case deselect

    public static func at(_ p: CGPoint, drawing: Bool, selected: Mark?, marks: [Mark],
                          reach: CGFloat) -> EditorPress {
        if let sel = selected,
           let handle = sel.handles.first(where: { hypot($0.1.x - p.x, $0.1.y - p.y) <= reach }) {
            return .resize(sel.id, handle.0)
        }
        if drawing { return .draw }
        if let hit = marks.last(where: { $0.hit(p, tolerance: reach) }) { return .move(hit.id) }
        return .deselect
    }
}

/// **The editor's engine.** Flattens a list of edits onto a capture, and writes
/// the result back over the file without disturbing what makes it *this*
/// capture — its name, its creation date (the day it was taken, which is what
/// the name and the day groups are built from), and its Finder tags.
///
/// It is the answer to the one thing Preview will not do: pixelate a region of
/// an image, so a key or an address can be hidden before a screenshot is sent
/// (the ScreenSnap Pro comparison, 2026-09-15).
public enum ImageEditor {

    // MARK: Render

    /// The one bitmap every render draws into: 8-bit sRGB with alpha.
    static func bitmap(width: Int, height: Int, bytesPerRow: Int = 0) -> CGContext? {
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// `source` with `draw` run over it in a top-down context whose origin is
    /// the picture's top-left — the frame every overlay here is drawn in.
    static func overlaying(_ source: CGImage, _ draw: (CGContext) -> Void) -> CGImage? {
        let w = source.width, h = source.height
        guard let ctx = bitmap(width: w, height: h) else { return nil }
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        draw(ctx)
        return ctx.makeImage()
    }

    /// Flatten `marks` onto `source`, in order. The same drawing the editor uses
    /// on screen, so the saved file is what was shown.
    public static func render(_ source: CGImage, marks: [Mark]) -> CGImage? {
        overlaying(source) { draw(marks, in: $0, source: source) }
    }

    /// The finished picture: `base` cut to `crop`, marks flattened onto it,
    /// scaled to `scale`, then set in its frame.
    ///
    /// Marks are in the base's own pixels, so a crop moves them by its origin
    /// and a scale shrinks them with the picture — which is what keeps both
    /// reversible: the base and the marks never change, only how they are cut
    /// and sized on the way out.
    public static func render(_ base: CGImage, marks: [Mark], crop: CGRect?, scale: CGFloat,
                              watermark: Watermark? = nil,
                              frame: FrameStyle) -> CGImage? {
        let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let cut = (crop.map { $0.standardized.integral.intersection(full) } ?? full)
        guard !cut.isEmpty else { return nil }
        var working = base
        var placed = marks
        if cut != full {
            guard let cropped = base.cropping(to: cut) else { return nil }
            working = cropped
            placed = marks.map { m in
                var s = m
                s.move(dx: -cut.minX, dy: -cut.minY)
                return s
            }
        }
        guard var annotated = placed.isEmpty ? working : render(working, marks: placed) else { return nil }
        if scale > 0, abs(scale - 1) > 0.001, let scaled = resized(annotated, by: scale) {
            annotated = scaled
        }
        // The watermark goes on the picture as it will be seen — after the
        // crop and the resize, before the frame — so it is never in the margin.
        if let watermark, !watermark.isEmpty, let stamped = stamped(annotated, with: watermark) {
            annotated = stamped
        }
        return render(annotated, marks: [], frame: frame)
    }

    /// The picture at another size, resampled well.
    public static func resized(_ image: CGImage, by factor: CGFloat) -> CGImage? {
        resized(image, to: CGSize(width: (CGFloat(image.width) * factor).rounded(),
                                  height: (CGFloat(image.height) * factor).rounded()))
    }

    public static func resized(_ image: CGImage, to size: CGSize) -> CGImage? {
        let w = max(1, Int(size.width)), h = max(1, Int(size.height))
        guard let ctx = bitmap(width: w, height: h) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// The finished picture: marks flattened onto `base`, then set in its frame.
    ///
    /// The frame is drawn in the bitmap's own upright coordinates, before
    /// anything is flipped, so the shadow falls downward without argument.
    public static func render(_ base: CGImage, marks: [Mark], frame: FrameStyle) -> CGImage? {
        guard let annotated = marks.isEmpty ? base : render(base, marks: marks) else { return nil }
        guard !frame.isPlain else { return annotated }
        let size = CGSize(width: base.width, height: base.height)
        let inset = frame.inset(for: size)
        let out = frame.outputSize(for: size)
        guard let ctx = bitmap(width: Int(out.width), height: Int(out.height)) else { return nil }
        let whole = CGRect(origin: .zero, size: out)
        drawBackground(frame.background, in: whole, ctx)

        let picture = CGRect(x: inset, y: inset, width: size.width, height: size.height)
        let shape = CGPath(roundedRect: picture, cornerWidth: frame.radius(for: size),
                           cornerHeight: frame.radius(for: size), transform: nil)
        drawShadow(of: shape, frame: frame, pictureSize: size, scale: 1, upright: true, ctx)
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.draw(annotated, in: picture)
        ctx.restoreGState()
        return ctx.makeImage()
    }

    /// The picture's shadow onto the margin, the one recipe for the file and
    /// the canvas: `scale` is view points per base pixel, `upright` whether
    /// the context's y runs up (a bitmap) or down (the canvas).
    public static func drawShadow(of shape: CGPath, frame: FrameStyle, pictureSize: CGSize, scale: CGFloat,
                                  upright: Bool, _ ctx: CGContext) {
        guard frame.shadow > 0, frame.padding > 0 else { return }
        let short = min(pictureSize.width, pictureSize.height) * scale
        let s = min(max(frame.shadow, 0), 1)
        let drop = short * 0.012 * (0.5 + s)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: upright ? -drop : drop),
                      blur: short * 0.03 * (0.5 + s * 1.5),
                      color: CGColor(gray: 0, alpha: 0.15 + 0.45 * s))
        ctx.addPath(shape)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// A frame's background, filling `rect`. Diagonal, light at the top left.
    /// `upright` says which way the context's y runs, as for `drawShadow`.
    public static func drawBackground(_ background: FrameStyle.Background, in rect: CGRect, _ ctx: CGContext,
                                      upright: Bool = true) {
        switch background.kind {
        case .none:
            break
        case .solid:
            ctx.setFillColor(background.first.cgColor)
            ctx.fill(rect)
        case .gradient:
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let g = CGGradient(colorsSpace: space,
                                     colors: [background.first.cgColor, background.second.cgColor] as CFArray,
                                     locations: [0, 1]) else { return }
            let (start, end) = gradientPoints(angle: background.angle, in: rect, upright: upright)
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.drawLinearGradient(g, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        case .image:
            guard let name = background.imageName, let image = BackgroundImages.load(name) else {
                // The picture is gone: a quiet neutral rather than a hole.
                ctx.setFillColor(MarkColor.frost.cgColor)
                ctx.fill(rect)
                return
            }
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.interpolationQuality = .high
            let fill = aspectFill(CGSize(width: image.width, height: image.height), in: rect)
            if upright { ctx.draw(image, in: fill) } else { drawUpright(image, in: fill, ctx) }
            ctx.restoreGState()
        }
    }

    /// The rect that fills `rect` with `size`'s proportions, centred, cropping
    /// whichever edge overflows.
    public static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let s = max(rect.width / size.width, rect.height / size.height)
        let w = size.width * s, h = size.height * s
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    /// Where a gradient at `angle` starts and ends across `rect`. 0° runs left
    /// to right; 90° top to bottom. `upright` is a bottom-left-origin context
    /// (the bitmap); the editor's canvas is top-down and passes false.
    public static func gradientPoints(angle: CGFloat, in rect: CGRect, upright: Bool) -> (CGPoint, CGPoint) {
        let a = angle * .pi / 180
        let dx = cos(a), dy = sin(a) * (upright ? -1 : 1)
        let half = (abs(dx) * rect.width + abs(dy) * rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        return (CGPoint(x: c.x - dx * half, y: c.y - dy * half), CGPoint(x: c.x + dx * half, y: c.y + dy * half))
    }

    /// Draw marks into a context whose coordinates are **image pixels with a
    /// top-left origin** — a flipped bitmap here, a SwiftUI canvas in the
    /// editor. `source` is what a pixelation samples; without it, pixelations
    /// are skipped (the editor bakes those into its base picture instead).
    public static func draw(_ marks: [Mark], in ctx: CGContext, source: CGImage?) {
        let bounds = source.map { CGRect(x: 0, y: 0, width: $0.width, height: $0.height) }
        for mark in marks {
            switch mark.kind {
            case .pixelate:
                guard let source, let bounds else { continue }
                let r = clamp(mark.rect, to: bounds)
                guard !r.isEmpty, let patch = pixelated(source, region: r) else { continue }
                drawUpright(patch, in: r, ctx)

            case .blackOut:
                // Opaque whatever the colour: this is a cover, never a tint.
                ctx.setFillColor(mark.color.cgColor.copy(alpha: 1) ?? CGColor(gray: 0.04, alpha: 1))
                ctx.fill(mark.rect.standardized)

            case .rectangle:
                let r = mark.rect
                guard r.width > 1, r.height > 1 else { continue }
                let radius = min(mark.lineWidth * 1.5, r.width / 2, r.height / 2)
                if mark.filled {
                    ctx.setFillColor(mark.color.cgColor)
                    ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
                    ctx.fillPath()
                } else {
                    let inset = r.insetBy(dx: mark.lineWidth / 2, dy: mark.lineWidth / 2)
                    guard inset.width > 0, inset.height > 0 else { continue }
                    ctx.setStrokeColor(mark.color.cgColor)
                    ctx.setLineWidth(mark.lineWidth)
                    ctx.addPath(CGPath(roundedRect: inset, cornerWidth: radius, cornerHeight: radius, transform: nil))
                    ctx.strokePath()
                }

            case .ellipse:
                let r = mark.rect
                guard r.width > 1, r.height > 1 else { continue }
                if mark.filled {
                    ctx.setFillColor(mark.color.cgColor)
                    ctx.fillEllipse(in: r)
                } else {
                    ctx.setStrokeColor(mark.color.cgColor)
                    ctx.setLineWidth(mark.lineWidth)
                    ctx.strokeEllipse(in: r.insetBy(dx: mark.lineWidth / 2, dy: mark.lineWidth / 2))
                }

            case .line:
                ctx.setStrokeColor(mark.color.cgColor)
                ctx.setLineWidth(mark.lineWidth)
                ctx.setLineCap(.round)
                ctx.move(to: mark.a)
                if let c = mark.control { ctx.addQuadCurve(to: mark.b, control: c) } else { ctx.addLine(to: mark.b) }
                ctx.strokePath()

            case .arrow:
                drawArrow(ctx, mark)

            case .highlight:
                // A plain translucent wash, not multiply. Multiply is how a
                // marker behaves on paper, and on a dark-mode screenshot it only
                // darkens — the highlight all but vanished (2026-09-16).
                ctx.setFillColor(MarkColor(red: mark.color.red, green: mark.color.green,
                                           blue: mark.color.blue, alpha: 0.38).cgColor)
                ctx.addPath(CGPath(roundedRect: mark.rect.standardized,
                                   cornerWidth: min(4, mark.rect.height / 4),
                                   cornerHeight: min(4, mark.rect.height / 4), transform: nil))
                ctx.fillPath()

            case .text:
                drawLabel(ctx, mark)

            case .step:
                drawBadge(ctx, mark)
            }
        }
    }

    // MARK: Steps

    /// A badge is about two lines of its number tall. For a pin, `a` is the
    /// tip and the badge hangs above it; for the others `a` is the centre.
    public static func badgeFrame(_ mark: Mark) -> CGRect {
        let d = mark.badgeDiameter
        switch mark.badge {
        case .bubble, .square:
            return CGRect(x: mark.a.x - d / 2, y: mark.a.y - d / 2, width: d, height: d)
        case .chevron:
            // A breadcrumb arrow: points right, `a` at its centre.
            return CGRect(x: mark.a.x - d * 0.8, y: mark.a.y - d / 2, width: d * 1.6, height: d)
        case .pin:
            return CGRect(x: mark.a.x - d / 2, y: mark.a.y - d * 1.45, width: d, height: d * 1.45)
        case .flag:
            // The pole stands on `a`; the pennant is a full badge wide.
            return CGRect(x: mark.a.x, y: mark.a.y - d * 1.5, width: d * 1.75, height: d * 1.5)
        }
    }

    private static func drawBadge(_ ctx: CGContext, _ mark: Mark) {
        let f = badgeFrame(mark)
        let d = mark.badgeDiameter
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: d * 0.06), blur: d * 0.12, color: CGColor(gray: 0, alpha: 0.28))
        ctx.setFillColor(mark.color.cgColor)
        var textCentre = CGPoint(x: f.midX, y: f.midY)
        switch mark.badge {
        case .bubble:
            ctx.fillEllipse(in: f)
        case .square:
            ctx.addPath(CGPath(roundedRect: f, cornerWidth: d * 0.22, cornerHeight: d * 0.22, transform: nil))
            ctx.fillPath()
        case .pin:
            // A circle with a point hanging from it, the tip at `a`.
            let circle = CGRect(x: f.minX, y: f.minY, width: d, height: d)
            let p = CGMutablePath()
            p.addArc(center: CGPoint(x: circle.midX, y: circle.midY), radius: d / 2,
                     startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: true)
            p.addLine(to: mark.a)
            p.closeSubpath()
            ctx.addPath(p)
            ctx.fillPath()
            textCentre = CGPoint(x: circle.midX, y: circle.midY)
        case .chevron:
            // A breadcrumb: a notch cut into the left end, a point on the right.
            let notch = f.height * 0.32
            let p = CGMutablePath()
            p.move(to: CGPoint(x: f.minX, y: f.minY))
            p.addLine(to: CGPoint(x: f.maxX - notch, y: f.minY))
            p.addLine(to: CGPoint(x: f.maxX, y: f.midY))
            p.addLine(to: CGPoint(x: f.maxX - notch, y: f.maxY))
            p.addLine(to: CGPoint(x: f.minX, y: f.maxY))
            p.addLine(to: CGPoint(x: f.minX + notch, y: f.midY))
            p.closeSubpath()
            ctx.addPath(p)
            ctx.fillPath()
            textCentre = CGPoint(x: f.midX + notch * 0.15, y: f.midY)
        case .flag:
            // A pole standing on `a`, a swallow-tailed pennant flying right, the
            // number in the pennant's body clear of the tail.
            let poleWidth = max(2.5, d * 0.11)
            let pole = CGRect(x: f.minX, y: f.minY, width: poleWidth, height: f.height)
            ctx.addPath(CGPath(roundedRect: pole, cornerWidth: poleWidth / 2, cornerHeight: poleWidth / 2, transform: nil))
            ctx.fillPath()
            let pennant = CGRect(x: f.minX + poleWidth, y: f.minY, width: f.width - poleWidth, height: d * 1.02)
            let tail = pennant.width * 0.2
            let p = CGMutablePath()
            p.move(to: CGPoint(x: pennant.minX, y: pennant.minY))
            p.addLine(to: CGPoint(x: pennant.maxX, y: pennant.minY))
            p.addLine(to: CGPoint(x: pennant.maxX - tail, y: pennant.midY))
            p.addLine(to: CGPoint(x: pennant.maxX, y: pennant.maxY))
            p.addLine(to: CGPoint(x: pennant.minX, y: pennant.maxY))
            p.closeSubpath()
            ctx.addPath(p)
            ctx.fillPath()
            textCentre = CGPoint(x: pennant.minX + (pennant.width - tail) / 2, y: pennant.midY)
        }
        ctx.restoreGState()

        // The number, centred, in type that reads on the colour.
        let ink = mark.color.ink
        let m = labelMetrics(String(mark.number), fontSize: mark.fontSize * 1.05, font: mark.font, color: ink)
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: textCentre.x - m.width / 2, y: textCentre.y + (m.ascent - m.descent) / 2)
        CTLineDraw(m.line, ctx)
        ctx.restoreGState()
    }

    /// Stroke and type that look the same on a 1x capture and a Retina one.
    public static func baseLineWidth(for size: CGSize) -> CGFloat {
        max(3, min(size.width, size.height) / 220).rounded()
    }

    public static func baseFontSize(for size: CGSize) -> CGFloat {
        max(16, min(size.width, size.height) / 34).rounded()
    }

    /// Where a label's pill sits. Shared by the drawing and the hit test, so
    /// what can be clicked is exactly what is drawn.
    public static func labelFrame(text: String, fontSize: CGFloat, font: TextFont = .system, at topLeft: CGPoint) -> CGRect {
        let m = labelMetrics(text.isEmpty ? " " : text, fontSize: fontSize, font: font)
        return CGRect(x: topLeft.x, y: topLeft.y,
                      width: m.width + m.padX * 2, height: m.ascent + m.descent + m.padY * 2)
    }

    private struct LabelMetrics {
        let line: CTLine, width: CGFloat, ascent: CGFloat, descent: CGFloat, padX: CGFloat, padY: CGFloat
    }

    private static func labelMetrics(_ text: String, fontSize: CGFloat, font face: TextFont = .system,
                                     color: CGColor? = nil) -> LabelMetrics {
        let font = face.font(size: fontSize)
        var attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        if let color { attrs[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        return LabelMetrics(line: line, width: width, ascent: ascent, descent: descent,
                            padX: fontSize * 0.5, padY: fontSize * 0.28)
    }

    private static func drawLabel(_ ctx: CGContext, _ mark: Mark) {
        guard !mark.text.isEmpty else { return }
        let m = labelMetrics(mark.text, fontSize: mark.fontSize, font: mark.font, color: mark.color.ink)
        let box = CGRect(x: mark.a.x, y: mark.a.y, width: m.width + m.padX * 2, height: m.ascent + m.descent + m.padY * 2)
        ctx.setFillColor(mark.color.cgColor)
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: mark.fontSize * 0.45,
                           cornerHeight: mark.fontSize * 0.45, transform: nil))
        ctx.fillPath()
        ctx.saveGState()
        // The context runs top-down; type is drawn bottom-up, so flip it back.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: box.minX + m.padX, y: box.minY + m.padY + m.ascent)
        CTLineDraw(m.line, ctx)
        ctx.restoreGState()
    }

    /// A `CGImage` right way up in a top-down context.
    static func drawUpright(_ image: CGImage, in rect: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    private static func clamp(_ r: CGRect, to bounds: CGRect) -> CGRect {
        r.standardized.integral.intersection(bounds)
    }

    /// The block size a region gets. Public so the editor's live preview and
    /// the flattened file agree to the pixel.
    public static func blockSize(for region: CGRect) -> CGFloat {
        max(8, min(region.width, region.height) / 5).rounded()
    }

    /// How far each tile reaches for its shade: three tiles across, centred.
    public static func sampleSpan(for region: CGRect) -> CGFloat {
        blockSize(for: region) * 3
    }

    /// Every tile becomes the average of a **wide** area centred on it.
    ///
    /// Not `CIPixellate`, which samples one point per tile: on a screenshot —
    /// mostly background, thin strokes of type — nearly every sample lands on
    /// background, so a redacted line came out as flat empty space with a
    /// stray square in it (2026-09-16). And not a plain per-tile average once
    /// the tiles got finer, because a small tile's own average can still hold
    /// a glyph's outline. The span is sampled on a grid of at most 48 by 48,
    /// which bounds the cost for a whole-screen region without narrowing it.
    private static func pixelated(_ source: CGImage, region: CGRect) -> CGImage? {
        guard let crop = source.cropping(to: region.integral) else { return nil }
        let w = crop.width, h = crop.height
        guard let read = bitmap(width: w, height: h, bytesPerRow: w * 4),
              let write = bitmap(width: w, height: h, bytesPerRow: w * 4),
              let src = read.data, let dst = write.data else { return nil }
        read.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        let from = src.assumingMemoryBound(to: UInt8.self)
        let to = dst.assumingMemoryBound(to: UInt8.self)
        let block = max(1, Int(blockSize(for: region)))
        let reach = max(block, Int(sampleSpan(for: region))) / 2

        var top = 0
        while top < h {
            let rows = min(block, h - top)
            let cy = top + rows / 2
            let y0 = max(0, cy - reach), y1 = min(h - 1, cy + reach)
            let yStep = max(1, (y1 - y0 + 1) / 48)
            var left = 0
            while left < w {
                let cols = min(block, w - left)
                let cx = left + cols / 2
                let x0 = max(0, cx - reach), x1 = min(w - 1, cx + reach)
                let xStep = max(1, (x1 - x0 + 1) / 48)
                var r = 0, g = 0, b = 0, a = 0, n = 0
                var y = y0
                while y <= y1 {
                    var x = x0
                    while x <= x1 {
                        let i = (y * w + x) * 4
                        r += Int(from[i]); g += Int(from[i + 1]); b += Int(from[i + 2]); a += Int(from[i + 3])
                        n += 1
                        x += xStep
                    }
                    y += yStep
                }
                let avg = (UInt8(r / n), UInt8(g / n), UInt8(b / n), UInt8(a / n))
                for yy in top..<(top + rows) {
                    var i = (yy * w + left) * 4
                    for _ in 0..<cols {
                        to[i] = avg.0; to[i + 1] = avg.1; to[i + 2] = avg.2; to[i + 3] = avg.3
                        i += 4
                    }
                }
                left += block
            }
            top += block
        }
        return write.makeImage()
    }

    /// Straight or bent. The head follows the curve's direction at the tip.
    private static func drawArrow(_ ctx: CGContext, _ mark: Mark) {
        let from = mark.a, to = mark.b, width = mark.lineWidth, color = mark.color.cgColor
        let length = mark.length
        guard length > width * 2 else { return }
        let toward = mark.control ?? from
        let angle = atan2(to.y - toward.y, to.x - toward.x)
        let head = max(width * 4.5, 12)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.move(to: from)
        // The shaft stops short of the tip, so the head is not blunted by it.
        if let c = mark.control {
            let t = max(0, 1 - head * 0.6 / length)
            let c1 = CGPoint(x: from.x + (c.x - from.x) * t, y: from.y + (c.y - from.y) * t)
            ctx.addQuadCurve(to: Mark.quadPoint(from, c, to, t), control: c1)
        } else {
            ctx.addLine(to: CGPoint(x: to.x - cos(angle) * head * 0.6, y: to.y - sin(angle) * head * 0.6))
        }
        ctx.strokePath()
        let spread: CGFloat = .pi / 7
        ctx.setFillColor(color)
        ctx.move(to: to)
        ctx.addLine(to: CGPoint(x: to.x - cos(angle - spread) * head, y: to.y - sin(angle - spread) * head))
        ctx.addLine(to: CGPoint(x: to.x - cos(angle + spread) * head, y: to.y - sin(angle + spread) * head))
        ctx.closePath()
        ctx.fillPath()
    }

    // MARK: Load and save

    public static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// Write `image` over `url` as a PNG, keeping the file's identity.
    ///
    /// - **The name** does not change, so the index entry, the watcher's list
    ///   of files it has already seen, and every link to it stay valid.
    /// - **The creation date** is the day the shot was taken. It drives the
    ///   name and the day headings, so an edit must not move a capture to today.
    /// - **Finder tags** are the filing. A plain atomic write replaces the file
    ///   and takes its extended attributes with it, so this swaps content with
    ///   `replaceItemAt`, which keeps the original's metadata — and checks.
    /// - **The modification date** does move: the file *was* changed, and
    ///   QuickLook keys its thumbnails on it, so leaving it would show the
    ///   unredacted picture in the grid.
    /// A PNG at `url`, nothing else — the writer `save` and the edit store share.
    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    public static func save(_ image: CGImage, over url: URL, fileManager: FileManager = .default) throws {
        let tags = Tagging.finderTags(of: url)
        let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate

        let scratch = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                          appropriateFor: url, create: true)
        defer { try? fileManager.removeItem(at: scratch) }
        let edited = scratch.appendingPathComponent(url.lastPathComponent)
        try writePNG(image, to: edited)

        _ = try fileManager.replaceItemAt(url, withItemAt: edited)

        if !tags.isEmpty, Set(Tagging.finderTags(of: url)) != Set(tags) { Tagging.add(tags, to: url) }
        var values = URLResourceValues()
        if let created { values.creationDate = created }
        values.contentModificationDate = Date()
        var target = url
        try? target.setResourceValues(values)
    }
}
