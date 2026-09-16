import Foundation
import CoreText
import AppKit

/// **The face a label, a step number or a watermark is set in.**
///
/// The system face is what every label has been so far and stays the default.
/// The three other designs are the system family's own — rounded, serif,
/// monospaced — and `family` is any face installed on the Mac, for when the
/// picture has to carry a company's look (Josh, 2026-09-16: "if this becomes
/// company image we'll need a bit of customization"). Everything is drawn
/// bold: a label on a screenshot is a caption, not a paragraph.
public enum TextFont: Hashable, Sendable, Codable {
    case system, rounded, serif, mono
    case family(String)

    public static let designs: [TextFont] = [.system, .rounded, .serif, .mono]

    public var name: String {
        switch self {
        case .system:         return "System"
        case .rounded:        return "Rounded"
        case .serif:          return "Serif"
        case .mono:           return "Mono"
        case .family(let f):  return f
        }
    }

    /// One string, so it can sit in a mark or in defaults: `system`, `serif`…
    /// or `family:Avenir Next`.
    public var stored: String {
        if case .family(let f) = self { return "family:\(f)" }
        return name.lowercased()
    }

    public init(stored: String) {
        switch stored {
        case "rounded": self = .rounded
        case "serif":   self = .serif
        case "mono":    self = .mono
        case let s where s.hasPrefix("family:") && s.count > 7: self = .family(String(s.dropFirst(7)))
        default:        self = .system
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(stored: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(stored)
    }

    /// Every family installed, without the system's private ones.
    public static func installedFamilies() -> [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The bold face at `size`. A family that is no longer installed falls back
    /// to the system face rather than to whatever CoreText substitutes.
    public func font(size: CGFloat) -> CTFont {
        switch self {
        case .system:
            return Self.systemFont(size)
        case .rounded, .serif, .mono:
            let design: NSFontDescriptor.SystemDesign = self == .rounded ? .rounded : self == .serif ? .serif : .monospaced
            let base = NSFont.systemFont(ofSize: size, weight: .bold)
            guard let descriptor = base.fontDescriptor.withDesign(design),
                  let font = NSFont(descriptor: descriptor, size: size) else { return Self.systemFont(size) }
            return font as CTFont
        case .family(let family):
            let traits: [CFString: Any] = [kCTFontSymbolicTrait: CTFontSymbolicTraits.boldTrait.rawValue]
            let attributes: [CFString: Any] = [kCTFontFamilyNameAttribute: family, kCTFontTraitsAttribute: traits]
            let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
            let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
            let got = CTFontCopyFamilyName(font) as String
            guard got.caseInsensitiveCompare(family) == .orderedSame else { return Self.systemFont(size) }
            return font
        }
    }

    /// Whether `font(size:)` will honour this choice on this Mac.
    public var isInstalled: Bool {
        guard case .family(let family) = self else { return true }
        return (CTFontCopyFamilyName(font(size: 12)) as String).caseInsensitiveCompare(family) == .orderedSame
    }

    private static func systemFont(_ size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }
}
