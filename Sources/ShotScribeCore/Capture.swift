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
