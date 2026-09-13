import Foundation

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

    /// The line for a given assistant.
    public static func line(forImageAt path: String, kind: AIProvider.Kind) -> String {
        kind == .claude || kind.assistant == "Claude" ? line(forImageAt: path) : plainLine(forImageAt: path)
    }

    private static func quoted(_ path: String) -> String {
        path.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
