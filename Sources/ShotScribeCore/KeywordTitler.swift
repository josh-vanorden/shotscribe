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
        Labelling(title: try await title(forOCRText: text), tags: tags(in: text, vocabulary: vocabulary))
    }

    /// With the positions: the headline, when the picture has one, is the
    /// title. The first eval (2026-09-23) put the keyword titler at 8% exact
    /// against kept names, with misses like "Chief Director Contracto" and
    /// "Goal Agent Max" — frequent words, never the one line set in big type
    /// at the top that a person would read as the title. That line is what
    /// this reads first; the keywords remain for a picture of one size of text.
    public func labelling(for lines: [OCR.TextLine], vocabulary: [String]) async throws -> Labelling {
        let text = OCR.text(of: lines)
        let title: String
        if let headline = Self.headline(in: lines) {
            title = LabelCleaner.clean(Self.titleCased(headline))
        } else {
            title = try await self.title(forOCRText: text)
        }
        return Labelling(title: title, tags: tags(in: text, vocabulary: vocabulary))
    }

    private func tags(in text: String, vocabulary: [String]) -> [String] {
        guard !vocabulary.isEmpty else { return [] }
        let words = Set(text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init))
        let present = vocabulary.filter { words.contains($0.lowercased()) }
        return Tagging.accepted(present, vocabulary: vocabulary)
    }

    /// The biggest type in the upper part of the picture, when it is clearly
    /// bigger than the rest: a slide's title, a dialog's heading, a page's
    /// h1. nil for a picture of one size of text — a terminal, a chat, a
    /// table — where the keywords are the better guess.
    static func headline(in lines: [OCR.TextLine]) -> String? {
        let candidates = lines.filter { line in
            let words = line.text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            let letters = line.text.filter(\.isLetter).count
            return line.top < 60 && letters >= 4 && (1...8).contains(words.count)
                && !words.allSatisfy { $0.allSatisfy(\.isNumber) }
        }
        guard let tallest = candidates.max(by: { $0.height < $1.height }) else { return nil }
        // The rest of the same row in the same type — a headline Vision read
        // as two boxes — and, apart from it, everything else on the page.
        let sameRow = { (line: OCR.TextLine) in abs(line.box.midY - tallest.box.midY) <= tallest.box.height / 2 }
        let rest = lines.filter { !sameRow($0) }.map(\.height).sorted()
        // Clearly bigger than the rest of the page, or it is not a headline;
        // a page of two lines has no "rest" to speak of and keeps its bigger one.
        if rest.count >= 2 {
            let median = rest[rest.count / 2]
            guard tallest.height >= median * 1.5 else { return nil }
        }
        let row = lines
            .filter { sameRow($0) && $0.height >= tallest.height * 0.8 && $0.text.contains(where: \.isLetter) }
            .sorted { $0.box.minX < $1.box.minX }
        let joined = row.map(\.text).joined(separator: " ")
        return joined.isEmpty ? tallest.text : joined
    }

    /// A headline as a title: each word capitalised, a short all-caps word
    /// kept as the acronym it is (MDM, AWS, IT), a bare mark dropped (&, —),
    /// and a number the headline *starts* with dropped too — "4 Tool Design"
    /// is a numbered slide, and the number is the deck's, not the title's.
    /// A number elsewhere stays: "Roadmap 2026" is what it says.
    static func titleCased(_ headline: String) -> String {
        var words = headline.split(whereSeparator: \.isWhitespace).map(String.init)
        while let first = words.first, first.allSatisfy(\.isNumber) { words.removeFirst() }
        return words.compactMap { word -> String? in
            guard word.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
            if word.count <= 3, word == word.uppercased(), word.contains(where: \.isLetter) { return word }
            return word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    public func title(forOCRText text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= TitlerPrompt.minOCRChars else { return LabelCleaner.generic }

        // Tokenize to alphanumeric words, keep order of first appearance while
        // counting frequency.
        var counts: [String: Int] = [:]
        var order: [String] = []
        for rawWord in trimmed.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let w = String(rawWord)
            guard w.count >= 3, w.count <= 18, !Self.stopwords.contains(w),
                  !(w.allSatisfy { $0.isNumber }), !Self.isOCRNoise(w) else { continue }
            if counts[w] == nil { order.append(w) }
            counts[w, default: 0] += 1
        }
        guard !order.isEmpty else { return LabelCleaner.generic }

        // Rank by frequency, tie-broken by first appearance (stable).
        let ranked = order.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        let picked = ranked.prefix(3).map { $0.capitalized }
        return LabelCleaner.clean(picked.joined(separator: " "))
    }

    /// "Progr8Ss", "Compl8Ted", "Softwarelm3Dcbp": a digit wedged between two
    /// letters is fast OCR misreading a glyph, never a word anyone would file
    /// under. Digits at either end stay — "ec2", "3d", "iphone15" are real.
    /// Surfaced by the first `shotscribe eval` run, 2026-09-12: a fortnight of
    /// names like these had been kept while Claude was signed out.
    static func isOCRNoise(_ w: String) -> Bool {
        let chars = Array(w)
        guard chars.count >= 3 else { return false }
        for i in 1..<(chars.count - 1) where chars[i].isNumber {
            if chars[i - 1].isLetter && chars[i + 1].isLetter { return true }
        }
        return false
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
