import Foundation
import Darwin  // kill(2) / SIGKILL for the watchdog escalation

/// Titles a screenshot by shelling out to the local **Claude Code CLI**
/// (`claude -p`) — no API key, billed to the user's Claude subscription.
///
/// The call is **sandboxed**: no MCP servers, and every built-in exec/write/
/// read/exfil tool is denied. The prompt carries text scraped off the user's
/// screen (possibly sensitive, possibly attacker-controlled if they screenshot
/// a malicious page), so the model is given nothing it could be tricked into
/// driving.
///
/// Ported from Navi's `ClaudeCLIClient`; the `/dev/null` stdin (avoids a ~3s
/// per-call stall) and the concurrent stderr drain (avoids a >64KB pipe
/// deadlock) are load-bearing, not incidental.
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

    // MARK: - Binary resolution (memoized)

    private static let binaryHolder = ResolvedValue()
    private static func resolveBinary() -> String? { binaryHolder.get { computeBinary() } }

    private static func computeBinary() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        if let resolved = shellWhich(), FileManager.default.isExecutableFile(atPath: resolved) { return resolved }
        return nil
    }

    private static func shellWhich() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v claude"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }

    /// Built-in tools denied on the completion — this is a pure text helper and
    /// the prompt routinely carries untrusted on-screen text, so a prompt-
    /// injection payload has nothing to execute. Paired with `--strict-mcp-config`.
    private static let deniedTools =
        "Bash,BashOutput,KillShell,Task,Agent,Read,Write,Edit,NotebookEdit,WebFetch,WebSearch,Glob,Grep"

    private func complete(prompt: String, system: String) async throws -> String {
        guard let bin = Self.resolveBinary() else { throw CLIError.notFound }
        let timeout = self.timeout
        let model = self.model
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: bin)
                var args = ["-p", prompt, "--output-format", "text"]
                if let model, !model.isEmpty { args += ["--model", model] }
                if !system.isEmpty { args += ["--append-system-prompt", system] }
                args += ["--strict-mcp-config", "--disallowedTools", Self.deniedTools]
                proc.arguments = args

                var env = ProcessInfo.processInfo.environment
                let extra = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin"
                env["PATH"] = env["PATH"].map { "\($0):\(extra)" } ?? extra
                proc.environment = env

                // No stdin to read (prompt is via -p) — feed /dev/null so claude
                // doesn't block ~3s waiting on stdin before every call.
                proc.standardInput = FileHandle.nullDevice
                let outPipe = Pipe(); proc.standardOutput = outPipe
                let errPipe = Pipe(); proc.standardError = errPipe

                do { try proc.run() } catch { cont.resume(throwing: error); return }

                // Watchdog: SIGTERM at the deadline, SIGKILL if it clings on.
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard proc.isRunning else { return }
                    proc.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                        if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
                    }
                }

                // Drain both pipes concurrently — reading only stdout while the
                // child writes >64KB to stderr deadlocks both sides.
                let errGroup = DispatchGroup()
                let errBox = DataBox()
                errGroup.enter()
                DispatchQueue.global().async {
                    errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    errGroup.leave()
                }
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                errGroup.wait()

                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if proc.terminationStatus == 0 && !text.isEmpty {
                    cont.resume(returning: text)
                } else {
                    // The reason can be on EITHER stream. Reading only stderr
                    // discarded the one message that explains the failure: the
                    // CLI reports "Failed to authenticate: OAuth session
                    // expired" on stdout with exit 1, so every expired session
                    // surfaced as the useless `.empty` and the app looked
                    // broken rather than logged out.
                    let err = String(data: errBox.data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let reason = err.isEmpty ? text : err
                    cont.resume(throwing: reason.isEmpty
                                ? CLIError.empty
                                : CLIError.failed(String(reason.prefix(200))))
                }
            }
        }
    }
}

/// Reference box so the background stderr-drain closure hands its result back
/// without mutating a captured `var` (which strict concurrency rejects). The
/// `DispatchGroup.wait()` before the read establishes the happens-before.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Thread-safe one-shot memoizer for the resolved CLI path.
private final class ResolvedValue: @unchecked Sendable {
    private let lock = NSLock()
    private var computed = false
    private var value: String?
    func get(_ compute: () -> String?) -> String? {
        lock.lock(); defer { lock.unlock() }
        if !computed { value = compute(); computed = true }
        return value
    }
}
