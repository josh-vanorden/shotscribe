import Foundation
import ShotScribeCore

// shotscribe — CLI front end over ShotScribeCore.
//
//   shotscribe label  [--no-claude] <file>
//   shotscribe rename [--no-claude] [--dry-run] [--force] <file>
//   shotscribe watch  [--no-claude] [dir]
//
// Zero third-party dependencies — argument parsing is deliberately tiny.

/// The titler is the AI tab's choice, read from the same settings the app
/// writes. `--offline` (or the older `--no-claude`) forces keywords.
func makeTitler(noClaude: Bool) -> Titler {
    if noClaude { return KeywordTitler() }
    let provider = ShotScribeDefaults.aiProvider()
    let availability = provider.availability()
    if let titler = provider.makeTitler(), availability.isReady { return titler }
    if provider.kind != .offline {
        FileHandle.standardError.write(Data(
            "note: \(provider.kind.name): \(availability.text) Using the offline keyword titler.\n".utf8))
    }
    return KeywordTitler()
}

/// Names and snippets reach the terminal from the filesystem and the index —
/// other software's file names can carry escapes. Strip Cc and Cf at print.
func safe(_ s: String) -> String {
    String(String.UnicodeScalarView(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
}

func expand(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
}

func describe(_ outcome: RenameOutcome) -> String {
    switch outcome {
    case .renamed(let from, let to):
        let tags = Tagging.finderTags(of: to)
        let filed = tags.isEmpty ? "" : "\n   tags  \(tags.joined(separator: ", "))"
        return "renamed  \(safe(from.lastPathComponent))\n      →  \(safe(to.lastPathComponent))\(filed)"
    case .wouldRename(let from, let to):
        return "would rename  \(safe(from.lastPathComponent))\n           →  \(safe(to.lastPathComponent))"
    case .skippedNotRawCapture(let url):
        return "skipped (not a macOS capture; use --force): \(safe(url.lastPathComponent))"
    case .skippedNotACapture(let url):
        return "skipped (not an image or a recording; ShotScribe only names captures): \(safe(url.lastPathComponent))"
    case .skippedNoLabel(let url):
        return "skipped (no usable label): \(url.lastPathComponent)"
    case .fileMissing(let url):
        return "error: file not found: \(url.path)"
    }
}

let usage = """
shotscribe — name screenshots so you can find them again.

USAGE:
  shotscribe label  [--no-claude] <file>            Print the title (no rename)
  shotscribe rename [--no-claude] [--dry-run] [--force] <file>
  shotscribe watch  [--no-claude] [dir]             Rename new captures as they land
  shotscribe index  [--force] [dir]                 Read every screenshot into the search index
  shotscribe find   <query>                         Search what your screenshots SAY, not just
                                                    what they are called
  shotscribe name                                   Show the name template renames use
  shotscribe ai                                     Show who titles, as the AI tab set it
  shotscribe eval   [--no-claude] [--limit N] [dir]  Score the titler against names you kept

FLAGS:
  --offline     Use the offline keyword titler instead of the AI tab's choice
                (`--no-claude` still works and means the same)
  --no-tags     Don't file the shot under Finder tags
  --dry-run     Show the new name without moving the file
  --force       Rename even files you named yourself (default: macOS captures only)
                For `index`: re-read files already indexed

The index lives at ~/.shotscribe/index.json and never leaves this machine. It is
more sensitive than the screenshots themselves — text caught in passing is
greppable there in a way it is not inside a PNG.
"""

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print(usage); exit(0)
}
args.removeFirst()

let noClaude = args.contains("--no-claude") || args.contains("--offline")
let noTags   = args.contains("--no-tags")
let dryRun   = args.contains("--dry-run")
let force    = args.contains("--force")
var limit = 25
if let i = args.firstIndex(of: "--limit"), i + 1 < args.count, let n = Int(args[i + 1]) {
    limit = n
    args.removeSubrange(i...(i + 1))
}
let positional = args.filter { !$0.hasPrefix("--") }

let titler = makeTitler(noClaude: noClaude)
var renamer = Renamer(titler: titler,
                      template: ShotScribeDefaults.nameTemplate(),
                      vocabulary: (noTags || !ShotScribeDefaults.taggingEnabled()) ? [] : ShotScribeDefaults.vocabulary())
// A failing assistant is said out loud, and the offline titler names the shot.
renamer.onTitlerError = { error in
    let who = noClaude ? "the offline titler" : ShotScribeDefaults.aiProvider().kind.name
    FileHandle.standardError.write(Data(
        "note: \(who) failed — \(error.localizedDescription) Used the offline title.\n".utf8))
}

switch command {
case "label":
    guard let file = positional.first else {
        FileHandle.standardError.write(Data("error: `label` needs a file path.\n".utf8)); exit(2)
    }
    let proposed = await renamer.labelling(fileAt: expand(file))
    print(proposed.title)
    if !proposed.tags.isEmpty { print("tags: \(proposed.tags.joined(separator: ", "))") }

case "rename":
    guard let file = positional.first else {
        FileHandle.standardError.write(Data("error: `rename` needs a file path.\n".utf8)); exit(2)
    }
    do {
        let outcome = try await renamer.rename(fileAt: expand(file), force: force, dryRun: dryRun)
        print(describe(outcome))
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8)); exit(1)
    }

case "watch":
    let dir = positional.first.map(expand) ?? FolderWatcher.defaultScreenshotDirectory()
    let watcher = FolderWatcher(directory: dir) { url in
        Task {
            do {
                let outcome = try await renamer.rename(fileAt: url, force: force, dryRun: dryRun)
                print(describe(outcome))
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            }
        }
    }
    // Arm first, retry second. `start()` seeds `seen` from everything already
    // in the folder, so a capture that lands while the retry is still running
    // would be seeded as already seen and then silently never renamed: not by
    // the retry, which has no record for it, and not by the watcher, which
    // thinks it was always there. Measured 2026-09-20 with the retry held open
    // by 40 in-flight records: a capture dropped 50ms in was still sitting
    // under its raw name at the end. Arming first costs nothing, because the
    // in-flight captures are on disk under raw names at this moment too, so
    // they are seeded as seen and the watcher will not race the retry for them.
    guard watcher.start() else {
        FileHandle.standardError.write(Data("error: can't watch \(dir.path)\n".utf8)); exit(1)
    }
    print("shotscribe: watching \(dir.path)  (Ctrl-C to stop)")
    // Inside a Task, never behind a top-level `await`: `main.swift` is
    // top-level code, and a bare `await` here would be the first genuine
    // suspension on the `watch` path, which hands control to the run loop that
    // the trailing `dispatchMain()` then re-enters and traps on (SIGTRAP in
    // `dispatch_main`, measured 2026-09-20). Inside a Task the top-level code
    // never suspends and falls through to `dispatchMain()` as it always did.
    Task {
        for outcome in await Backlog.retryInFlight(in: dir, renamer: renamer) {
            print(describe(outcome))
        }
    }
    dispatchMain()   // run forever

case "index":
    let force = args.contains("--force")
    args.removeAll { $0 == "--force" }
    let dir = positional.first.map(expand) ?? FolderWatcher.defaultScreenshotDirectory()
    print("reading \(dir.path)")
    let r = ShotIndex.reindex(folder: dir, force: force) { i, n in
        if i % 10 == 0 || i == n {
            FileHandle.standardError.write(Data("  \(i)/\(n)\r".utf8))
        }
    }
    FileHandle.standardError.write(Data("\n".utf8))
    print("indexed \(r.indexed) · already current \(r.skipped) · pruned \(r.pruned)")
    print("index: \(ShotIndex.indexURL.path)")

case "find":
    let query = positional.joined(separator: " ")
    if query.isEmpty {
        FileHandle.standardError.write(Data("error: find needs something to look for\n".utf8))
        exit(1)
    }
    let hits = ShotIndex.search(query)
    guard !hits.isEmpty else {
        print("nothing matched \"\(query)\". If the shots predate the index, run: shotscribe index")
        exit(0)
    }
    let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
    for h in hits.prefix(20) {
        let mark = h.matchedInName ? "*" : " "
        let tags = h.shot.tags ?? []
        let filed = tags.isEmpty ? "" : "  [\(tags.joined(separator: "] ["))]"
        print("\(mark) \(fmt.string(from: h.shot.captured))  \(safe(h.shot.name))\(filed)")
        if !h.snippet.isEmpty { print("     \(safe(h.snippet))") }
        print("     \(safe(h.shot.path))")
    }
    if hits.count > 20 { print("… and \(hits.count - 20) more") }

case "eval":
    // The folder is the set: every capture that is already named is a judged
    // answer, and its Finder tags a judged filing. Raw captures are skipped.
    let dir = positional.first.map(expand) ?? FolderWatcher.defaultScreenshotDirectory()
    let cases = Array(Evals.cases(in: dir).suffix(limit))   // newest names sort last
    guard !cases.isEmpty else {
        print("no named captures in \(dir.path) to judge against"); exit(0)
    }
    let which = noClaude ? "offline titler" : ShotScribeDefaults.aiProvider().kind.name
    print("judging \(cases.count) named capture\(cases.count == 1 ? "" : "s") in \(dir.lastPathComponent) with the \(which)")
    var scores: [Evals.Score] = []
    var failures: [String] = []   // a titler that cannot run is not a titler that named badly
    for (i, c) in cases.enumerated() {
        FileHandle.standardError.write(Data("  \(i + 1)/\(cases.count)\r".utf8))
        let ocr = OCR.recognizeText(atPath: c.url.path)
        let got: Labelling
        do { got = try await titler.labelling(forOCRText: ocr, vocabulary: renamer.vocabulary) }
        catch { failures.append(error.localizedDescription); got = Labelling(title: LabelCleaner.generic) }
        let s = Evals.score(got, against: c)
        scores.append(s)
        let mark = s.exact ? "=" : s.recall >= 0.5 ? "~" : " "
        print("\(mark) \(String(format: "%3.0f%%", s.recall * 100))  \(s.expected)  →  \(s.actual)"
              + (got.tags.isEmpty ? "" : "  [\(got.tags.joined(separator: "] ["))]"))
    }
    FileHandle.standardError.write(Data("\n".utf8))
    let sum = Evals.summarize(scores)
    let pct = { (d: Double?) in d.map { String(format: "%.0f%%", $0 * 100) } ?? "n/a" }
    print("exact \(pct(sum.exactRate)) · title recall \(pct(sum.meanRecall)) · tag precision \(pct(sum.tagPrecision)) · tag recall \(pct(sum.tagRecall))")
    print("= same title   ~ half or more of its words   (blank) missed")
    if !failures.isEmpty {
        print("\(failures.count) of \(cases.count) never reached the titler: \(failures[0])")
    }

case "ai":
    let p = ShotScribeDefaults.aiProvider()
    print("titler   \(p.kind.name)")
    if let m = p.effectiveModel { print("model    \(m)") }
    if let c = p.effectiveCommand, p.kind != .claude { print("command  \(c)") }
    if let e = p.endpoint { print("endpoint \(e)") }
    print("status   \(p.availability().text)")
    print("text     \(p.kind.whereTextGoes)")
    print("Set in ShotScribe.app › AI. --offline forces keyword titles for one run.")
case "name":
    // Read-only on purpose: the menu bar panel is where a template is edited,
    // and this is how the CLI shows which one it will use.
    let t = renamer.template
    print("layout   \(t.layout)")
    print("date     \(t.dateStyle.rawValue)")
    print("time     \(t.timeStyle.rawValue)")
    print("title    \(t.titleStyle.rawValue), \(t.titleWords) words, max \(t.maxTitleChars) chars")
    print("example  \(Naming.sampleFilename(t) ?? "—")")
    if t == .default { print("\n(the shipped default — nothing custom stored)") }

case "-h", "--help", "help":
    print(usage)

default:
    FileHandle.standardError.write(Data("error: unknown command '\(command)'.\n\n".utf8))
    print(usage); exit(2)
}
