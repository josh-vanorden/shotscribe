import Foundation

/// Titles a screenshot by shelling out to the local **Claude Code CLI**
/// (`claude -p`) — no API key, billed to the user's Claude subscription.
///
/// The call is **sandboxed**: no MCP servers, and every built-in exec/write/
/// read/exfil tool is denied. The prompt carries text scraped off the user's
/// screen (possibly sensitive, possibly attacker-controlled if they screenshot
/// a malicious page), so the model is given nothing it could be tricked into
/// driving.
///
/// The process handling lives in `CommandRunner`, shared with every other CLI
/// titler; what is Claude-specific here is the argument list and the errors.
public struct ClaudeTitler: Titler {
    public enum CLIError: LocalizedError {
        case notFound, empty, failed(String)
        public var errorDescription: String? {
            switch self {
            case .notFound: return "The Claude CLI (`claude`) isn't installed."
            case .empty:    return "The Claude CLI returned nothing."
            case .failed(let m):
                // An expired session is the common case and has a specific fix,
                // so it gets a specific sentence rather than a raw CLI line.
                if m.localizedCaseInsensitiveContains("authenticate")
                    || m.localizedCaseInsensitiveContains("oauth")
                    || m.localizedCaseInsensitiveContains("expired") {
                    return "Claude is signed out — run `claude` in a terminal to sign in again."
                }
                return "Claude CLI: \(m)"
            }
        }
    }

    public var timeout: TimeInterval
    public var model: String?

    /// - Parameters:
    ///   - timeout: seconds before the watchdog terminates a hung run.
    ///   - model: optional `--model` override (e.g. a fast model for latency).
    public init(timeout: TimeInterval = 30, model: String? = nil) {
        self.timeout = timeout
        self.model = model
    }

    /// True when the `claude` binary resolves — lets callers pick a fallback.
    public static func isAvailable() -> Bool { resolveBinary() != nil }

    public func title(forOCRText text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= TitlerPrompt.minOCRChars else { return "Screenshot" }
        let raw = try await complete(
            prompt: "OCR text:\n\(trimmed)\n\nLabel:",
            system: TitlerPrompt.system
        )
        return LabelCleaner.clean(raw)
    }

    /// Title and tags from the one call. An empty vocabulary means the caller
    /// wants no tags, and the prompt goes back to asking for a label alone.
    public func labelling(forOCRText text: String, vocabulary: [String]) async throws -> Labelling {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= TitlerPrompt.minOCRChars else { return Labelling(title: "Screenshot") }
        guard !vocabulary.isEmpty else { return Labelling(title: try await title(forOCRText: trimmed)) }
        let raw = try await complete(
            prompt: "OCR text:\n\(trimmed)\n\nLabel:",
            system: TitlerPrompt.system(taggedFrom: vocabulary)
        )
        return Self.parseLabelling(raw, vocabulary: vocabulary)
    }

    /// "AWS Billing Console | dashboard, browser" → the name and the filing. A
    /// reply with no "|" is taken as all label, which is what a literal-minded
    /// model gives back.
    static func parseLabelling(_ raw: String, vocabulary: [String]) -> Labelling {
        let line = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
        let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let proposed = parts.count > 1 ? parts[1].split(separator: ",").map(String.init) : []
        return Labelling(title: LabelCleaner.clean(String(parts.first ?? "")),
                         tags: Tagging.accepted(proposed, vocabulary: vocabulary))
    }

    private static func resolveBinary() -> String? { Executables.resolve("claude") }

    /// Built-in tools denied on the completion — this is a pure text helper and
    /// the prompt routinely carries untrusted on-screen text, so a prompt-
    /// injection payload has nothing to execute. Paired with `--strict-mcp-config`.
    private static let deniedTools =
        "Bash,BashOutput,KillShell,Task,Agent,Read,Write,Edit,NotebookEdit,WebFetch,WebSearch,Glob,Grep"

    private func complete(prompt: String, system: String) async throws -> String {
        guard let bin = Self.resolveBinary() else { throw CLIError.notFound }
        var args = ["-p", prompt, "--output-format", "text"]
        if let model, !model.isEmpty { args += ["--model", model] }
        if !system.isEmpty { args += ["--append-system-prompt", system] }
        args += ["--strict-mcp-config", "--disallowedTools", Self.deniedTools]
        let run = try await CommandRunner.run(bin, args, timeout: timeout)
        if run.status == 0 && !run.out.isEmpty { return run.out }
        // The reason can be on EITHER stream: the CLI reports "Failed to
        // authenticate: OAuth session expired" on stdout with exit 1, so
        // reading only stderr made every expired session look like `.empty`.
        // Printable before it is thrown: this string reaches the terminal, the
        // panel and the log, and the CLI's streams are not trusted with them.
        let reason = CommandRunner.printable(String((run.err.isEmpty ? run.out : run.err).prefix(200)))
            .trimmingCharacters(in: .whitespaces)
        throw reason.isEmpty ? CLIError.empty : CLIError.failed(reason)
    }
}
