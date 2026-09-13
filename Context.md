# Context

<!-- markerblock:you-are-here -->
## You are here
<!-- Written by /save. Overwritten each time — narrative lives in History.md. -->

**Last session:** 2026-09-13
**Phase:** Ship — 1.5.1 is public; 1.6.0 ("Bring your own AI") is built, tested and pushed on `settings-pane`, unreleased, scheduled for Monday 2026-09-14
**Next action:** Monday: after Josh's click-through of the AI tab, bump `serverInfo` to 1.6.0 and date the CHANGELOG, tag `v1.6.0`, `APPLE_NOTARY_PROFILE=cockpit-notary ./scripts/package-app.sh`, verify as 1.5.1 was, `/clean-tree`, `gh release create v1.6.0 dist/ShotScribe-1.6.0.dmg --latest --notes-file …` (draft in the session scratchpad — recreate from `roadmap.md` if gone), then Toolbelt's pin to `from: "1.6.0"`.

**Open loops**
- Josh's click-through of the AI tab (each kind, the tile's mark, "Try it" on Ollama, the popover switch, an endpoint with no key) — the one thing between here and the tag.
- Codex, Gemini CLI, Cursor Agent presets unverified on this Mac; `codex` is absent here since macOS refused the 0.118.0 cask binary (memory: `codex-cask-flagged-2026-09-13`).
- Brand marks are Lobe Icons copies shipped on Josh's call; OpenAI's and Google's own downloads are gated (`assets/brands/README.md`).
- The 1.5 punch list (title edit, Share unfold, AirDrop, `/screenshot code`, recordings, capture-flag timing) is still Josh's to run by hand; backlog sweep (93 raw files) unbuilt; `claude` signed out; Remote Control off by choice.

**Ruled out**
- A menu `Picker` on a computed `Binding` (changes its face, not the model); CoreSVG and Quick Look for brand SVGs; the initial monogram as the shipped tile (Josh: real marks); ChatGPT.app's icon standing in for Codex.
- Remote Control as a push channel; braces as the code icon; `standardShareMenuItem` for the share row; the xattr alone as "raw"; `ImageRenderer`; copied fixtures; extension-only `labelling`; app names in the menu-word list; a Terminal for stage two.

**Working tree:** clean once the docs commit carrying this block lands
**Unpushed commits:** 10 + this docs commit, all pushed by the `/clean-tree` that follows
<!-- /markerblock:you-are-here -->

ShotScribe turns raw macOS screenshot filenames ("Screenshot 2026-08-11 at
3.41.07 PM.png") into dated, findable titles ("2026-08-11 1541 AWS Billing
Console.png") — on-device OCR (Apple Vision) plus a swappable Titler seam.

## Current state (2026-09-13 — 1.5.1 public, 1.6.0 built and unshipped)

1.5.1 is the public release (GitHub, notarized DMG). Everything below that
says "1.6" is on `settings-pane`, built, tested (140) and pushed, with the tag,
notarization and release scheduled for Monday 2026-09-14 (`roadmap.md`).
Toolbelt still pins `.upToNextMinor(from: "0.6.0")`, which cannot reach a 1.x
tag until its `from:` is raised.

- **Bring your own AI (1.6).** `AIProvider` is the one stored choice
  (`shotscribe.ai`, migrating the old switch): Offline, Claude Code, Codex,
  Gemini CLI, Cursor Agent, Ollama, An endpoint, Other CLI…. `makeTitler()` is
  the factory every door uses; `CommandTitler` runs any command with
  `{prompt}` as one argument (presets are editable templates carrying each
  tool's tool-denying flags), `EndpointTitler` is the only network code (key
  in the Keychain via `Secrets`), `CommandRunner` the one process runner.
  `Renamer.onTitlerError` makes a failing titler visible; the CLI prints it.
  `shotscribe ai`, `--offline`, `SHOTSCRIBE_DEFAULTS=<domain>`.
- **Five tabs, still.** Folder · Rename (switch, rename-now, then *Spelling* —
  the template) · AI (picker bound to plain state, the kind's fields,
  availability computed off the main thread, "Try it on the newest capture")
  · File · Keep. The popover keeps one "Title with AI" switch.
- **The Send-to tile wears the titler's mark**: Claude, the OpenAI mark for
  Codex, Gemini, Cursor, Ollama (Lobe Icons copies in `assets/brands/`,
  rasterised through WebKit by `scripts/svg-to-png.swift`, embedded by
  `scripts/make-brand-art.swift`), `wifi.slash` offline, `terminal` and
  `network` for the open doors. `/screenshot "<path>"` is copied only for
  Claude Code; every other kind gets a plain ask.

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
