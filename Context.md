# Context

<!-- markerblock:you-are-here -->
## You are here
<!-- Written by /save. Overwritten each time — narrative lives in History.md. -->

**Last session:** 2026-09-13
**Phase:** Ship — 1.6.2 is public (https://github.com/josh-vanorden/shotscribe/releases/tag/v1.6.2, notarized under `shotscribe-notary`); 1.6.0 and 1.6.1 went out the same day
**Next action:** `shotscribe eval --limit 25` with `claude` signed in (it is, since tonight) — the first real quality number against names that were not the titler's own. Then pick up the 1.6.3 ideas in `roadmap.md`: the customizable landing zone (per-tile use counts, hide/reorder/pin) first.

**Open loops**
- Toolbelt's pin is at `from: "1.6.2"`, committed there and unpushed (with the 1.6.0 pin `4eeb4dd`), beside Josh's own uncommitted `.gitignore`; pushing Toolbelt is his call.
- `~/.claude.json` still registers the `shotscribe` MCP server under the old project path `~/git/personal/shotscribe` (binary gone); re-register from `active/shotscribe/.build/release/shotscribe-mcp` — Josh's config.
- The announcement is drafted (`announcement.md`, session scratchpad; two lengths) — Josh: secondary.
- Codex, Gemini CLI, Cursor Agent presets unverified here; `codex` absent since macOS refused the 0.118.0 cask binary. Backlog sweep (93 raw files) unbuilt; recordings and the capture-flag timing remain hand-untested.
- Left to the operator by the security pass, on purpose: confining MCP OCR to the watched folder, pinning the README's skill URL to a tag, CI.

**Ruled out**
- A state mark in the accent colour, or inside the tile: invisible on the light band; the default's halo is green and outside the circle (three rounds, 2026-09-13).
- "Set as the click action" as the wording; reusing `cockpit-notary`; moving a published tag; a menu `Picker` on a computed `Binding`; CoreSVG and Quick Look for brand SVGs; `ImageRenderer`; copied fixtures; extension-only `labelling`; Remote Control as a push channel; braces as the code icon.

**Working tree:** clean once the docs commit carrying this block lands
**Unpushed commits:** none after this block's `/clean-tree`
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
- **The landing zone is in both views** (the list lost it until 2026-09-13),
  and the window reloads the moment the watcher names a capture (it kept its
  launch-time cache until the same day).
- **A bin on every shot** — the tile's corner and the landing zone (on hover,
  on a dark scrim), beside the date in the list: `DeletePill` eats the word
  "Delete" letter by letter, furls to the bin, turns an arc for a beat, seals,
  and the shot goes where the **Keep** tab says — Trash, deleted outright, or
  (for clean-up) an archive folder. Default: the Trash.
- **1.6.1:** **Mark up in Preview** (a tile with Preview's icon after Finder,
  and in every menu; Restore moved beside the "was …" line). **Tags as a
  filter:** a strip under the grid head with every tag in use and its count —
  isolate, narrow (AND), Show all, Esc — and **By tag** in the sort menu
  grouping the grid by filing; an empty result keeps the way out. The bin sits
  on a dark scrim over images. Security sweep: a custom command's first token
  must be a plain name or a path; plain http to a remote endpoint is flagged.
- **1.6.2:** **Right-click any screenshot** — grid tile, list row, the hero's
  thumbnail, the popover — for one shared menu (`ShotMenu`): Reveal, Mark up,
  Share, Send to, Rebuild as code, File as, Restore, the bin. **A click has a
  default** (`ShotScribeModel.defaultAction`: Reveal, Mark up, Send to or
  Rebuild; Reveal to start): right-click a landing-zone tile, "Set as
  default", and every plain click on a shot does that. The default tile wears
  a green halo outside its circle (`ShotPalette.chosen`, systemGreen on
  purpose — the accent is what everything else wears, and it vanished on the
  light band) and the menu marks it "✓ default". The seven-track security
  pass's twelve fixes ride along (`SECURITY.md`).
- **The icon is Josh's artwork** (`assets/ShotScribe-artwork.png`, fitted to
  Apple's grid by `scripts/fit-icon.swift`, built by `scripts/make-iconset.sh`).
  **The tagline** heads the README and the first-launch welcome: *Every
  screenshot, named — the moment it lands, by the AI you already use, and it
  stays a file in your folder.*

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
