import Foundation

/// The swappable seam. Given the OCR text pulled off a screenshot, produce a
/// short human title. Implementations: `ClaudeTitler` (local `claude -p`),
/// `KeywordTitler` (offline). A future MCP server satisfies this same shape
/// from the other direction — Claude calling *in* rather than the tool calling
/// *out*.
public protocol Titler: Sendable {
    func title(forOCRText text: String) async throws -> String

    /// The title, plus whatever tags this titler can propose — in one pass, so
    /// tagging never costs a second model call.
    ///
    /// A protocol *requirement* with a default below, not an extension method
    /// alone: callers hold a `Titler` existential, and an extension-only method
    /// dispatches statically, so every implementation's override would be
    /// skipped and nothing would ever be tagged.
    func labelling(forOCRText text: String, vocabulary: [String]) async throws -> Labelling

    /// The same, from the lines as read, with where they sit. A titler that
    /// can use the positions — the offline one reads the headline off the
    /// biggest type — overrides this; the rest get the joined text. A
    /// requirement with a default, for the reason above.
    func labelling(for lines: [OCR.TextLine], vocabulary: [String]) async throws -> Labelling
}

public extension Titler {
    /// The default proposes no tags, so a titler with no notion of them needs
    /// no change.
    func labelling(forOCRText text: String, vocabulary: [String]) async throws -> Labelling {
        Labelling(title: try await title(forOCRText: text))
    }

    func labelling(for lines: [OCR.TextLine], vocabulary: [String]) async throws -> Labelling {
        try await labelling(forOCRText: OCR.text(of: lines), vocabulary: vocabulary)
    }
}

public enum TitlerPrompt {
    /// The rules that make the same screen get the same label twice. Written
    /// after the first eval (2026-09-23): seven of its 25 misses were the
    /// model choosing between its own synonyms for one screen — "Slide" one
    /// day and "Diagram" the next, "Onboarding Docs" then "Knowledge Base".
    /// Words that are on the screen do not drift; words the model supplies do.
    static let rules = """
    Prefer the words the screen uses for itself — its heading, page, document, \
    dialog or app name — over your own; when the screen names nothing, say what \
    it shows in plain words. Name the subject, what the screen is about, rather \
    than the app it is in or a person on it. Name what it is, not what kind of \
    picture it is: no Slide, Screenshot, Diagram, Screen, Page, View or Window \
    unless that word is on the screen, and no slide or page number. Same screen, \
    same label: the plainest reading wins.
    """

    /// Shared instruction so every titler asks for the same shape of answer.
    public static let system = """
    You label a screenshot from its OCR text. Reply with ONLY a 2-3 word Title \
    Case label naming what it shows — e.g. "AWS Billing Console", "Xcode Build \
    Error", "Slack Channel Rename", "Terminal Output", "Figma Canvas". \(rules) \
    No punctuation, no quotes, max 3 words. If unclear, reply "Screenshot".
    """

    /// Below this many characters of OCR text, don't even bother a model — it's
    /// an image-only shot; the caller uses the generic fallback.
    public static let minOCRChars = 4

    /// The same job, asking for the filing too. The list is closed: OCR text is
    /// untrusted, `Tagging.accepted` drops anything off-list anyway, and naming
    /// the list keeps the model from spending the slot on something invented.
    public static func system(taggedFrom vocabulary: [String]) -> String {
        guard !vocabulary.isEmpty else { return system }
        return """
        You label a screenshot from its OCR text. Reply with ONE line and nothing \
        else: a 2-3 word Title Case label naming what it shows, then " | ", then up \
        to \(Tagging.maxPerShot) tags from this list, comma separated — \
        \(vocabulary.joined(separator: ", ")). For example: "AWS Billing Console | \
        dashboard, browser". \(rules) No punctuation in the label, no quotes, max 3 \
        words. Use only tags from that list, and leave the part after "|" empty when \
        none fit. If the shot is unclear, reply "Screenshot |".
        """
    }
}
