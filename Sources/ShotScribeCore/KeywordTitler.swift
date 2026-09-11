import Foundation

/// Offline fallback: no network, no Claude. Picks the most salient words from
/// the OCR text by frequency, skipping stopwords and noise, and Title-Cases up
/// to three of them. Good enough to beat eight identical timestamps; keeps the
/// tool useful to anyone who doesn't have Claude Code installed.
public struct KeywordTitler: Titler {
    public init() {}

    /// Offline tagging: a vocabulary word that appears in the shot's own text,
    /// whole, counts. No cleverness — but it means `--no-claude` files things
    /// too, and a tag it proposes can always be pointed at in the text.
    public func labelling(forOCRText text: String, vocabulary: [String]) async throws -> Labelling {
        let title = try await title(forOCRText: text)
        guard !vocabulary.isEmpty else { return Labelling(title: title) }
        let words = Set(text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init))
        let present = vocabulary.filter { words.contains($0.lowercased()) }
        return Labelling(title: title, tags: Tagging.accepted(present, vocabulary: vocabulary))
    }

    public func title(forOCRText text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= TitlerPrompt.minOCRChars else { return "Screenshot" }

        // Tokenize to alphanumeric words, keep order of first appearance while
        // counting frequency.
        var counts: [String: Int] = [:]
        var order: [String] = []
        for rawWord in trimmed.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let w = String(rawWord)
            guard w.count >= 3, w.count <= 18, !Self.stopwords.contains(w),
                  !(w.allSatisfy { $0.isNumber }) else { continue }
            if counts[w] == nil { order.append(w) }
            counts[w, default: 0] += 1
        }
        guard !order.isEmpty else { return "Screenshot" }

        // Rank by frequency, tie-broken by first appearance (stable).
        let ranked = order.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        let picked = ranked.prefix(3).map { $0.capitalized }
        return LabelCleaner.clean(picked.joined(separator: " "))
    }

    /// Small, boring English stoplist — enough to keep "the login page" from
    /// becoming "The Login". Intentionally not exhaustive.
    private static let stopwords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "any", "can",
        "her", "was", "one", "our", "out", "has", "have", "his", "how", "man",
        "new", "now", "old", "see", "two", "way", "who", "did", "get", "let",
        "put", "say", "she", "too", "use", "with", "from", "this", "that",
        "your", "into", "then", "than", "them", "they", "will", "your", "here",
        "when", "what", "which", "there", "about", "click", "press", "enter",
        "http", "https", "www", "com", "org", "net",
    ]
}
