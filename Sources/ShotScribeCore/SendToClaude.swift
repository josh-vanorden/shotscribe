import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// A shot handed to an assistant's session. Nothing can push into a running
/// session, so the hand-off is one line on the pasteboard. For Claude Code
/// that line is the `/screenshot` skill's path form, which reads this shot
/// rather than the newest; for any other assistant it is a plain instruction
/// that works in any chat. The app's "Send to …" copies exactly this;
/// `SendToClaudeTests` holds the skill and the app to the same spelling.
public enum SendToClaude {

    /// `/screenshot "<path>"` — quoted, since capture names carry spaces.
    public static func line(forImageAt path: String) -> String {
        "/screenshot \"\(quoted(path))\""
    }

    /// The same ask for an assistant that has no `/screenshot`.
    public static func plainLine(forImageAt path: String) -> String {
        "Look at the screenshot at \"\(quoted(path))\" and address it in the context of what I am working on. "
        + "If its name is still a raw capture name, rename it with a 2-3 word title, date first."
    }

    /// The line for a given titler: the skill's form for Claude Code, where
    /// `/screenshot` lives; the plain ask for everything else.
    public static func line(forImageAt path: String, kind: AIProvider.Kind) -> String {
        kind == .claude ? line(forImageAt: path) : plainLine(forImageAt: path)
    }

    /// **The shot itself, for a chat that cannot see this Mac.** A path is a
    /// meaning only to a process on this disk; claude.ai and the Claude app run
    /// their chats in a container that has never seen it, so the `/screenshot`
    /// line arrives there as a question about a file that does not exist
    /// (Josh, 2026-09-22: "nothing arrived"). This puts the picture on the
    /// pasteboard as PNG data — what a web composer attaches on ⌘V — with the
    /// file's URL for apps that take files, and the file's *name* as the text
    /// fallback, never its path. nil for anything that is not a still.
    public static func picture(forImageAt url: URL) -> NSPasteboardItem? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let png = NSMutableData()
        guard let sink = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(sink, image, nil)
        guard CGImageDestinationFinalize(sink) else { return nil }
        let item = NSPasteboardItem()
        item.setData(png as Data, forType: .png)
        item.setString(url.absoluteString, forType: .fileURL)
        item.setString(url.lastPathComponent, forType: .string)
        return item
    }

    private static func quoted(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
