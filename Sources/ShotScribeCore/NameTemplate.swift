import Foundation

/// How a renamed capture is spelled: the layout holds the tokens and whatever
/// literal text sits between them, and the styles decide what each token
/// renders as. Separators are part of the layout — `{date}_{time}_{title}` —
/// so there is no separate separator setting.
///
/// `NameTemplate.default` reproduces the only format ShotScribe ever shipped,
/// which is the point: the repo is public, and an upgrade must not rename
/// anybody's captures differently than yesterday.
public struct NameTemplate: Codable, Equatable, Sendable {

    /// 2026-08-11 · 08-11-2026 · 20260811
    public enum DateStyle: String, Codable, CaseIterable, Sendable {
        case iso, us, compact

        var format: String {
            switch self {
            case .iso:     return "yyyy-MM-dd"
            case .us:      return "MM-dd-yyyy"
            case .compact: return "yyyyMMdd"
            }
        }
    }

    /// 1541 · 15-41 · 3.41 PM
    public enum TimeStyle: String, Codable, CaseIterable, Sendable {
        case hhmm, dashed, twelveHour

        var format: String {
            switch self {
            case .hhmm:       return "HHmm"
            case .dashed:     return "HH-mm"
            case .twelveHour: return "h.mm a"
            }
        }
    }

    /// AWS Billing Console · aws-billing-console · aws_billing_console
    public enum TitleStyle: String, Codable, CaseIterable, Sendable {
        case asIs, kebab, snake
    }

    /// Tokens plus literal text, e.g. "{date} {time} {title}".
    public var layout: String
    public var dateStyle: DateStyle
    public var timeStyle: TimeStyle
    public var titleStyle: TitleStyle
    /// How many words of the title to keep (1–3). A longer summary than that
    /// needs `TitlerPrompt` to ask for one, so it is not a template setting.
    public var titleWords: Int
    /// Cap on the title alone, not the whole name — the stamp is fixed-width.
    public var maxTitleChars: Int

    public init(layout: String = "{date} {time} {title}",
                dateStyle: DateStyle = .iso,
                timeStyle: TimeStyle = .hhmm,
                titleStyle: TitleStyle = .asIs,
                titleWords: Int = 3,
                maxTitleChars: Int = 60) {
        self.layout = layout
        self.dateStyle = dateStyle
        self.timeStyle = timeStyle
        self.titleStyle = titleStyle
        self.titleWords = titleWords
        self.maxTitleChars = maxTitleChars
    }

    /// Today's format, exactly: "2026-08-11 1541 AWS Billing Console.png".
    public static let `default` = NameTemplate()

    /// Every token a layout may use. `{app}` is deliberately absent: a capture
    /// records its type and screen rect, never the app it came from.
    public static let tokens = ["{date}", "{time}", "{title}"]

    /// Decoded field by field so that adding a setting later leaves a stored
    /// template loadable. The synthesised decoder would throw on the missing
    /// key, and the caller's `try?` would silently reset somebody's naming.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NameTemplate.default
        layout = try c.decodeIfPresent(String.self, forKey: .layout) ?? d.layout
        dateStyle = try c.decodeIfPresent(DateStyle.self, forKey: .dateStyle) ?? d.dateStyle
        timeStyle = try c.decodeIfPresent(TimeStyle.self, forKey: .timeStyle) ?? d.timeStyle
        titleStyle = try c.decodeIfPresent(TitleStyle.self, forKey: .titleStyle) ?? d.titleStyle
        titleWords = try c.decodeIfPresent(Int.self, forKey: .titleWords) ?? d.titleWords
        maxTitleChars = try c.decodeIfPresent(Int.self, forKey: .maxTitleChars) ?? d.maxTitleChars
    }
}

/// Why a template cannot be used. Held apart from the rendering so a settings
/// pane can say what is wrong before it saves anything.
public enum TemplateProblem: Equatable, Sendable {
    case noTokens
    case unknownToken(String)
    case illegalCharacters(String)
    case rendersEmpty
    case looksLikeACapture

    public var why: String {
        switch self {
        case .noTokens:
            return "Add at least one of \(NameTemplate.tokens.joined(separator: " ")) — without one, every capture would get the same name."
        case .unknownToken(let t):
            return "\(t) is not a token. Use \(NameTemplate.tokens.joined(separator: " "))."
        case .illegalCharacters(let chars):
            return "A filename cannot contain \(chars)."
        case .rendersEmpty:
            return "This template produces an empty name."
        case .looksLikeACapture:
            return "This produces a name macOS uses for a fresh capture, so ShotScribe would rename its own output."
        }
    }
}
