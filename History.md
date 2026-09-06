# History

Append-only session log. `/save` is the checkpoint gesture — new entries go
at the bottom. Seeded 2026-08-12 from `git log --oneline -15`.

## 2026-08-11 — Scaffold shotscribe
Extracted from the larger "Navi" app as its own single-purpose tool.
Core engine (`ShotScribeCore`) + CLI (`rename` / `label` / `watch`),
on-device Vision OCR, swappable `Titler` seam.

## 2026-08-11 — MCP server
Added `shotscribe-mcp`: the same engine exposed as MCP tools
(`latest_screenshots`, `ocr_screenshot`, `rename_screenshot`) so Claude
Code / Cowork can call it mid-session instead of shelling out to the CLI.

## 2026-08-12 — Menu bar app
Added `ShotScribe.app` (`MenuBarExtra`): auto-rename watch toggle,
configurable watch folder, Claude/offline titler switch, launch at login,
recent-rename history.

## 2026-08-12 — First-run polish
Icon, welcome window, folder choice, and login flow — passing the "I just
downloaded this" test for a stranger's first launch.

## 2026-08-12 — "Bring your own Claude" made explicit
UI and README now state plainly that ShotScribe drives the user's own
`claude` CLI/subscription — no keys, no account of its own.

## 2026-08-12 — Ship stage: sign, notarize, staple
`scripts/package-app.sh` gained the full Apple pipeline (Developer ID,
hardened runtime, secure timestamp, notarytool, staple) for both the app
and a drag-to-Applications DMG. First run was clean: both submissions
Accepted, `spctl` reports "source=Notarized Developer ID".

## 2026-08-12 — /screenshot skill
Shipped `skills/screenshot/SKILL.md`, a generic "see my newest screenshot"
gesture for any Claude Code user. Completes the fourth door to the engine
(CLI, MCP, menu bar, skill).

## 2026-08-20 — Extracted the face (`ShotScribeUI`)
ShotScribe had four doors to one engine, but the *face* wasn't one of them:
`AppModel` and `PanelView` lived inside the `shotscribe-menubar` executable, so
nothing else could host it. Toolbelt wanted to admit ShotScribe and had nothing
to mount.

- New `ShotScribeUI` target: `ShotScribeModel` (was `AppModel`, now public) and
  `ShotScribeSurface` / `ShotScribeView` (was `PanelView`). `Log` moved with
  them. `shotscribe-menubar` keeps only the `@main`, the app delegate, and the
  welcome window, and is now a consumer of the library.
- `ShotScribeChrome` — `.menuBar` draws the 340pt popover with "Launch at
  login" and "Quit"; `.hosted` draws a roomy detail pane without them, because
  `SMAppService.mainApp` and `NSApplication.shared.terminate` would act on
  whatever is hosting, not on ShotScribe. One view, two rooms, rather than two
  views that drift.
- **Settings follow the tool, not the host.** `ShotScribeModel.defaults` reads
  the `com.joshvanorden.shotscribe` domain by name whenever `Bundle.main` is
  something else; inside ShotScribe.app it is `.standard`, so nothing migrated.
  Caught before shipping: without it, a belt-mounted copy read empty defaults
  and would have started renaming in the *system* screenshot folder instead of
  `~/Pictures/Navi Screenshots`.
- **Two watchers never race.** A hosted copy detects a running ShotScribe.app
  and stands down with a banner (watch toggle and rename action disabled),
  resuming automatically when it quits. First implemented with the workspace
  didLaunch/didTerminate notifications, which never fired — ShotScribe.app is
  `LSUIElement`. Switched to KVO on `NSWorkspace.runningApplications`, which is
  documented KVO-compliant and does see accessory apps.
- No engine changes: `ShotScribeCore` is untouched.
- Verified by hand (the suite can't run — see `Phase.md`): clean rebuild, the
  menu bar popover still opens and shows the real history, and the belt-hosted
  pane shows the right folder, the real history, and the stand-down banner
  appearing and clearing as ShotScribe.app starts and quits.

## 2026-09-03 — The fourth question: what is kept

Where, when and how were answered; nothing said what became of a capture
afterwards. Added `Keeping.swift` (`KeepPolicy`, `Sessions`, `Cleanup`), the
original name in the index with `Renamer.restoredURL`/`restore` and
`FolderWatcher.ignore` behind an Undo, session tiles that fold bursts, and a
Keep block with a previewed, confirmed clean-up to the Trash or an archive
folder. The undo test exposed `record` and `reindex` keying the index by
different spellings of one path; both key canonically now. Verified: 50 tests
green (17 new), `swift build` clean, and the belt built against this working
copy in edit mode. Seen on screen later the same day, mounted in the belt from
the v0.6.0 tag: the Keep block, the pickers and the session grid all render.

## 2026-09-04 — QA pass

A review agent read the Keep commit against its own design intent. Fixed: the clean-up plan is scoped to the watched folder and names it (it reached every folder ever watched); the preview lists every row; Cancel is disabled once moves are under way; the archive folder may not be the watched one; undo is withheld while ShotScribe.app watches the folder; the index serialises writes and the sweep merges onto the freshest store (a record made mid-sweep, and its original name, used to be overwritten); the watcher keys seen files by name and closes its descriptor by value (one leaked fd per toggle). Left: the eight-row preview nit became the scrolling list. 50 tests green.

## 2026-09-06 — shipped as its own app, v0.6.1

- `scripts/package-app.sh` takes its version from the latest tag — it had
  said an older number as a literal — and signs a plain (non-notarized) run
  with the Developer ID too, so macOS permission grants survive rebuilds
  instead of being re-asked after every ad-hoc signature.
- Built, signed, notarized and stapled: `dist/*.app` and
  `dist/*-0.6.1.dmg`, both accepted by Gatekeeper. The same box the belt
  mounts, standing alone; the belt's Toolbox installs and uninstalls it.
