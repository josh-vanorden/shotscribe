import Foundation

/// **The words in a shot, findable in Spotlight at once.**
///
/// ShotScribe's own index knows the text inside every capture; Spotlight only
/// learns it hours to days later, when Apple's image-text pass gets round to
/// the file. Writing the significant words as `kMDItemKeywords` — a metadata
/// attribute Spotlight indexes the moment the file is touched — makes a plain
/// Spotlight query for `accounting` find the org chart within seconds
/// (measured 2026-09-22: five seconds; Apple's own text pass still empty).
///
/// **Off by default, on purpose.** Metadata travels with the file on AirDrop
/// and in an archive, so words from the screen — including any later covered
/// in the editor — would ride along with a shared copy. The switch says so.
/// The word list is distilled, not the whole text: the title's words, the
/// tags, then the distinct significant words of the OCR, capped.
public enum Spotlight {
    public static let attribute = "com.apple.metadata:kMDItemKeywords"
    public static let limit = 60

    /// The distilled list: title words and tags first, then the OCR's distinct
    /// words that are not noise — three letters or more, letters and digits,
    /// not a stopword — in order of first appearance, capped at `limit`.
    public static func keywords(title: String, tags: [String], text: String, limit: Int = limit) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        func take(_ word: String) {
            let w = word.lowercased()
            guard w.count >= 3, w.count <= 40, w.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }),
                  !stopwords.contains(w), seen.insert(w).inserted, out.count < limit else { return }
            out.append(w)
        }
        for word in title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) { take(String(word)) }
        for tag in tags { take(tag.trimmingCharacters(in: .whitespaces)) }
        for word in text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "_" }) {
            take(String(word).trimmingCharacters(in: CharacterSet(charactersIn: "-_")))
        }
        return out
    }

    /// Write the list as the file's Spotlight keywords. Never fatal.
    @discardableResult
    public static func write(_ keywords: [String], to url: URL) -> Bool {
        guard !keywords.isEmpty,
              let data = try? PropertyListSerialization.data(fromPropertyList: keywords, format: .binary, options: 0)
        else { return false }
        return Xattr.write(data, attribute, at: url.path)
    }

    public static func read(_ url: URL) -> [String] {
        guard let data = Xattr.read(attribute, at: url.path, limit: 64 * 1024),
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String] else { return [] }
        return list
    }

    public static func remove(from url: URL) {
        Xattr.remove(attribute, at: url.path)
    }

    /// Words that say nothing about what a shot showed.
    static let stopwords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "any", "can", "had", "her", "was", "one", "our",
        "out", "day", "get", "has", "him", "his", "how", "man", "new", "now", "old", "see", "two", "way", "who",
        "did", "its", "let", "put", "say", "she", "too", "use", "with", "this", "that", "from", "have", "your",
        "will", "more", "when", "what", "were", "they", "been", "than", "then", "them", "into", "some", "such",
        "only", "also", "here", "there", "which", "their", "about", "would", "could", "should", "these", "those",
        "each", "other", "after", "before", "over", "under", "just", "like", "very", "much", "many", "most",
        "does", "done", "make", "made", "back", "well", "where", "while", "click", "page", "view", "open", "close",
        "file", "edit", "help", "window", "menu", "search", "screenshot", "screen", "image", "png",
    ]
}

extension ShotScribeDefaults {
    public static let spotlightKeywordsKey = "shotscribe.spotlightKeywords"

    /// Off unless switched on: the words travel with the file.
    public static func spotlightKeywords() -> Bool { suite.bool(forKey: spotlightKeywordsKey) }
    public static func setSpotlightKeywords(_ on: Bool) { suite.set(on, forKey: spotlightKeywordsKey) }
}
