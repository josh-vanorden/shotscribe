import Foundation

/// Tags for a capture, written where macOS already looks for them.
///
/// A tag goes on the file as a **Finder tag**, so it shows in Finder, sorts in
/// the sidebar and answers a Spotlight search without ShotScribe running or any
/// surface of its own. That is the whole reason tags are worth doing before a
/// pane exists: the operating system is the UI.
///
/// **Tags come from a fixed list, never from the model's imagination.** The OCR
/// text is whatever was on screen — possibly a page written to manipulate
/// whatever reads it — so a proposed tag is kept only when it is already in the
/// vocabulary. That keeps a screenshot from inventing its own filing, and keeps
/// the tag list from sprawling into hundreds of one-offs.
public enum Tagging {

    /// Shipped vocabulary. Deliberately short, general, and about *what kind of
    /// thing the shot is* — not about its subject, which the title already
    /// carries. Made editable when there is a pane to edit it in.
    public static let defaultVocabulary = [
        "terminal", "code", "error", "browser", "docs", "chat", "email",
        "calendar", "design", "dashboard", "settings", "logs", "ticket",
        "meeting", "diagram", "receipt",
    ]

    /// How many tags one capture may carry. More than a couple stops being a
    /// filing system and starts being noise.
    public static let maxPerShot = 2

    /// The proposals that survive: matched case-insensitively against the
    /// vocabulary, returned in the vocabulary's own spelling, de-duplicated,
    /// capped. Anything not on the list is dropped without comment.
    public static func accepted(_ proposed: [String],
                                vocabulary: [String] = defaultVocabulary) -> [String] {
        let known = Dictionary(vocabulary.map { ($0.lowercased(), $0) },
                               uniquingKeysWith: { first, _ in first })
        var kept: [String] = []
        for raw in proposed {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let canonical = known[key], !kept.contains(canonical) else { continue }
            kept.append(canonical)
            if kept.count == maxPerShot { break }
        }
        return kept
    }

    // MARK: - Finder tags

    /// The Finder tags already on a file.
    public static func finderTags(of url: URL) -> [String] {
        (try? url.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
    }

    /// Add tags to a file, keeping whatever it already carries. Setting
    /// `tagNames` replaces the lot, so anything the user filed by hand has to be
    /// merged back in or it would be silently thrown away.
    @discardableResult
    public static func add(_ tags: [String], to url: URL) -> Bool {
        let existing = finderTags(of: url)
        let merged = existing + tags.filter { new in
            !existing.contains { $0.caseInsensitiveCompare(new) == .orderedSame }
        }
        guard merged != existing else { return true }
        do {
            // `URLResourceValues.tagNames`' setter is macOS 26+, and this package
            // floors at 13. The NSURL key has been writable since 10.9.
            try (url as NSURL).setResourceValue(merged as NSArray, forKey: .tagNamesKey)
            return true
        } catch {
            return false   // a tag is a nicety; never fail a rename over one
        }
    }
}

/// What a titler makes of a screenshot: the name, and the filing.
public struct Labelling: Equatable, Sendable {
    public var title: String
    public var tags: [String]

    public init(title: String, tags: [String] = []) {
        self.title = title
        self.tags = tags
    }
}
