import Foundation

/// A shot handed to a Claude Code session. Nothing can push into a running
/// session, so the hand-off is one line on the pasteboard that the
/// `/screenshot` skill takes as an argument: pasted anywhere Claude Code is
/// listening, the skill reads this shot rather than the newest one. The app's
/// "Send to Claude" copies exactly this; `SendToClaudeTests` holds the skill
/// and the app to the same spelling.
public enum SendToClaude {

    /// `/screenshot "<path>"` — quoted, since capture names carry spaces.
    public static func line(forImageAt path: String) -> String {
        "/screenshot \"\(path.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
