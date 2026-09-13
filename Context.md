# Context

<!-- markerblock:you-are-here -->
## You are here
<!-- Written by /save. Overwritten each time — narrative lives in History.md. -->

**Last session:** 2026-09-12
**Phase:** Ship (1.5.0 tagged, notarized and pushed; the DMG is local — no GitHub release yet; Toolbelt still mounts 0.6.1)
**Next action:** Ask Josh whether to publish: `gh release create v1.5.0 dist/ShotScribe-1.5.0.dmg`; then raise Toolbelt's pin at `toolbelt/Package.swift:34` to `.upToNextMinor(from: "1.5.0")` and `swift package update shotscribe`. In parallel, sign in to `claude` and run `.build/release/shotscribe eval --limit 25`.

**Open loops**
- The punch list in `roadmap.md` (13 items): nothing hand-tested yet — the tiles and their hover names, the title edit, Share unfolding and an AirDrop, the Send to Claude paste, `/screenshot code`, a screen recording, the capture-flag timing.
- Backlog sweep: 93 raw `Screenshot …` files in the folder (newest 2026-08-21), unbuilt; same pass could re-render old names under a new template.
- `claude` signed out since 2026-09-10: no eval number yet, and Remote Control needs the login too (left off by Josh's choice).
- Toolbelt pin: `.upToNextMinor(from: "0.6.0")` cannot resolve a 1.x tag.

**Ruled out**
- Remote Control (`claude rc`) as a push channel into a session: only claude.ai/code and the phone app can send into one; Send to Claude is a paste by design.
- Braces as the code tile's icon (an engineer's glyph); `standardShareMenuItem` for the share row (a menu, not a row).
- The `kMDItemIsScreenCapture` xattr alone as "raw"; `ImageRenderer` for off-screen renders; copied fixtures; `labelling` as an extension-only method; app names in the menu-word list; opening a Terminal for stage two.

**Working tree:** clean once the docs commit carrying this block lands
**Unpushed commits:** 1 (that docs commit), pushed by the same `/clean-tree`; code and the `v1.5.0` tag were pushed first
<!-- /markerblock:you-are-here -->

ShotScribe turns raw macOS screenshot filenames ("Screenshot 2026-08-11 at
3.41.07 PM.png") into dated, findable titles ("2026-08-11 1541 AWS Billing
Console.png") — on-device OCR (Apple Vision) plus a swappable Titler seam.

## Current state (2026-09-12 — 1.5.0)

Tagged `v1.5.0` at `9ddbf8c` on `settings-pane`; everything since 0.6.1 ships
as one release (the notarized DMG's status is in `History.md`, same date).
Toolbelt still pins `.upToNextMinor(from: "0.6.0")`, which cannot reach a 1.x
tag until its `from:` is raised.

- **Captures are recognised in any language.** `Naming.isRawCapture(at:)`:
  the English prefix alone, or the default-name shape plus the
  `kMDItemIsScreenCapture` xattr. Never the xattr alone — it survives renames.
- **The name is a template.** `NameTemplate` (layout tokens + date, time,
  title styles, words, cap), validated before it is stored; the default spells
  exactly the 0.6 name. Stored in `ShotScribeDefaults`, read by every door.
- **Tags.** A closed vocabulary (stored, editable), one model call for title
  and tags, written as Finder tags, cached in the index, ranked in search,
  chips on tiles, "File as" for older shots, and a tagging switch. Off keeps
  the vocabulary.
- **The app has a window and a Dock icon**, with the menu bar item kept so
  closing the window leaves it watching. `LSUIElement` is gone.
- **The window is the glass design** (locked 2026-09-12): grid edge to edge
  under floating capsules, a latest-capture hero on its own ambient band, day
  groups, gallery tiles with hover captions, and a tabbed floating inspector
  (Folder, Rename, Name, File, Keep) that never scrolls. The popover is
  unchanged.
- **The landing zone.** The hero's title edits in place (click or the pencil;
  Return renames with the stamp kept exactly as spelled — `Naming.retitled`,
  `ShotScribeModel.retitle`; undo keeps working). Under it, one row of round
  tiles carrying the icon of the service each reaches, named on hover by
  `NamedOnHover`: Finder's own icon, **Share** (which unfolds in place into
  the Mac's destinations for the file — AirDrop, Mail, Messages, Notes… with
  "More" as the system picker), Claude's app icon for **Send to Claude**
  (copies `/screenshot "<path>"`; the skill takes a path now), a hammer for
  **Rebuild as code** (the brief), undo, and the tag menu. Braces were
  rejected as an engineer's glyph.
- **Four borrows from screenshot-to-code.** `layout_screenshot` (text with
  positions, on-device) and `/screenshot code`; screen recordings as captures
  (two frames via AVFoundation); `shotscribe eval`, with the folder as the
  test set; `{app}`, read off the menu bar or title bar. The eval's first run
  found a fortnight of OCR-noise names kept while Claude was signed out, and
  the `{app}` test found the menu bar leaking into titles; both fixed.
- Tags are drawn as tags (glyph, word, tooltip); any shot drags out as a copy
  of the file.
- Engine: `NameTemplate`, `Settings`, `Tagging`, `Capture`, `Frames`, `Chrome`,
  `Evals`, `CodeBrief`, `SendToClaude`, `Naming.retitled`; `IndexedShot.tags`;
  `Renamer(titler:template:vocabulary:)`. 125 tests.
- Remote Control (`claude rc`) is not a push channel into a session — only
  claude.ai/code and the phone app can send into one — so Send to Claude is a
  paste by design. It is off on this machine by Josh's choice (2026-09-12).

## Earlier state (2026-09-03 — the fourth question: what is kept)

ShotScribe answered *where* (the watch folder), *when* (the watch toggle) and
*how* (the titler). It now answers **what is kept**, in a Keep block beside the
others — the surface the other sidecars copy (toolbelt `Phase.md`, "The
local-setup contract"):

- **Undo.** The raw capture name rides in the index (`IndexedShot.original`),
  so a rename can be walked back from the tile's context menu or an Undo on
  the history row, for as long as the file is where the rename left it. The
  watcher is told about the restored name *before* the move, or it would
  rename the file straight back.
- **Sessions.** Consecutive captures within a gap the user sets (default 3
  min, Off–15) fold into one stacked tile — the last shot stands for the
  burst, count on its shoulder — and open out in place. Flat while searching
  and under the name sorts, where "consecutive" means nothing.
- **Clean-up.** Duplicates (same text, whitespace- and case-insensitive; thin
  or empty OCR never counts) and captures older than N days (Never–365) are
  *flagged*, never acted on: **Preview clean-up** shows every move with its
  reason, and only **Move N to …** applies it. Destination is the Trash or an
  archive folder the user picks. Nothing is ever deleted outright.
- **Found on the way:** `ShotIndex.record` keyed by the path it was handed,
  `reindex` by the filesystem-canonical one; under `/var/…` a sweep built a
  twin entry and the original name rode with neither. Both key canonically now.

Engine: `Keeping.swift` — `KeepPolicy`, `Sessions.collapse`, `Cleanup.plan`
(pure) and `Cleanup.apply` (the only thing that touches disk, and it takes the
plan the user saw). 50 tests.

## Earlier state (as of 2026-08-20, v0.4.0)
- Swift package, five targets: `ShotScribeCore` (the engine), `shotscribe`
  (CLI), `shotscribe-mcp` (MCP server for Claude Code/Cowork), **`ShotScribeUI`
  (the face as a mountable library)**, and `shotscribe-menubar` (the menu bar
  app around it).
- **2026-08-20 — the face was extracted.** `AppModel` and the panel lived
  inside the menu bar executable, so nothing else could host ShotScribe. They
  are now `ShotScribeModel` and `ShotScribeSurface` in `ShotScribeUI`, with a
  `ShotScribeChrome` mode (`.menuBar` / `.hosted`) so the popover and a roomy
  detail pane share one view instead of two that drift. `shotscribe-menubar` is
  now a consumer of that library, not the owner of it. Toolbelt mounts
  `ShotScribeSurface(chrome: .hosted)`.
- Default titler is `ClaudeTitler` — shells out to the user's own `claude -p`
  CLI (no API keys shipped, no account of ShotScribe's own). `KeywordTitler`
  is the offline fallback when Claude Code isn't installed.
- Menu bar app (`ShotScribe.app`) is packaged via `scripts/package-app.sh`,
  now Developer-ID signed, notarized, and stapled (app + DMG) — the first
  notarization run was clean (commit a5b221d).
- `skills/screenshot/SKILL.md` ships the `/screenshot` gesture for any
  Claude Code user, independent of whether ShotScribe's MCP server is
  registered.
- All four "doors" to the one engine (CLI, MCP, menu bar, `/screenshot`
  skill) are now shipped, per the latest commit message.

## Key decisions
- **A plan is shown before it is applied, and clean-up never deletes** (2026-09-03).
  `Cleanup.plan` is pure; `apply` takes that plan, not a policy it re-evaluates,
  so what moves is exactly what was on screen. Trash or an archive folder, both
  recoverable. Thin OCR text is unknown, not a match — it never makes duplicates.
- Only macOS default capture filenames get renamed — a file the user named
  themselves is never touched (safety rule baked into the core).
- OCR always stays on-device; only extracted text (never the image) reaches
  the titler, and only when Claude titling is enabled.
- **ShotScribe's settings belong to ShotScribe, not to its host.**
  `ShotScribeModel.defaults` reads the `com.joshvanorden.shotscribe`
  preferences domain by name whenever `Bundle.main` is something else. Inside
  ShotScribe.app that is exactly `.standard`, so nothing migrated. Without it, a
  host with its own bundle id starts blank — and starts renaming files in a
  folder the operator never chose.
- **Two watchers never race.** A hosted copy detects a running ShotScribe.app
  (KVO on `NSWorkspace.runningApplications` — the didLaunch/didTerminate
  notifications do not fire for an `LSUIElement` app) and stands down with a
  banner rather than fighting over the same capture. It resumes on its own when
  the app quits.
- **App-level controls are `.menuBar`-only.** "Launch at login" resolves through
  `SMAppService.mainApp` and "Quit" terminates `NSApplication.shared` — in a
  hosted pane both would act on the host, so the surface omits them.

## Before touching anything
- Build: `swift build -c release`. Package the menu bar app with
  `./scripts/package-app.sh` (`APPLE_NOTARY_PROFILE=<profile>` for the full
  sign/notarize/staple pipeline).
- Tests live in `Tests/ShotScribeCoreTests/`.
- `swift test` runs green: **13 tests, 0 failures** (first executed
  2026-08-20). Earlier that day it could not compile at all — `xcode-select`
  was pointing at CommandLineTools, so `XCTest` was missing; that was fixed the
  same day. If the symptom returns, check `xcode-select -p` first.
- TODO: no CI workflow found in the repo — confirm whether tests run
  anywhere besides locally.
