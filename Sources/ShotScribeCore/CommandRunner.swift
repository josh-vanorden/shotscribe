import Foundation
import Darwin  // kill(2) / SIGKILL for the watchdog escalation

/// Runs one command to completion and hands back both streams — the one
/// process runner every CLI titler shares, so the three load-bearing details
/// live in one place: `/dev/null` on stdin (else some CLIs stall waiting for
/// it), both pipes drained concurrently (reading only stdout while the child
/// writes >64KB to stderr deadlocks both sides), and a SIGTERM→SIGKILL
/// watchdog. Ported from Navi's `ClaudeCLIClient` via `ClaudeTitler`.
enum CommandRunner {
    struct Result: Sendable {
        let out: String
        let err: String
        let status: Int32
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> Result {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: executable)
                proc.arguments = arguments

                var env = ProcessInfo.processInfo.environment
                let extra = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin"
                env["PATH"] = env["PATH"].map { "\($0):\(extra)" } ?? extra
                proc.environment = env

                proc.standardInput = FileHandle.nullDevice
                let outPipe = Pipe(); proc.standardOutput = outPipe
                let errPipe = Pipe(); proc.standardError = errPipe

                do { try proc.run() } catch { cont.resume(throwing: error); return }

                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard proc.isRunning else { return }
                    proc.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                        if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
                    }
                }

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

                let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let err = String(data: errBox.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                cont.resume(returning: Result(out: out, err: err, status: proc.terminationStatus))
            }
        }
    }
}

/// Reference box so the background stderr-drain closure hands its result back
/// without mutating a captured `var`. The `DispatchGroup.wait()` before the
/// read establishes the happens-before.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Where a CLI lives, found once per name: the usual install spots first, then
/// the login shell's `command -v`, so a tool on a PATH only the shell knows
/// about is still found from an app that inherited none of it.
public enum Executables {
    private static let lock = NSLock()
    private static var cache: [String: String?] = [:]

    public static func resolve(_ name: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[name] { return hit }
        let found = compute(name)
        cache[name] = found
        return found
    }

    /// A bare command name: letters, digits, `._+-`. Anything else — a space,
    /// a `;`, a `$(` — is not a name, and is refused before it can reach the
    /// shell below. (The user types the template, so this is belt-and-braces
    /// against a pasted setting, not against the user.)
    static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "._+-".unicodeScalars.contains($0) }
    }

    private static func compute(_ name: String) -> String? {
        let fm = FileManager.default
        if name.contains("/") {
            // A path is checked as a path, never handed to a shell.
            let path = (name as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: path) ? path : nil
        }
        guard isPlainName(name) else { return nil }
        let home = NSHomeDirectory()
        var candidates = ["\(home)/.local/bin/\(name)", "/opt/homebrew/bin/\(name)",
                          "/usr/local/bin/\(name)", "/usr/bin/\(name)", "/bin/\(name)"]
        if name == "claude" { candidates.insert("\(home)/.claude/local/claude", at: 1) }
        for c in candidates where fm.isExecutableFile(atPath: c) { return c }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v \(name)"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let s, !s.isEmpty, fm.isExecutableFile(atPath: s) else { return nil }
        return s
    }
}
