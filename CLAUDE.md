# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ShotScribe renames macOS screenshots from `Screenshot 2026-08-11 at 3.41.07 PM.png`
to `2026-08-11 1541 AWS Billing Console.png`. On-device Vision OCR pulls the text,
a titler turns that text into a 2–3 word label, and the file is renamed date-first.

Swift package, macOS 13 floor, **zero third-party dependencies** — that's deliberate.
Argument parsing (no ArgumentParser) and JSON-RPC (no MCP SDK) are hand-rolled and
should stay that way.

## Commands

```bash
swift build -c release              # all four products
swift build -c release --product shotscribe-mcp
./scripts/package-app.sh            # → dist/ShotScribe.app (ad-hoc signed)
APPLE_NOTARY_PROFILE=<profile> ./scripts/package-app.sh   # sign + notarize + staple app AND dmg
```

**Tests need the Xcode toolchain, not the Command Line Tools.** `xcode-select -p` on
this machine points at `/Library/Developer/CommandLineTools`, which ships no XCTest,
so a bare `swift test` fails with `no such module 'XCTest'`. Prefix instead:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NamingTests/testUniqueNameSuffixesOnCollision
```

(`sudo xcode-select -s /Applications/Xcode.app` fixes it permanently but needs the
user's password — don't run it for them.) If a build errors about a precompiled
module built with a different module cache path, the repo moved: `rm -rf
.build/*/{debug,release}/ModuleCache`.

There is no CI. Tests run locally only.

## Architecture

One engine, four front doors. `ShotScribeCore` holds every piece of logic; the three
executables are thin.

```
ShotScribeCore ──┬── shotscribe          CLI: label / rename / watch
                 ├── shotscribe-mcp      MCP server (stdio JSON-RPC) for Claude Code / Cowork
                 └── shotscribe-menubar  SwiftUI MenuBarExtra → dist/ShotScribe.app
```

Pipeline: `OCR.recognizeText` → `Titler.title(forOCRText:)` → `LabelCleaner.clean`
→ `Naming.filename(…template:)` → `Renamer` moves the file. `FolderWatcher` feeds it new
captures.

Settings live in one place for all four doors: `ShotScribeDefaults` (the
`com.joshvanorden.shotscribe` domain, `.standard` from inside the app itself). That is how
the CLI and MCP server spell names the same way the app does — `ShotScribeModel.defaults`
delegates to it rather than resolving the domain a second time.

`Capture` holds the one list of capture extensions (stills plus `mov`/`mp4`); the watcher, the
index, the MCP door and the panel all filter with `Capture.isCapture`. `OCR.frames(atPath:)` is the
one place a path becomes images — one for a still, two via `Frames` for a recording — and every
reader (labelling, `ShotIndex.searchText`, `recognizeLayout`) goes through it. `recognizeLayout`
is what the `layout_screenshot` MCP tool and `/screenshot code` build on: positions in percent of
the image, top-left origin, reading order.

### The Titler seam, and why its direction flips

`Titler` is the swappable protocol. Behind it: `ClaudeTitler` (`claude -p`, tools denied),
`CommandTitler` (any command with `{prompt}` as one argument — the Codex, Gemini CLI, Cursor
Agent and Ollama presets are just templates in `AIProvider.Kind`), `EndpointTitler` (one
OpenAI-compatible `POST /chat/completions`, the only network code) and `KeywordTitler` (offline).
`AIProvider` is the stored choice (`ShotScribeDefaults.aiProvider()`, key `shotscribe.ai`,
migrating the old `shotscribe.useClaude` switch) and `makeTitler()` is the one factory every door
uses; `CommandRunner` is the one process runner (`/dev/null` stdin, both pipes drained, watchdog).
The endpoint key is in the Keychain via `Secrets.store`; tests swap in `MemoryStore`.
`SHOTSCRIBE_DEFAULTS=<domain>` points a CLI run at another settings domain, as `SHOTSCRIBE_INDEX`
does for the index — use it for any provider trial, never the real domain.

**`shotscribe-mcp` must never use `ClaudeTitler`.** When Claude calls the server as a
tool, the caller already *is* the model — titling inside the tool would be a nested LLM
call. So the server is pinned to `Renamer(titler: KeywordTitler())`, `ocr_screenshot`
hands back raw text for the caller to title, and `rename_screenshot` takes the caller's
`title` (which routes through `Renamer`'s `label:` short-circuit, skipping OCR entirely).
Keep it mechanical.

### Tags

Tags are **Finder tags** on the file (`com.apple.metadata:_kMDItemUserTags`), which is why
they need no UI: Finder and Spotlight are the surface. `Tagging.add` merges rather than
replaces — setting `tagNames` overwrites the whole set, including what the user filed by
hand — and writes through `NSURL`, since the `URLResourceValues.tagNames` setter is macOS
26+ against this package's macOS 13 floor.

The file is the record; `IndexedShot.tags` is a cache of it, refreshed on every sweep —
including the skip-unchanged branch, since a tag added in Finder changes no bytes. It is
`[String]?` so an index written before tags still decodes (a throw there means `load`'s
`try?` silently returns an empty store — the whole history). `ShotIndex.search` ranks a tag
hit just under a name hit.

`Titler.labelling(forOCRText:vocabulary:)` returns title *and* tags from one model call.
It is a **protocol requirement with a default implementation**, never an extension method
alone: every door holds a `Titler` existential, and extension-only methods dispatch
statically, so overrides would be silently skipped (they were — see `History.md`, 2026-09-11).

### Invariants worth not breaking

- **A tag only ever comes from the vocabulary.** `Tagging.accepted` filters every proposal,
  wherever it came from — the model, an MCP caller, anywhere. OCR text is attacker-reachable,
  so a screenshot must not be able to invent its own filing; this is the same boundary as the
  `ClaudeTitler` tool denylist, not a tidiness rule.

- **Only macOS default capture names get renamed.** `Naming.isRawCapture(at:)`, enforced in
  `Renamer.rename` before anything else. The English prefix (`"Screenshot "` / `"Screen Shot "`)
  matches on the name alone; any other language needs the default-name shape *and* the
  `com.apple.metadata:kMDItemIsScreenCapture` xattr. Never let the xattr decide alone: it
  survives renames, so it's on every shot ShotScribe named and every capture the user renamed.
  A file the user named is never touched unless `force`.
- **`NameTemplate.default` must keep spelling today's name**, `"2026-08-11 1541 AWS Billing
  Console.png"` — date first, so name-sort stays chronological and truncating UIs keep the
  meaningful tail. The repo is public: an upgrade that renames differently than yesterday is
  a bug. `NameTemplateTests` pins it.
- **A template is validated before it is stored, never at rename time.** `Naming.validate`
  refuses unknown tokens, a layout with no token, path-illegal characters, and — the
  load-bearing one — any template whose sample passes `looksLikeDefaultCaptureName`, which
  would set the watcher renaming ShotScribe's own output. `ShotScribeDefaults` is the gate;
  a stored template that no longer validates is ignored in favour of the default.
- **The OCR text is untrusted** — it's whatever was on screen, possibly a malicious page.
  `ClaudeTitler` therefore runs `--strict-mcp-config` with a hard `--disallowedTools`
  denylist (Bash, Read, Write, Edit, WebFetch, Task, …). Don't loosen it to "help" the model.
- **Three details in `ClaudeTitler.complete` are load-bearing**, not incidental: `/dev/null`
  stdin (else `claude` stalls ~3s per call waiting on stdin), the concurrent stderr drain
  (reading only stdout deadlocks past 64KB of stderr), and the SIGTERM→SIGKILL watchdog.

### Menu bar app specifics

- `AppModel` is reached via `@NSApplicationDelegateAdaptor`, **not** `@StateObject` on the
  `App` — a `@StateObject` referenced only inside the `MenuBarExtra` closure isn't created
  until the panel is first opened, so folder watching wouldn't start until someone clicked.
- `AppModel.rename` composes OCR → title itself instead of letting `Renamer` do it, so a
  titler failure is *visible* (logged, surfaced in the panel) rather than silently degrading
  to the offline label.
- 1.5s sleep before reading a new capture: macOS may still be writing the file.
- `ObservableObject` over `@Observable` on purpose — keeps the macOS 13 floor.
- `SMAppService` (launch at login) only works from a real `.app` bundle; under `swift run`
  it throws and the error lands in the panel.
- No console — debug through `~/Library/Logs/ShotScribe.log` (`Log.write`).

### The window (`.hosted` chrome) and how to see it without launching

The hosted pane is the glass design locked on 2026-09-12: the grid scrolls edge to edge under
floating capsules, a latest-capture hero sits on a band tinted by its own thumbnail, and the
settings live in a tabbed inspector (Folder, Rename, Name, File, Keep) floating on
`ultraThinMaterial`. `glass(in:)` is the one helper for that material and its lit top edge;
`AspectThumbnail` sizes tiles by ratio. Two gotchas at the macOS 13 floor: `Text.foregroundStyle`
on a concatenated `Text` is 14+ (use `foregroundColor`), and the pane must paint
`windowBackgroundColor` itself or a host that draws none shows the grid over black.

To look at the pane without putting a window on the operator's machine: `scripts/render-pane.swift`
(compile line in its header) hosts the real `ShotScribeView` in an unordered `NSWindow` against the
`.o` files in `.build/debug`, with `ShotScribeDefaults.suiteOverride` and `ShotIndex.storeOverride`
pointed at scratch and `shotscribe.watching` off, drives the model, and snapshots. `ImageRenderer`
is not enough; it leaves AppKit-backed controls blank. Fixtures must be hard links of real captures,
not copies, or creation dates are all "now". A menu `Picker` must bind to plain `@State` with an
`onChange` handler, never a computed `Binding` — the computed one changed its displayed value
without calling the setter (2026-09-13).

### Version strings

`VERSION` in `scripts/package-app.sh` (feeds the generated Info.plist and names the DMG) is
the latest git tag, never a literal. `serverInfo` in `Sources/shotscribe-mcp/main.swift` is
still a literal — bump it in the same commit as the tag (it sat at 0.2.0 until 1.5.0).

## Repo conventions

`Hook.md` holds the working rules and is authoritative; the CHRIS OP doc set
(`Context.md`, `History.md`, `Index.md`, `Skills.md`, `Obsidian.md`, `Phase.md`) is
maintained alongside the code as work happens, via `/save`. Two rules bite in practice:

- **`roadmap.md` is lowercase, gitignored, and never committed.** If it shows up staged or
  tracked, stop and fix that first.
- **Pushing is user-authorised only** (`~/.git-hooks/pre-push` requires `MANUAL_PUSH=1`). Commit locally; push at end of day or when asked.

`skills/screenshot/SKILL.md` is a product of this repo — the `/screenshot` gesture shipped
to other Claude Code users — not config for working here.
