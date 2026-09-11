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

## 2026-09-11 — Captures are recognised in any language

`Naming.isRawCapture` matched only "Screenshot " / "Screen Shot ", so on a
German, French or Japanese Mac — or with a custom `com.apple.screencapture
name` — ShotScribe renamed nothing, silently. It mattered once the repo went
public.

- **The rule now.** The English prefix still matches on the name alone.
  Anything else needs two signals: a name shaped like macOS's default (a word,
  the ISO date, a dotted time, maybe AM/PM and a counter) *and* macOS's own
  capture flag, the xattr `com.apple.metadata:kMDItemIsScreenCapture`, read
  with `getxattr` — no Spotlight involved.
- **Why not the flag alone.** It was the plan until the folder was counted:
  all 218 images in `~/Pictures/Screenshots` carry the flag, including the 125
  ShotScribe had already renamed. The flag survives renames, so on its own it
  would re-rename ShotScribe's output and every capture the user named
  themselves. "Raw" stays a question about the name.
- `canUndo` reads a history row's name with no file behind it, so it gets the
  name-only `looksLikeDefaultCaptureName`.
- Evidence: 58 tests green (8 new, on temp files carrying the real xattr); both
  wrong rules — English-only and flag-only — fail the new tests; old and new
  rules agree on all 218 real captures (93 raw either way), so English users
  see no change. Unverified live: that the flag is on the file when the
  watcher fires. The non-English fixtures are reconstructed formats, not files
  from a non-English Mac.

## 2026-09-11 — Tags, filed where macOS already looks

Tags go on the capture as **Finder tags**, so they show in Finder, sort in the
sidebar and answer a Spotlight search with no ShotScribe surface at all. That
is why tags came before the template pane: the operating system is the UI, so
the feature is reachable the day it lands.

- **A closed vocabulary, not the model's imagination.** Sixteen general tags
  about what kind of thing a shot is; the title already carries the subject.
  A proposal outside the list is dropped, so a page that was on screen cannot
  invent its own filing, and the list cannot sprawl into hundreds of one-offs.
  Two tags per shot.
- **One model call, not two.** `Titler` grew `labelling(forOCRText:vocabulary:)`
  returning title *and* tags; `ClaudeTitler` asks for `Name | tag, tag` in the
  same `claude -p` it already made. `KeywordTitler` tags offline on whole-word
  matches, so `--no-claude` files things too.
- **Found by running it, not by testing it.** `labelling` started as an
  extension method only. Every door holds a `Titler` existential, so the call
  dispatched statically to the default implementation and nothing was ever
  tagged — while 70 unit tests passed, because they held concrete titlers. It
  is a protocol requirement now, with the default alongside, and a test holds
  the existential on purpose.
- **The user's own tags are kept.** Setting `tagNames` replaces the whole set,
  so `Tagging.add` merges. `URLResourceValues.tagNames`' setter is macOS 26+ and
  this package floors at 13, so the write goes through `NSURL`.
- Evidence: 71 tests green, 13 new. End to end on a generated PNG, the CLI
  renamed it to `2026-09-11 1727 Terminal Error Connection.png` and wrote
  `com.apple.metadata:_kMDItemUserTags` holding `terminal` and `error` in
  Finder's own format. Spotlight itself is unconfirmed — the scratch file sat
  in `/private/tmp`, which Spotlight does not index.

## 2026-09-11 — Tags reach the search and the tiles

The filing was on the files but invisible to ShotScribe's own surfaces. Now the
index carries it, search ranks it, and the tiles wear it.

- **The file is the record, the index is a cache.** `record` and `reindex` read
  the Finder tags off the file, so a tag added by hand in Finder arrives on the
  next sweep — including through the skip-unchanged branch, since tags change
  without the bytes changing and re-reading them is one syscall against the OCR
  that branch exists to avoid.
- **`IndexedShot.tags` is optional** so an index written before tags still
  decodes. A throw there would hit `load`'s `try?` and hand back an empty store:
  the operator's entire searchable history, gone quietly.
- **A tag ranks just under the filename** and above body text. Both were chosen
  deliberately; the text merely crossed the screen.
- **On a tile and on a list row**, each tag is a chip, and clicking one searches
  for it — filtering is a query, so there is no second code path and the field
  shows what is being asked.
- **`SHOTSCRIBE_INDEX`** points the index elsewhere. Without it, trying the CLI
  against a scratch folder writes those files into the real searchable history,
  which is exactly what the sweep tests once did to it.
- Evidence: 76 tests green, 5 new. Through the built CLI against a scratch
  index, `find error` returned the tagged capture and printed
  `[terminal] [error]`, and `~/.shotscribe/index.json` was untouched. The chips
  themselves are compile-checked only — rendering them needs the app running,
  which would put a menu bar item and a folder watcher on the operator's
  machine, so that check waits for them.
