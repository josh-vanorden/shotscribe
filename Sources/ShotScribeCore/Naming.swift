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

    static func hasEnglishCapturePrefix(_ filename: String) -> Bool {
        let lower = filename.lowercased()
        return lower.hasPrefix("screenshot ") || lower.hasPrefix("screen shot ")
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

    /// Strip characters that break paths or read badly, collapse spaces, cap length.
    public static func sanitize(_ label: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\t")
        let cleaned = label.components(separatedBy: illegal).joined(separator: " ")
        let collapsed = cleaned.split(separator: " ").joined(separator: " ")
        return String(collapsed.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    /// "2026-08-11 1541 AWS Billing Console.png" — sortable, scannable.
    /// nil when there's no usable label, so the caller leaves the file alone.
    public static func filename(label: String, capturedAt: Date, ext: String) -> String? {
        let clean = sanitize(label)
        guard !clean.isEmpty else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HHmm"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let stamp = fmt.string(from: capturedAt)
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        return "\(stamp) \(clean)\(suffix)"
    }

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
