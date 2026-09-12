import Foundation
import ShotScribeCore

// shotscribe — CLI front end over ShotScribeCore.
//
//   shotscribe label  [--no-claude] <file>
//   shotscribe rename [--no-claude] [--dry-run] [--force] <file>
//   shotscribe watch  [--no-claude] [dir]
//
// Zero third-party dependencies — argument parsing is deliberately tiny.

func makeTitler(noClaude: Bool) -> Titler {
    if noClaude { return KeywordTitler() }
    if ClaudeTitler.isAvailable() { return ClaudeTitler() }
    FileHandle.standardError.write(Data(
        "note: `claude` not found — using the offline keyword titler.\n".utf8))
    return KeywordTitler()
}

func expand(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
}

func describe(_ outcome: RenameOutcome) -> String {
    switch outcome {
    case .renamed(let from, let to):
        let tags = Tagging.finderTags(of: to)
        let filed = tags.isEmpty ? "" : "\n   tags  \(tags.joined(separator: ", "))"
        return "renamed  \(from.lastPathComponent)\n      →  \(to.lastPathComponent)\(filed)"
    case .wouldRename(let from, let to):
        return "would rename  \(from.lastPathComponent)\n           →  \(to.lastPathComponent)"
    case .skippedNotRawCapture(let url):
        return "skipped (not a macOS capture; use --force): \(url.lastPathComponent)"
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

FLAGS:
  --no-claude   Use the offline keyword titler instead of `claude -p`
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

let noClaude = args.contains("--no-claude")
let noTags   = args.contains("--no-tags")
let dryRun   = args.contains("--dry-run")
let force    = args.contains("--force")
let positional = args.filter { !$0.hasPrefix("--") }

let titler = makeTitler(noClaude: noClaude)
let renamer = Renamer(titler: titler,
                      template: ShotScribeDefaults.nameTemplate(),
                      vocabulary: (noTags || !ShotScribeDefaults.taggingEnabled()) ? [] : ShotScribeDefaults.vocabulary())

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
    print("shotscribe: watching \(dir.path)  (Ctrl-C to stop)")
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
    guard watcher.start() else {
        FileHandle.standardError.write(Data("error: can't watch \(dir.path)\n".utf8)); exit(1)
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
        print("\(mark) \(fmt.string(from: h.shot.captured))  \(h.shot.name)\(filed)")
        if !h.snippet.isEmpty { print("     \(h.snippet)") }
        print("     \(h.shot.path)")
    }
    if hits.count > 20 { print("… and \(hits.count - 20) more") }

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
