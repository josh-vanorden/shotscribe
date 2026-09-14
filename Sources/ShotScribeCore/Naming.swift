import Foundation
import Darwin  // getxattr(2) for the capture flag

/// Turns a label + capture time into a findable filename, and decides which
/// files are safe to rename.
///
/// Date FIRST so name-sort stays chronological, then the label for scanning
/// and search — the tail (what truncating UIs keep) is the meaningful part.
public enum Naming {
    /// Is this file still wearing the name macOS gave it as a capture? ONLY
    /// these are renamed — a file the user named themselves is never touched.
    ///
    /// The English names ("Screenshot …", the older "Screen Shot …") match on
    /// the name alone, as they always have. Every other language, and a custom
    /// `com.apple.screencapture name`, needs two signals: a name shaped like
    /// macOS's default AND macOS's own capture flag on the file. The flag alone
    /// is not enough — it survives renames, so it is on every shot ShotScribe
    /// has already named and on every capture the user renamed themselves.
    public static func isRawCapture(at url: URL) -> Bool {
        let name = url.lastPathComponent
        if hasEnglishCapturePrefix(name) { return true }
        return hasDefaultCaptureShape(name) && isFlaggedAsCapture(url)
    }

    /// Name only, for a name with no file behind it (a history row's "from"):
    /// does it look like a macOS default capture name, in any language?
    public static func looksLikeDefaultCaptureName(_ filename: String) -> Bool {
        hasEnglishCapturePrefix(filename) || hasDefaultCaptureShape(filename)
    }

    /// Stills and recordings alike: macOS writes "Screen Recording 2026-09-12
    /// at 3.41.07 PM.mov" into the same folder, in the same shape.
    static func hasEnglishCapturePrefix(_ filename: String) -> Bool {
        let lower = filename.lowercased()
        return lower.hasPrefix("screenshot ") || lower.hasPrefix("screen shot ")
            || lower.hasPrefix("screen recording ")
    }

    /// macOS's default capture name in any language: a word or two, the ISO
    /// date, then the time with dots for colons (a Finder name cannot hold
    /// ":"), maybe an AM/PM marker, maybe a duplicate counter —
    /// "Bildschirmfoto 2026-08-11 um 15.41.07", "截屏2026-08-11 下午3.41.07",
    /// "Screenshot 2026-08-11 at 3.41.07 PM (2)". ShotScribe's own names start
    /// with the date and carry no seconds, so they never match. The marker is
    /// held to one or two letters a part ("PM", "p. m.") so a name the user
    /// extended ("… 15.41.07 Anna") stops matching.
    static func hasDefaultCaptureShape(_ filename: String) -> Bool {
        let stem = (filename as NSString).deletingPathExtension
        let range = NSRange(stem.startIndex..., in: stem)
        return defaultCaptureShape.firstMatch(in: stem, range: range) != nil
    }

    private static let defaultCaptureShape = try! NSRegularExpression(pattern:
        #"^\D.*\d{4}-\d{2}-\d{2}.*\d{1,2}\.\d{2}\.\d{2}(?:\s?\p{L}{1,2}(?:\.\s?\p{L}{1,2})?\.?)?(?:\s\(?\d{1,3}\)?)?$"#)

    /// macOS stamps every capture with this extended attribute (a binary-plist
    /// `true`), whatever the language or name setting, and it rides along
    /// through renames. Read straight off the file — no Spotlight involved.
    static let captureFlag = "com.apple.metadata:kMDItemIsScreenCapture"

    static func isFlaggedAsCapture(_ url: URL) -> Bool {
        let size = getxattr(url.path, captureFlag, nil, 0, 0, 0)
        guard size > 0 else { return false }
        var bytes = [UInt8](repeating: 0, count: size)
        guard getxattr(url.path, captureFlag, &bytes, size, 0, 0) == size else { return false }
        let value = try? PropertyListSerialization.propertyList(from: Data(bytes), format: nil)
        return (value as? Bool) ?? false
    }

    /// A name with its title swapped and everything else kept as spelled: the
    /// stamp the template put around it stays, so an edit in the window never
    /// re-renders yesterday's date. `name` carries no extension, as
    /// `IndexedShot.name` does. The title takes the template's joining style but
    /// not its word cap — someone who typed six words meant six. nil when the
    /// title sanitises to nothing.
    public static func retitled(_ name: String, to title: String, style: NameTemplate.TitleStyle = .asIs) -> String? {
        let words = sanitize(title).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }
        let clean: String
        switch style {
        case .asIs:  clean = words.joined(separator: " ")
        case .kebab: clean = words.joined(separator: "-").lowercased()
        case .snake: clean = words.joined(separator: "_").lowercased()
        }
        let stem = Sessions.stem(of: name)
        guard stem != name, let range = name.range(of: stem) else { return clean }
        return name.replacingCharacters(in: range, with: clean)
    }

    /// Strip characters that break paths or read badly, collapse spaces, cap length.
    /// Control and invisible-format characters (Cc, Cf) count as illegal: a title
    /// comes from a model that read whatever was on screen, and a bidi override
    /// (U+202E) or a terminal escape in a filename lies about what the name says.
    public static func sanitize(_ label: String, maxChars: Int = 60) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\t").union(.controlCharacters)
        let cleaned = label.components(separatedBy: illegal).joined(separator: " ")
        // A word that is only dots ("..", ".") survives the character strip and
        // reads as a path component; it carries no meaning in a title either.
        let collapsed = cleaned.split(separator: " ")
            .filter { $0.contains { $0 != "." } }
            .joined(separator: " ")
        return String(collapsed.prefix(maxChars)).trimmingCharacters(in: .whitespaces)
    }

    /// "2026-08-11 1541 AWS Billing Console.png" under the default template —
    /// sortable, scannable. nil when the template asks for a title and there is
    /// no usable one, so the caller leaves the file alone.
    public static func filename(label: String, app: String? = nil, capturedAt: Date, ext: String,
                                template: NameTemplate = .default) -> String? {
        let title = renderedTitle(label, template)
        if template.layout.contains("{title}") && title.isEmpty { return nil }
        var stem = template.layout
        stem = stem.replacingOccurrences(of: "{date}", with: stamp(capturedAt, template.dateStyle.format))
        stem = stem.replacingOccurrences(of: "{time}", with: stamp(capturedAt, template.timeStyle.format))
        stem = stem.replacingOccurrences(of: "{title}", with: title)
        // No app read off the chrome leaves the slot empty; `tidy` closes the gap.
        stem = stem.replacingOccurrences(of: "{app}", with: app.map { sanitize($0, maxChars: 30) } ?? "")
        stem = tidy(stem)
        guard !stem.isEmpty else { return nil }
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    /// The title as the template spells it: cut to `titleWords`, restyled, and
    /// capped. Styling happens after the cut so a word is never half-kebabed.
    static func renderedTitle(_ label: String, _ template: NameTemplate) -> String {
        let words = sanitize(label, maxChars: .max).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return "" }
        let kept = words.prefix(max(1, template.titleWords))
        let joined: String
        switch template.titleStyle {
        case .asIs:  joined = kept.joined(separator: " ")
        case .kebab: joined = kept.joined(separator: "-").lowercased()
        case .snake: joined = kept.joined(separator: "_").lowercased()
        }
        return String(joined.prefix(max(1, template.maxTitleChars)))
            .trimmingCharacters(in: CharacterSet(charactersIn: " -_"))
    }

    /// A rendered name, tidied: nothing a path cannot hold, no double spaces,
    /// and no separator left dangling where a token rendered empty.
    static func tidy(_ stem: String) -> String {
        sanitize(stem, maxChars: .max)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -_"))
    }

    private static func stamp(_ date: Date, _ format: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = format
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }

    // MARK: - Judging a template

    /// What a settings pane shows under the field, and what `validate` judges.
    public static func sampleFilename(_ template: NameTemplate) -> String? {
        filename(label: sampleLabel, app: "Safari", capturedAt: sampleDate, ext: "png", template: template)
    }

    static let sampleLabel = "AWS Billing Console"
    static let sampleDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 11; c.hour = 15; c.minute = 41
        return Calendar.current.date(from: c) ?? Date(timeIntervalSince1970: 1_786_000_000)
    }()

    /// nil when the template is usable. Checked before it is saved, never at
    /// rename time — a rename must not be the thing that discovers a bad name.
    public static func validate(_ template: NameTemplate) -> TemplateProblem? {
        let braced = tokenPattern
            .matches(in: template.layout, range: NSRange(template.layout.startIndex..., in: template.layout))
            .compactMap { Range($0.range, in: template.layout).map { String(template.layout[$0]) } }
        if let unknown = braced.first(where: { !NameTemplate.tokens.contains($0) }) {
            return .unknownToken(unknown)
        }
        guard NameTemplate.tokens.contains(where: { template.layout.contains($0) }) else {
            return .noTokens
        }
        let illegal = template.layout.filter { "/\\:*?\"<>|".contains($0) }
        if !illegal.isEmpty {
            return .illegalCharacters(illegal.map(String.init).joined(separator: " "))
        }
        guard let sample = sampleFilename(template), !sample.isEmpty else { return .rendersEmpty }
        // The idempotency guard: a template that spells a name macOS would give
        // a fresh capture turns the watcher loose on ShotScribe's own output.
        if looksLikeDefaultCaptureName(sample) { return .looksLikeACapture }
        return nil
    }

    private static let tokenPattern = try! NSRegularExpression(pattern: #"\{[^}]*\}"#)

    /// Resolve a collision by suffixing " (2)", " (3)", … Pure: the caller
    /// supplies the existence check so this stays testable.
    public static func uniqueName(_ desired: String, exists: (String) -> Bool) -> String {
        guard exists(desired) else { return desired }
        let url = URL(fileURLWithPath: desired)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        for n in 2...99 {
            let candidate = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            if !exists(candidate) { return candidate }
        }
        return desired
    }
}
