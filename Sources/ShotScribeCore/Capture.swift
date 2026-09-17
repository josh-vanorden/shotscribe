import Foundation

/// What lands in a screenshot folder. macOS writes stills and screen
/// recordings to the same place, so the watcher, the index, the MCP door and
/// the panel read one list here rather than four of their own that drift.
public enum Capture {
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "tiff", "heic", "bmp"]
    /// `Screen Recording … .mov` is what macOS writes; `mp4` for a re-export.
    public static let movieExtensions: Set<String> = ["mov", "mp4"]
    public static var extensions: Set<String> { imageExtensions.union(movieExtensions) }

    public static func isCapture(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }
    public static func isMovie(_ url: URL) -> Bool { movieExtensions.contains(url.pathExtension.lowercased()) }
}

extension Capture {
    /// When a capture was taken, as well as the file can say: its creation
    /// date, else its modification date. nil when it says nothing.
    public static func takenAt(_ url: URL) -> Date? {
        let v = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return v?.creationDate ?? v?.contentModificationDate
    }
}
