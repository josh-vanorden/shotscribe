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

## 2026-09-11 — The name is a template, not a constant

`Naming.filename` held one hardcoded format. It is now rendered from a
`NameTemplate`, and `NameTemplate.default` spells exactly what ShotScribe has
always spelled — the repo is public, so an upgrade that renamed differently
than yesterday would be a bug. This slice is the engine; the settings pane is
next.

- **The layout carries the separators.** `{date} {time} {title}` by default,
  and `{date}_{time}_{title}` is how somebody gets underscores, so there is no
  separator setting. Styles cover the rest: date (iso / us / compact), time
  (hhmm / dashed / twelveHour), title (asIs / kebab / snake), plus title words
  and a cap. "Summary off" is a layout without `{title}`, not a feature.
- **`{app}` is absent deliberately.** A capture's metadata records its type and
  screen rect, never the app it came from.
- **Validated before it is stored, never at rename time.** `Naming.validate`
  refuses unknown tokens, a layout with no tokens, path-illegal characters, and
  any template whose sample reads as a fresh capture name — that last one is
  the idempotency guard, without which the watcher renames its own output.
  `ShotScribeDefaults` is the gate, and ignores a stored template that no
  longer validates.
- **One settings domain, four doors.** `ShotScribeDefaults` owns the
  `com.joshvanorden.shotscribe` lookup that `ShotScribeModel` used to do alone,
  so the CLI and the MCP server spell names the way the app does.
  `shotscribe name` prints the template in force.
- **`Sessions.stem` was coupled to the old format** — it stripped "10-char
  date, 4-digit time" to title a burst. It now takes stamp-looking parts off
  the front and the back whatever the template spells them as, so a session
  under `{title} {date}` is still titled by its title.
- Evidence: 78 tests green, 20 new. The CLI binary renames a capture to
  `2026-09-11 1704 Screenshot.png` under the default, unchanged. Not yet built:
  the pane, so nothing but `defaults write` can set a template today — and the
  operator's own domain was never written to during any of this.

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

## 2026-09-11 — The settings pane, and the two branches meet

The template engine had been parked since this morning with no way to reach it,
and the tag vocabulary was a shipped constant. Both wanted the same pane, so
`filename-templates` came back onto main first — five conflicts, all of them the
two features touching the same rename path — and then the pane.

- **`Renamer` now carries a template and a vocabulary side by side**, and the
  vocabulary moved out of `Tagging.defaultVocabulary` into
  `ShotScribeDefaults.vocabulary()`, so the CLI, the MCP server and the app all
  file from the same stored list. The MCP tool description lists whatever is
  stored, not the shipped list.
- **A Name block and a File block**, in the shape the Keep block set. Styles
  apply as you pick them — a picker cannot spell an unusable name. The layout
  field and the vocabulary field are drafts with a "Use" button, because
  half-typed text is invalid text. Under the layout sits either the sample it
  would produce or the reason it cannot be used.
- **An empty vocabulary resets to the shipped list** rather than meaning "file
  nothing" — that is a different question, and answering it that way would leave
  no way back.
- **"File as" on a shot's context menu** reaches every capture from before
  today, which the vocabulary otherwise could not: it only applied at rename
  time.
- **Seen, not assumed.** SwiftUI renders off-screen through an `NSHostingView`
  in an unordered window, against a scratch settings domain and a scratch index,
  so the pane could be looked at without putting a menu bar item or a folder
  watcher on the operator's machine. `ImageRenderer` is not enough on its own —
  it leaves AppKit-backed controls (TextField, Picker) blank. Two things the
  render caught: a Date row whose caption just repeated its own picker options,
  and tag chips that were invisible until sessions were switched off, because
  the fixture shots folded into one tile.
- Evidence: 99 tests green, 3 new. The rendered pane shows the sample
  `2026-08-11 1541 AWS Billing Console.png`, all 16 vocabulary tags, and the
  `terminal` / `error` chips on the tile renamed after the dispatch fix — with
  none on the one renamed before it.

## 2026-09-11 — A window and a Dock icon, with the menu bar item kept

ShotScribe was menu-bar-only (`LSUIElement`), so the roomy surface with Keep,
Name, File, search and the tiles had no home outside Toolbelt, and Toolbelt is
pinned to 0.6.1 from GitHub. Josh expected an app like Understand: a window,
in the Dock.

- **A `Window` scene hosting `ShotScribeView(chrome: .hosted)`**, 900 by 860
  by default, plus the `MenuBarExtra` as before. Closing the window does not
  quit (`applicationShouldTerminateAfterLastWindowClosed` is false): a watcher
  that dies with its window defeats the point. Dock click and Spotlight
  relaunch bring the window back.
- **"Open ShotScribe" in the popover footer.** The library cannot open a window
  itself, since it must never know what is hosting it, so `ShotScribeView`
  takes an optional `onOpenWindow` and the app target passes `openWindow(id:)`.
- **The welcome window is gone.** Its job was telling you a menu-bar-only app
  had not vanished; a window does that. Its "install Claude Code" guidance
  already lives in the pane's Claude toggle.
- **`LSUIElement` removed** from the generated Info.plist in
  `scripts/package-app.sh`.
- Evidence: Launch Services reports `type="Foreground"`; a
  `CGWindowListCopyWindowInfo` sweep found the window at 900 by 794, layer 0;
  Josh saw it open to the front. Seen from the app itself: the popover has
  never shown Keep, and now does not show Name or File either; those live in
  the window. Found in the same pass: `claude` was signed out since Sep 10,
  which is why recent titles came from the offline titler.

## 2026-09-12 — The window becomes the product: glass, tabs, gallery

Three preview pages in the browser narrowed the window down (layout, then a
visual pass, then the macOS 26 idiom); Josh locked Glass with captions on
hover, and this is the port into `ShotScribeSurface.swift`.

- **The screenshots get the whole window.** The grid runs edge to edge and
  scrolls under floating chrome: a status capsule (watching, folder), a search
  capsule, and an inspector toggle, all on `ultraThinMaterial` with a lit 1pt
  top edge. The window paints its own background, since a host that draws none
  would otherwise show the grid over nothing.
- **A latest-capture hero** on a band tinted by the capture's own colours
  (the thumbnail, blurred and faded into the window): what it was called, what
  it is called now, its tags, Reveal, Restore name, File as. Only in the
  chronological view; a search or a name sort has no "latest".
- **Groups by day** (Today, Yesterday, a weekday within the week, then the
  date), only under a chronological sort. `Sessions.stem` titles the hero.
- **Gallery tiles**: 4:3, 9pt radius, caption over the image on hover, an
  accent ring on hover, bursts stacked with two edges behind. `AspectThumbnail`
  sizes by ratio rather than a fixed height, from the same QuickLook cache.
- **A tabbed inspector that never scrolls**: Folder, Rename, Name, File, Keep as
  a capsule strip, one pane at a time, floating inset from the window edge on
  glass. Open on Rename on first launch. The amber notice is gone; any state
  worth a word is one quiet line under the toggle it concerns.
- **Tagging is a switch** (`ShotScribeDefaults.taggingEnabled`, on by default).
  Off, the vocabulary dims but stays, and every door files nothing; the CLI's
  `--no-tags` still overrides per run. The vocabulary is removable tags with an
  add field, in a `FlowLayout`, not a comma box.
- **Recent left the window.** Undo is on the hero and on every tile's context
  menu; the list would have been the same information twice. The popover
  keeps it.
- **Found on the way:** `Text.foregroundStyle` on a concatenated `Text` is
  macOS 14+; `foregroundColor` is the 13-floor spelling. The off-screen render
  needs the pane to paint a background and the fixture to keep real creation
  dates (hard links, not copies), or the "latest" is whichever file was copied
  last and every shot folds into one burst.
- Evidence: 100 tests green, 1 new. Rendered off-screen in light and dark
  against hard links of the six newest captures: the real latest up top with
  its `code` tag, Yesterday and Thursday groups, two separate 10:21 and 10:26
  tiles (five minutes apart, three-minute gap), the inspector on Rename showing
  the real stand-down state because ShotScribe.app was running at the time.

## 2026-09-12 — The code bridge: `/screenshot code` and `layout_screenshot`

Josh pointed at `abi/screenshot-to-code` (78.6k stars, since 2023, busy this
summer) and asked what to borrow. Its craft is an agent loop: create once then
edit surgically, extract the screenshot's real assets rather than redraw them,
never embed the screenshot, render the result in headless Chromium and fix what
it sees, evals with a rating UI. Its output is an `index.html` in a browser tab
from pasted API keys. ShotScribe's edge is where the result lands.

- **`layout_screenshot`**, a fourth MCP tool. `OCR.recognizeLayout` returns
  every recognised line with its position (Vision's boxes, turned into percent
  of the image, top-left origin) in reading order: top to bottom, then left to
  right within a row, rows judged by vertical centres within half a line. That
  is the structure half of "extract, don't redraw", done on-device, with no
  pixel leaving the machine. Accurate recognition, no language correction.
- **`/screenshot code [stack]`** in the shipped skill: read the capture and
  its layout, pick the stack from the repo, create once then edit, reference
  existing assets or leave a labelled slot, render and verify before stopping
  (`/preview` for web, the off-screen render for SwiftUI), then the usual
  housekeeping. Credited to screenshot-to-code in the skill and the README.
- **Not borrowed, on purpose:** the model mix and variants (against the
  bring-your-own-Claude stance; `LLMPreference` already reads the machine's
  choice), image generation and background removal, and vision inside the
  watcher (only extracted text leaves the machine; vision stays on demand).
- **Found on the way:** Vision reports pixels, and on a Retina display a
  rendered test image is 2x its point size. The first test asserted points.
- Evidence: 102 tests green, 2 new. A JSON-RPC round trip into the built
  `shotscribe-mcp` listed four tools and returned, for a generated 1400×360
  PNG, one line at `top 44.1 left 3.2 w 69.6 h 14.8  terminal error:
  connection refused`. The skill itself is prose; its first real run is Josh's.

## 2026-09-12 — Screen recordings are captures too

macOS drops `Screen Recording … .mov` into the same folder as stills, and
ShotScribe walked past them: the watcher, the index, the MCP door and the
panel each kept their own list of image extensions, none with a movie in it.

- **One list.** `Capture.imageExtensions`, `Capture.movieExtensions` (`mov`,
  `mp4`) and `Capture.isCapture` replace four copies that had already drifted
  (the index knew no `gif` or `bmp`; the watcher did).
- **Two frames stand in for the file.** `Frames.stills(of:)` takes a beat in
  and the middle, on the older synchronous AVFoundation calls the 13 floor
  still ships; `OCR.frames(atPath:)` is now the one place a path becomes
  images, so labelling, the search index and `recognizeLayout` read a
  recording the way they read a still. The layout uses the middle frame.
- **Recognised by name alone.** `hasEnglishCapturePrefix` adds
  "Screen Recording ". A real recording on this machine (2024, Documents)
  carries no `kMDItemIsScreenCapture` xattr, so the shape-plus-xattr rule
  cannot cover non-English recordings; that is a known gap, same as before.
- **Found on the way:** the narrow no-break space macOS puts before AM/PM in
  capture names bit a shell path I typed with a plain space; `mdfind`'s path
  was the one to use.
- Evidence: 107 tests green, 5 new, three of which write a two-second H.264
  movie with `AVAssetWriter` and read it back through `Frames`, `OCR` and the
  `Renamer` (dry run: `.mov` kept, name from the frames). The built CLI
  labelled the real 49-second recording "Adobe Benefits Membership" with the
  offline titler in 0.63s, without touching it.

## 2026-09-12 — `shotscribe eval`: the folder is the test set

Borrowed from screenshot-to-code's `Evaluation.md` in shape (a fixed set, a
score, runs compared) and not in substance: ShotScribe needs no fixture set,
because every capture already named is a judged answer and its Finder tags a
judged filing. `Evals.cases(in:)` reads them off the folder, raw captures
skipped; `Evals.score` gives exact match, title recall (the share of expected
words that came back) and tag precision and recall; the CLI prints a row per
capture and a summary, and names a titler that never ran rather than scoring
its silence.

- **The first run was a finding, not a score.** Against the newest twelve
  kept names the offline titler scored 92% exact, because those names were
  its own: Claude has been signed out since the 10th, auto-rename kept going,
  and nobody looked. Names like "Progr8Ss User Compl8Ted" had been kept for a
  fortnight. The README says so: the number is a regression check when the
  kept names came from the titler under test, a quality score only when
  somebody judged them.
- **The finding fixed one thing on the spot.** A digit wedged between two
  letters is a misread glyph, never a title word; `KeywordTitler.isOCRNoise`
  drops those, digits at the edges kept ("ec2", "3d", "iphone15"). Re-run:
  exact 75%, recall 90%, and "Progr8Ss User Compl8Ted" now titles as
  "User 1000H Progress". Lower is honest here.
- Evidence: 113 tests green, 6 new. Two real runs of `shotscribe eval
  --no-claude --limit 12` on `~/Pictures/Screenshots`, read-only, before and
  after the filter; and a run with Claude selected reporting "2 of 2 never
  reached the titler: Claude is signed out" instead of a zero.

## 2026-09-12 — `{app}`, read off the capture's own chrome

The one template token the metadata could not supply. A full-screen shot
starts with the menu bar, whose first item after the Apple mark is the app; a
window shot starts with its title bar. `Chrome.app(in:)` reads either off the
positioned lines the fast OCR pass now keeps (`OCR.recognizeLines`), so the
title and the app come from one Vision call. Best effort, and the README says
so: a browser's title bar names the tab.

- **`{app}` is a known token.** Rendered from the chrome, empty when there is
  none, the gap closed by `tidy`. The sample under the layout field shows
  "Safari". A caller that brought its own title (the MCP door, the app) pays
  for the read only when the template actually spells `{app}`.
- **The menu bar was in the titles.** Found by the end-to-end test: the offline
  titler had been reading "Shell Edit View Window Help" along with the body,
  and on a shot whose words all occur once, the first three win. `Chrome.body`
  now hands the titler everything below the chrome when there is chrome; the
  model's own rename path uses it too.
- **Two wrong turns, both caught by the real image, not the synthetic lines.**
  Vision's fast boxes for a 15pt bar are taller than the 4% a 28px strip
  works out to on paper, so the strip filter missed them; and the menu-word
  list had "terminal" in it, so Terminal's own name was read as a menu and
  dropped. The list now holds only words that can follow an app name.
- Evidence: 118 tests green, 5 new, one of them a rendered 1200×700 image with
  a drawn menu bar that comes out as "<date> Terminal Deploy Finished
  Warnings" under `{date} {app} {title}`, no "Shell" anywhere in it.

## 2026-09-12 — Stage two in the app: Rebuild as code, tags drawn as tags, drag-out

Josh, looking at the new window: the tag pills read as buttons ("what does
the terminal button do?"), "code" beside a feature called code read as an
action ("stage two, the user hits code, then what?"), and a named capture
could not be dragged into Mail or Jira from the window.

- **Tags are drawn as tags.** One `TagChip` everywhere: the tag glyph, the
  word, and a hover that says "Filed under code (a Finder tag). Click to see
  everything filed the same way." Nothing in a chip runs anything.
- **Any shot drags out as a copy.** `NSItemProvider(contentsOf:)` on tiles,
  stacks, the hero and list rows, so a drop into Mail, Jira or Slack attaches
  the file the way Finder would.
- **Stage two, as far as the app can take it.** "Rebuild as code" on the hero
  and in every shot's menu copies a self-contained brief for Claude Code: the
  file, its text with positions (the layout read inline, so it works with or
  without the MCP server), and the working discipline. One line under the
  grid says where to paste it: into Claude Code, inside the project the code
  should land in. The agent and the repo live there; the app does not pretend
  otherwise. Chosen over "open a Terminal on it" and over "just say where to
  go".
- Evidence: 120 tests green, 2 new: the brief carries the file, the exact
  strings from a rendered image, and the discipline, and stays plain ASCII
  punctuation since it is pasted into a terminal. The app was rebuilt and
  relaunched; the drag and the paste are Josh's to try.

## 2026-09-12 — Send to Claude: a chosen shot into the session you are in

From the punch list: "send to Claude session". `/screenshot` already did it
from the Claude Code side, but only for the newest capture; the window had no
way to point a session at the shot in front of you.

- **`/screenshot` takes a path.** `skills/screenshot/SKILL.md` (and the
  installed copy in `~/.claude/skills`) read a quoted path argument as *the*
  capture and skip the search; `N` still works, and both work after `code`. A
  `.mov` path goes to `ocr_screenshot`, since Read cannot show a movie.
- **Send to Claude, in the app.** On the hero and in every shot's menu. It
  copies `/screenshot "<path>"` (`SendToClaude.line`) and the line under the
  grid says: paste into any Claude Code session; /screenshot reads this shot
  there. Chosen over launching a session (ruled out with stage two) and over
  copying the image itself (whether the composer would take the image or the
  text from one pasteboard is unknown). Drag-out stays the wordless version.
- The note under the grid became one thing, `HandoffNote` (text and symbol),
  and a brief still reading its layout no longer overwrites the pasteboard
  after a later Send to Claude.
- Evidence: 122 tests green, 2 new: the line's quoting, and that the shipped
  skill documents the exact form the app copies. The app was repackaged at
  18:01; the paste is Josh's to try. The composer taking a pasted
  `/screenshot …` as a command on submit is expected, not yet seen.

## 2026-09-12 — Share, unfolding in place

Josh sent a reel of a share pill that opens into a row of destination icons,
each named on hover, and asked for that. Built natively on the hero: one
**Share** capsule that unfolds into the Mac's own destinations for the file
(`NSSharingService.sharingServices(forItems:)` — AirDrop, Mail, Messages,
Notes, Add to Photos, Freeform on this Mac, the first six of ten), each named
the moment it is hovered, with "More" opening the system picker (`ShareLink`).
Real services with their own icons instead of social logos; the hero's action
row became a `FlowLayout` so an open row wraps instead of clipping. Every
shot's context menu keeps a plain "Share…" that opens the picker.

- `sharingServices(forItems:)` is deprecated at macOS 13 in favour of
  `standardShareMenuItem`, which is a menu and cannot be laid out as a row; it
  still answers on macOS 26, and nothing else enumerates destinations with
  icons. One deprecation warning, on purpose, with the reason beside it.
- Evidence: builds, 122 tests green (none touch the view), the services list
  confirmed from a scratch program against a real capture. The unfold, the
  hover names and an actual AirDrop are Josh's to try; repackaged at 18:35.

## 2026-09-12 — The landing zone: service tiles, and a title you can fix

Josh's screenshot of the window (still the 17:26 build — Share and Send to
Claude were in `dist/` but not in the app in front of him) named two things:
the hero's action icons were cryptic ("poor, they should reflect their service
and have our hover text, simple layout"), and a rename the person does not like
needs a fast fix right there.

- **Tiles.** The hero's actions are one row of 30 pt round tiles, each the
  icon of the service it reaches — Finder's own face, the Share glyph that
  unfolds, Claude's app icon (a glyph if the app is missing), `{}` for the
  brief, a pencil, undo, the tag — each named the moment it is hovered by the
  same `NamedOnHover` bubble the share row uses. No text labels, no tooltip
  delay. `ActionTile`, `TileButtonStyle`, `AppIcons`.
- **Title edit in place.** Click the title (or the pencil) and it becomes a
  field; Return renames the file, Escape puts it back. `Naming.retitled`
  keeps the stamp exactly as spelled and swaps only the words, applying the
  template's joining style but not its word cap. `ShotScribeModel.retitle`
  moves the file (watcher told first), keeps a ShotScribe-named shot's raw
  original for undo and gives a hand-named one its previous name there.
- Evidence: 125 tests green, 3 new on `retitled` (stamp kept, snake style,
  no cap, no-stamp names, empty and illegal titles). The app was repackaged
  and relaunched at 18:59, so the next look is this build; the tiles, the
  bubbles and an actual edit are Josh's to see.
- Later: the `{}` tile became a hammer. Josh: outside engineering nobody
  knows what those symbols are for; "rebuild" is a word everyone has.

## 2026-09-12 — 1.5.0: tagged, notarized, stapled

Josh's number, not 0.7.0: everything since 0.6.1 ships as one release.

- **Version.** `serverInfo` in the MCP server was the last literal (0.2.0);
  it now says 1.5.0 and `CLAUDE.md` says to bump it with the tag. The app's
  version is the tag, as `package-app.sh` has read it since 2026-09-06.
  Tagged `v1.5.0` at `9ddbf8c`, annotated with what the release holds.
- **Shipped.** `APPLE_NOTARY_PROFILE=cockpit-notary ./scripts/package-app.sh`
  (the profile name lives in toolbelt's docs, now in memory too): Developer ID
  + hardened runtime + timestamp, notarized and stapled, app and
  `dist/ShotScribe-1.5.0.dmg`. Apple's log: Accepted for both submissions,
  no Invalid.
- **Evidence for "no error installing":** `stapler validate` passes on the
  app and the DMG; `spctl -a -t open --context context:primary-signature` on
  the DMG says accepted, source=Notarized Developer ID; a copy of the app
  taken out of the mounted DMG and given a Safari quarantine xattr passes
  `spctl -a -t execute` the same way and satisfies its Designated
  Requirement. That is the path a download takes.
- Not done, on purpose: the DMG is local (`dist/` is gitignored). A GitHub
  release on the tag is the distribution step, and publishing is Josh's
  call. Toolbelt still pins `.upToNextMinor(from: "0.6.0")`, which cannot
  reach 1.x.
- Pushed `settings-pane`, `main` and the tag with `MANUAL_PUSH=1` under
  this evening's `/clean-tree`.

## 2026-09-12 — The QA pass, and 1.5.1 out the door

Josh: "an end to end checklist of each feature, a full QA pass, a security
sweep, the go-to-market warnings, then out the door publicly." Run on fresh
release binaries, in scratch folders, with `SHOTSCRIBE_INDEX` pointed away
from the real index and nothing written to the real defaults domain
(checksummed before and after).

**First finding was the pass itself:** `.build/release/shotscribe` was a
Sep 11 binary — `package-app.sh` builds only the menubar product — so the
first run "found" missing tags, an unknown `eval`, and a German capture renamed
without its flag, all of which were the stale binary. It also honoured no
`SHOTSCRIBE_INDEX` and wrote six scratch entries into the real index; they
were scrubbed (backup `index.json.qa-2026-09-12.bak`, 222 entries remain).
Second finding: `cp` copies extended attributes, so fixtures inherited the
capture flag and Finder tags from their originals; `cp -X` is the fixture
rule now (in memory).

**Checklist (fresh binaries):**
- Capture rule: `Screenshot`, `Screen Shot` renamed; user-named refused,
  `--force` renames; `Bildschirmfoto` without the flag refused, with it
  renamed; a collision gets ` (2)`. ✓
- Rename, offline titler, dry-run, template (`name`). ✓
- Tags: written as Finder tags (read back with `xattr -px … | xxd -r -p |
  plutil -p -`: `terminal 0`, `code 0`); `--no-tags` writes none; an
  off-vocabulary tag from an MCP caller is dropped; hand tags are kept. ✓
- Index and search: `SHOTSCRIBE_INDEX` honoured, `find` by text and by tag,
  the real index untouched. ✓
- `eval --limit 3`: scores, moves nothing. ✓
- Watcher: a capture dropped into a watched folder renamed within ~2 s. ✓
- MCP over stdio: initialize (1.5.x, protocol echoed), four tools, OCR,
  layout (86 lines), `rename_screenshot` dry run, refusal of a user-named
  file, unknown tool → -32602, unknown method → -32601, a malformed line
  ignored without a crash, stderr quiet. ✓ Two notes: a non-image path
  answers "no text recognised" rather than "not an image"; a malformed line
  gets no -32700 reply. Both left as they are.
- The window, captured live (`screencapture -l<window>`): hero, tiles, tag
  chips, inspector. Switches looked off in the capture — that is macOS
  drawing an inactive window; `defaults` said on. The tag tile had wrapped:
  the hero's text column is ~252 pt and seven 30 pt tiles need 258. ✗ → fixed
  (28 pt, 6 pt gaps), re-captured, one row. ✓
- Recordings: `RecordingTests` only; no `.mov` in the folder to try live.
- Not exercised by machine: title edit, Share unfolding, hover bubbles,
  drag-out, Send to Claude paste, launch at login, anything with `claude`
  signed in. Josh's punch list in `roadmap.md`.

**Security sweep:** `ClaudeTitler` runs `--strict-mcp-config` and denies
Bash, BashOutput, KillShell, Task, Agent, Read, Write, Edit, NotebookEdit,
WebFetch, WebSearch, Glob, Grep; stdin `/dev/null`, SIGTERM→SIGKILL
watchdog. No network code beyond spawning `claude`; no telemetry; no secrets
or e-mail addresses in tracked files; the log carries names and counts, never
OCR text; hardened runtime on, no entitlements. Two findings fixed in 1.5.1:
the index was 0644 in a 0755 folder (now 0600/0700, tightened on the next
save of an old index), and a title of `../../etc/passwd` kept `..` as a word
(dot-only words dropped). `Triage.md` has both, and the wrap.

**Go to market:** README gained *Before you install — what it touches*,
install from the DMG, a privacy table (index, defaults, log, tags), *Uninstall*,
*Known limitations*; `SECURITY.md` (reporting, the trust boundaries);
`CHANGELOG.md`.

**Shipped:** `v1.5.1` at `e6e96a1`, notarized (4× Accepted, stapled; the DMG
and a quarantined copy of the app both assess as Notarized Developer ID),
published as the latest GitHub release with the DMG attached. 127 tests.

## 2026-09-13 — Bring your own AI: the AI tab, and five tabs still

Josh, first thing: ShotScribe reads as a Claude-only tool, his teammates use
Cursor, Hermes, LibreChat, OpenAI and Gemini, and the inspector's five icons
are the right number. Decision: merge Rename and Name, give the fifth slot to
an **AI** tab, and cover the list with two mechanisms — a CLI the person is
already signed in to, or an OpenAI-compatible endpoint.

- **`AIProvider`** is the one stored choice (`shotscribe.ai`, migrating the
  old "Title with Claude" switch so an upgrade changes nobody's titler):
  offline, Claude Code, Codex, Gemini CLI, Cursor Agent, Ollama, a command, an
  endpoint. `makeTitler()` is the factory every door uses.
- **`CommandTitler`** runs any command with `{prompt}` as one argument
  (instruction + OCR text) and takes the reply's last non-empty line; the
  presets are visible, editable templates carrying each CLI's tool-denying
  flags. `CommandRunner` is the process runner extracted from `ClaudeTitler`
  (stdin `/dev/null`, both pipes drained, SIGTERM→SIGKILL), shared by both.
- **`EndpointTitler`**: one `POST {base}/chat/completions`, the only network
  code in the app; the key comes from the Keychain (`Secrets`, with a
  `MemoryStore` for tests) and never touches the settings file.
- **The tabs**: Folder · Rename (the switch, rename-now, then *Spelling* — the
  template and its pickers) · AI (picker, the kind's fields, an availability
  line, where the text goes, the machine's `provider.json` as a one-click
  suggestion, "Try it on the newest capture") · File · Keep. The popover keeps
  one switch, "Title with AI". **Send to …** follows the assistant (Claude's or
  Cursor's icon; `/screenshot "<path>"` for Claude Code, a plain ask for
  others); the brief's note names the agent.
- **CLI**: `shotscribe ai`; `--offline` (alias `--no-claude`);
  `SHOTSCRIBE_DEFAULTS=<domain>` tries another settings domain, the way
  `SHOTSCRIBE_INDEX` does for the index — every provider trial below used it,
  and the real domain was checksummed untouched.
- **A failing titler is now said out loud.** `Renamer.labelling` swallowed
  errors (`try?` → "Screenshot"); it now reports through `onTitlerError` and
  falls back to the offline name. The CLI prints the note. Found because a
  blocked Codex run printed "Screenshot" instead of an error.
- Evidence: 140 tests green (13 new: migration, lenient decoding, argv
  building, a command as a titler, failure and timeout, the endpoint request
  and reply, availability, the hand-off line, the machine preference, secrets,
  the reported failure). Live through the CLI in a throwaway domain: **Ollama**
  preset titled a capture "Terminal Settings · terminal, settings" in 15 s;
  **Ollama as an endpoint** (`/v1`, no key) answered in 0.8 s; a **custom
  command** and **offline** as expected; **Gemini CLI** missing → visible
  note + offline title. The window captured live: five tabs, the Rename tab
  with *Spelling* under the switch. The AI tab itself, the popover switch and
  "Try it" are Josh's to click.
- **Not verified, and an incident.** The Codex preset was run once and macOS
  refused to launch `/opt/homebrew/Caskroom/codex/0.118.0/codex-aarch64-apple-darwin`
  as *known malware* (cask installed 2026-04-03; the file was removed at
  06:54, not to the Trash). Nothing executed. Codex, Gemini CLI and Cursor
  Agent ship as their documented invocations, editable, unverified here; the
  README says so. Whether that April build was compromised or the verdict a
  false positive is not knowable without fetching it again, which this
  session did not do.
- Later that morning: the picker was rewired (see Triage), and the Send-to
  tile now carries the mark of the titler itself — Josh: "those three are
  really well known and should have their respective logo icons." The marks
  come from Lobe Icons 1.95.0 (MIT collection; the marks stay their owners'),
  rasterised to 256 px through WebKit (`scripts/svg-to-png.swift`: CoreSVG
  dropped Gemini's gradient, Quick Look painted it on white — Josh caught the
  white square), embedded as base64, monochrome ones as templates.
  Offline wears `wifi.slash`, a command `terminal`, an endpoint `network`.
  Verified with `scripts/render-pane.swift`: six snapshots, one per kind.
- Later: "A command" became **Other CLI…**, last in the picker, with one line
  naming who it is for (llm, aichat, mods, a team script). Josh's read of the
  tab: "99% there"; the Gemini mark's white square and edge crop were the last
  visual defect, fixed by the WebKit renderer. The ship list for Monday
  2026-09-14 is in `roadmap.md`; the release notes are drafted. Docs and code
  pushed under the evening's `/clean-tree`; no 1.6.0 tag yet.
- 09:30: the list view had no landing zone — the hero was built only on the
  tiles branch. Fixed (hero first, the newest shot left out of the rows);
  `scripts/render-pane.swift` grew a `HARNESS_VIEW=list` switch to prove it.
- 09:47: **a bin on every shot.** Josh: the tile's upper corner, the landing
  zone, and right of the date in the list. `TrashButton` + `TrashCan`: a drawn
  can whose lid hinges at the right, lifts for the pointer and swings open on
  the click, then the tile scales away before `NSWorkspace.recycle` runs;
  list rows keep theirs faint until hovered. Josh remembered a bin animation
  from "Claude Bridge, Skills" to reuse — no such control exists in any repo
  or surface here (the hub's bin is a plain button), so this one was drawn
  fresh in that spirit.
- 09:58: Josh sent the reel he meant ("Delete Button — The Bin Eats The
  Label"): the letters fly into the bin, the pill furls to the icon, an arc
  turns while the request runs, then seals. Built as `DeletePill`: hover
  unfurls "Delete"; the click flies each letter in on a `GeometryEffect` arc
  (keyframes are macOS 14+) while the can's level rises, furls, turns the
  arc for a beat — the Trash move is milliseconds, so the beat is a floor, not
  a measurement — seals, then the shot leaves. Same control in the tile
  corner, the landing zone and the list row.
- 11:41: **the icon is Josh's.** Five vector directions in a /preview
  (localhost:9012) did not land — symbols of a screenshot, none of the
  naming; the recap and the elevator pitch came out of that conversation
  instead ("Every screenshot, named — the moment it lands"). Josh brought his
  own artwork (`assets/ShotScribe-artwork.png`, 1254 px with alpha):
  `scripts/fit-icon.swift` finds the squircle's edge from the alpha and fits
  it to 824 of 1024, `scripts/make-iconset.sh` builds the iconset and icns.
  The mascot and the old `make-icon.swift` generator are gone.
- 11:51: the tagline — "Every screenshot, named — the moment it lands, by the
  AI you already use, and it stays a file in your folder" — heads the README
  and the first-launch welcome (the empty state: a folder with nothing named
  yet). The README's "welcome window" sentence, stale since the Dock window,
  now describes what first launch does. Rendered off-screen on an empty folder.
- 12:10: a capture named by the watcher stayed off screen until the next
  launch — the model recorded it but never reloaded its cache (Triage). Fixed:
  the window reloads the moment the rename lands. Josh's noon captures were
  the first ones taken without a relaunch in between, which is why it took
  until today to show.

## 2026-09-13 — 1.6.0 shipped, under ShotScribe's own notary profile

Josh at 12:09: "we are set". The number: he said 1.5.0, but 1.5.0 and 1.5.1
were already public, so 1.6.0 — what the CHANGELOG had said all along.
The notary: he wanted ShotScribe's own credential, not the shared
`cockpit-notary`. The "apple dev skill" turned out to be Conduit's
`apple-ship`, whose `credentials` wizard (Touch-ID gated) stores a notarytool
keychain profile named by `apple-ship.config.json`; ShotScribe got that file
(`notaryProfile: shotscribe-notary`), Josh ran the wizard with a fresh
app-specific password, and the profile answered.

- `0a901f6` Version 1.6.0, tag `v1.6.0` on it; two doc/config commits after.
- `APPLE_NOTARY_PROFILE=shotscribe-notary ./scripts/package-app.sh`: Apple
  Accepted the app and the DMG (the profile's first two submissions), both
  stapled. `stapler validate` passes on both; `spctl` on the DMG and on a
  quarantined copy of the app taken out of it: Notarized Developer ID.
- Pushed `settings-pane`, `main` and the tag; published
  https://github.com/josh-vanorden/shotscribe/releases/tag/v1.6.0 with the
  DMG, marked latest. The app in the Dock is that build.
- Still Josh's: keep testing (his words); Toolbelt's pin to `from: "1.6.0"`;
  the announcement (drafted, "secondary").
- 14:17, after the release: **Mark up in Preview.** Josh: "every time we sign
  something we find something" — he opens screenshots in Preview to pencil
  them, and nothing in the window kicked that off. A tile with Preview's own
  icon after Finder on the landing zone, and a line in both menus;
  `NSWorkspace.open(_:withApplicationAt:)` on `/System/Applications/Preview.app`.
  "Restore original name" left the tile row for a link beside the "was …"
  line it puts back, so the row stays one row. Toolbelt's pin raised to
  `from: "1.6.0"` the same hour. For 1.6.1.
- 16:15: **tags as a filter.** Josh, still clicking: no way to sort or isolate
  by tag — a chip click ran a text search for the word. Now `tagFilter` on the
  model (isolate; a second tag narrows, AND), a strip under the grid head with
  every tag in use and its count, and a **By tag** sort that groups the grid
  by filing, a shot under each tag it carries, the untagged last. Rendered
  both off-screen (`HARNESS_SORT=tag`). For 1.6.1.
- 16:30: the tag filter had no way out (Triage) — narrowed to nothing, the
  window showed the first-launch welcome. Now: the strip and a "Show all"
  survive an empty result, the count line links Show all, selected chips wear
  an ×, Esc clears.

## 2026-09-13 — 1.6.1, the same evening: what a day of use turned up

Josh kept clicking after 1.6.0 and each thing he found went straight in:
Mark up in Preview, tags as a filter (with a way out, after the first cut
had none), the bin on a scrim, the window reloading on the watcher's rename,
the list view's landing zone. Then "1.6.1 is ready for the public — we need
a security sweep."

- **The sweep, by hand.** `/security-team` dispatches `claude -p` per track
  and `claude` was signed out all day, so the seven tracks were walked
  manually against the diff since 1.5.1: no secrets or addresses in tracked
  files; no new log line carries screen text ("deleted for good: N file(s)"
  is a count); `removeItem` only under the Keep tab's own choice; argv never
  a shell for the titlers. Two hardenings: a custom command's first token
  must be a plain name (letters, digits, `._+-`) or a path before
  `command -v` runs in the login shell — a pasted setting could otherwise
  have carried a `;` into it — and a plain-http endpoint on a non-local host
  is flagged in the AI tab. Tests for both; 143 green.
- **Shipped.** `1bfc066` Version 1.6.1, tag on it; notarized under
  `shotscribe-notary` (Apple: Accepted for app and DMG, stapled; stapler,
  spctl on the DMG and a quarantined copy of the app all pass). Pushed with
  the tag; published as
  https://github.com/josh-vanorden/shotscribe/releases/tag/v1.6.1, latest.
- **1.6.2 ideas** recorded in `roadmap.md`: a customizable landing zone
  (count each tile's use, hide, reorder, pin) and two coding agents for
  comparison builds. And the skill sweep once `claude` is signed in.

## 2026-09-13, night — the seven-track pass, for real

`claude` signed in (the browser handshake completed on its own), then
`/security-team`. Getting it to run was its own finding: the
`~/.claude/skills/security-team` link points at the registry's unexpanded
source, whose `lib/` wrappers fail when sourced; the deploy helper's expanded
copy at `~/.claude/conduit-skills/library/security-team/` is the working
entrypoint. `DEVELOPER_DIR` had to ride along for XCTest, and the pipeline's
check gate does not know Swift packages, so the suite was run by hand on the
branch (152 green) and again after the merge (154).

Seven tracks, seven passes, twelve surgical commits on
`security/20260913-1829`, all merged into `settings-pane` with four
conflicts resolved (the refusal wins over the warning; their tool description;
both sets of tests). Josh's instruction — "fix any issues uncovered" — also
covered what the tracks deferred to the operator: the key never over
cleartext, `force` for captures only, the terminal as a print boundary, the
backslash in the hand-off line; those four went in on `4a91e04` before the
merge. Left as the operator's call, on purpose: confining MCP OCR to the
watched folder (a feature), pinning the README's skill URL to a tag, CI.
Reports in `docs/security/2026-09-13/`; `SECURITY.md` carries the summary.
- 20:32: Josh, holding the tag: the main window's tiles had no right-click
  (the list rows and the popover did; `GalleryTile` was new and never got
  one), and a click had no configurable default. One `ShotMenu` now backs
  every shot everywhere; `ShotScribeModel.defaultAction` (Reveal, Mark up,
  Send to, Rebuild) is what a click does, set by right-clicking a landing-zone
  tile, shown with an accent shadow and a ✓ in the menu. 154 tests.

## 2026-09-13, late — 1.6.2: the right-click, the default click, and the pass

Josh, holding the tag: "hold the push and tag, until we fix a missing
functionality" — every shot needed a right-click with the landing zone's
functions, and the landing zone needed a way to set what a plain click does.
Built on `settings-pane` and checked by him in three rounds:

- **One menu everywhere.** `ShotMenu` backs the grid tiles (which had none),
  the list rows, the hero's thumbnail and the popover: Reveal, Mark up,
  Share, Send to, Rebuild as code, File as, Restore, then the bin.
- **The default click.** `ShotScribeModel.defaultAction` (Reveal, Mark up,
  Send to, Rebuild; stored under `shotscribe.defaultAction`, Reveal to
  start) is what `click(shot)` performs outside selection mode. Set by
  right-clicking a landing-zone tile; the tile that is the default says
  "Default ✓" instead, and the shot menu marks its line "✓ default".
- **Three rounds on the mark.** First an accent ring on the tile's edge with
  a soft shadow: "you can barely see it in dark mode but cannot see the
  light mode" (Triage 21:10). Then the wording cut to "Set as default" and
  the ring made solid — still a tint on the icon; Josh: "move to the outside
  of the icon circle." So a 2 pt ring 4 pt off the edge with a glow, the
  icon untouched (`ed6f6ea`). Then "change the default selection color to
  green, that is unmistakable" — `ShotPalette.chosen` = systemGreen
  (`b57dca5`). Each round rendered in `.aqua` and `.darkAqua` through the
  harness before he looked; "we're there."
- **Shipped as 1.6.2.** `serverInfo` → 1.6.2, CHANGELOG dated (`69d127e`),
  tag `v1.6.2`; notarized under `shotscribe-notary` (app and DMG Accepted,
  stapled, verified), pushed with the tag via `/clean-tree`, published as
  https://github.com/josh-vanorden/shotscribe/releases/tag/v1.6.2, latest.
  Toolbelt's pin raised to `from: "1.6.2"` and resolved (committed there,
  unpushed, beside the 1.6.0 pin commit). 154 tests.

## 2026-09-14 — 1.6.3: the landing zone arranges, the grid becomes a carousel

A morning of Josh's own calls, each checked in the window before the next.

- **The arrangeable landing zone** (the 1.6.3 idea, built). `LandingZone` in
  Core holds the order, what is put away and the tally; the order is stored as
  names so a tile added later appears instead of shifting the row, hiding the
  last visible tile is refused (right-click is the way back in), and a reset
  keeps the counts because the arrangement is the setting and the tally is
  evidence about it. Arrange mode swaps the live controls for inert faces, so
  the drag has the gesture to itself; the badge alone hides, so a click meant
  as a drag cannot empty the row. 13 new tests.
- **A card fan-out, straightened.** Josh sent a "Cards Fan-Out Animation"
  reference and asked for it without the arch. Six treatments went up on
  localhost:9013 over twelve of his real captures; he picked **Straight deck**
  and the numbers with it. Ported as `DeckRow`/`DeckCard`, then on his word the
  adaptive grid was cut entirely: **Carousel** (default, first) and **List**,
  with `GalleryTile` and `GallerySessionTile` deleted and the stored `tiles`
  mapped onto the carousel.
- **The list got the picture.** Hover shades the row and shows the capture. The
  first cut put the preview in the row's own overlay and reached for `zIndex` —
  wrong, and Josh's screenshot showed why: in a `LazyVStack` the rows built
  afterwards draw straight over it. The list now reads an anchor preference and
  draws one preview in its own overlay, 320pt right of the names, clamped to
  the pane and flipped above the row at the end of the list.
- **First run.** The inspector started open on Rename, and the only welcome was
  an empty state nobody with a used Mac ever sees. Now: a greeting sheet once
  per Mac carrying the folder row and the watch switch, an inspector that
  starts closed and remembers, and **Folder** as its first tab.
- **A red suite that was not ours.** `ChromeTests` began failing on every
  commit, 2e6d9cc included, when the operator moved to 1x displays: the fixture
  was drawn through `lockFocus`, which takes its scale from the attached
  screen, and `OCR.recognizeLines` reads with `.fast` and no language
  correction, where a 15pt label at 1x comes back "Terniinal". The fixture is
  now drawn at 2x like a real capture. Triage has it.
- **The welcome shows once, proven rather than assumed.** Josh asked after the
  release whether it really is show-once. The off-screen harness was run three
  times against one settings domain: a fresh Mac shows the sheet, pressing
  Start writes `shotscribe.greeted`, and the two launches after it show
  nothing. His own Mac already reads `shotscribe.greeted = 1`. The one way it
  returns is quitting with the sheet still open, which is correct — that run
  never finished the setup.
- **Shipped.** `serverInfo` → 1.6.3, CHANGELOG dated, tag `v1.6.3`, notarized
  under `shotscribe-notary`, pushed with the tag, released on GitHub as latest,
  Toolbelt's pin raised. 167 tests green throughout.

## 2026-09-15 — a competitor, then the card it suggested

Josh's shared link drew good feedback, and a friend was pushed
**ScreenSnap Pro** ($39, one-time). Evaluated: it is a capture-and-beautify
tool — backgrounds, annotations, cloud links — and its own About page rules
out naming, organising, searching, tagging and folder watching. Different
shelf, same file. Two of its ideas were worth taking; Josh picked one.

- **The capture card**, built local-only on his instruction. The rename is the
  whole product and it happens in silence, so this is the moment ShotScribe
  has something to say. Six rounds with him at the keyboard:
  - It waited for the title (ten seconds) before appearing. Now `justLanded`
    announces the raw capture and the card is up in about a second saying
    "Naming…", then names in place and widens.
  - The middle button "did nothing": a non-activating panel spends the first
    click raising itself, so the button never saw it. A hosting view that
    answers `acceptsFirstMouse` fixed it, and `acceptsMouseMovedEvents` fixed
    the hover states with it.
  - Thin grey glyphs read as disabled on glass. The marks are Preview's and
    Finder's own icons now — the same answer the landing zone reached in
    September when Josh said its tiles "should reflect their service".
  - "Named" in green text washed out over a bright desktop; it is a filled
    badge now.
  - Two self-inflicted bugs, found and fixed before he saw them: every renamed
    file put up a phantom "Naming…" card that never resolved (the watcher sees
    ShotScribe's own output land, so `justLanded` is gated on
    `Naming.isRawCapture`), and a title slower than the linger let the card
    time out before it had said anything (no countdown runs while unnamed).
  - It also sat open for forty seconds after tagging: a menu takes the mouse
    off the card without SwiftUI reporting the exit, so the hover pause never
    lifted. Anything done from a menu now restarts the linger.
- **Send to swallowed Rebuild as code.** Josh: the two buttons "are really
  doing the same job". Not quite — one says look at this, the other says
  rebuild this as code — but they are one destination, so they are one mark
  with both jobs, the assistant, and the click default under its right-click.
  `LandingZone.Tile` lost `.rebuild`; a stored order still naming it is
  shrugged off by `resolve`, the same way a name from a later version is.
- **Two shipped tag bugs, both traps rather than polish.** A tag could only be
  added — `Tagging.add` merges and every menu disabled what was already on the
  shot — so the first guess was permanent. And emptying the vocabulary put the
  sixteen shipped words straight back, which meant deleting them one at a time
  never finished; the reasoning behind that (never strand the operator) now
  lives in a named **Shipped list** action instead of a side effect.
- **The bin went dead after one delete** (Triage). Reported twice before it was
  understood: `DeletePill` never reset its stage, and a lazy stack hands that
  state to whatever takes the slot.
- **A bin on each day heading**, eating a word that carries the count.
- Verified throughout by driving the real app: a synthetic capture into the
  watched folder, the panel captured by window id, and the test files trashed
  after. `claude auth` had lapsed again and was renewed mid-session; titles
  were confirmed real by the tags a model returns and the offline titler does
  not. 168 tests.

## 2026-09-15, evening — 1.6.4 shipped

`serverInfo` → 1.6.4, CHANGELOG dated, tag `v1.6.4` at `4bf74b0`; notarized
under `shotscribe-notary` and verified four ways (stapler on app and DMG,
`spctl` on the DMG, a quarantined copy out of the DMG through Gatekeeper —
Notarized Developer ID). Pushed with the tag, published as latest:
https://github.com/josh-vanorden/shotscribe/releases/tag/v1.6.4 — Toolbelt's
pin raised to 1.6.4 and the belt built against it. 168 tests.
- `gh release create` failed first time: `gh` was active on the **work**
  account (`jvanorden-it`), whose token lacked the scope. `forge auto` switched
  it to the personal one and the release went straight through. The machine-wide
  rule already says to run `forge auto` before acting on a repo's remote; this
  is the first time it has actually bitten here.

## 2026-09-16 — the editor, from a competitor's shelf to Josh's

The morning's requirement, in his words: "No Git push until the end of the
run." Everything below was built, tested and shown to him before a single
commit; this entry is the one save.

- **The backlog sweep**, first. `Backlog.pending` finds what is still called
  `Screenshot …`; `propose` names it; the model runs three at a time, each row
  approved or dropped; `applyBacklog` renames under `watcher?.ignore` so the
  rename does not come back as a new capture. Josh: "I am good with the current
  state and old shots remaining untouched" — built, his to run.
- **The watcher was re-titling ShotScribe's own output.** The log showed 257
  titler calls for files the name check would refuse a moment later: `rename`
  ran OCR before `isRawCapture`. Reordered; the wasted work is gone.
- **Edit the Image** (`ImageEditor.swift`, `EditStore.swift`, `Editor.swift`),
  in eight rounds with him at the keyboard, each a report from the app:
  - "The pixel mute is larger than it really needs to be" — per-tile averages
    over a three-tile span, block size a fifth of the short side.
  - "Unable to edit any of the added items" — marks were baked in on mouse-up.
    A mark is now a value with an identity; the picture is flattened on Save.
  - "Layering is an issue… you cannot put a label over any part of it" — the
    one press rule (`EditorPress`): a visible handle resizes in any tool, a
    drawing tool always draws, only Select picks up.
  - "Once an image is saved no edits" — `EditStore`: the untouched base and
    `edit.json` under Application Support, linked by an xattr on the file;
    redactions burned into the kept base so Revert is honest.
  - Frames with sliders and his palette (scarlet, vivid yellow, sage, sand,
    frost, sapphire, cream, forest, tiffany, dark grey); combos; **+** for his
    own by hex or wheel; a picture of his own behind the shot.
  - Steps that count up, five badges (the `>>` chevron was "one of my
    favorites"), the flag reshaped twice; five sizes, then "make it a size
    slider. Makes it much easier."
  - Crop and resize, both reversible in the kept edit.
  - "Our default color for all adjustments should be Black then white, then
    color." Done; the highlighter keeps its own yellow, since a black wash dims.
  - "Why does the blackout not allow for another color selection?" No reason
    beyond my call. It takes one, opaque whatever the colour.
  - The arrow's middle handle: "macOS added… a middle pin to allow you adjust
    the bend." One pin, a quadratic through it, snaps straight when dragged
    back to the middle; edits saved before it decode straight.
- **Watermark, fonts, set-once** (`Watermark.swift`, `TextFont.swift`). Words
  or a logo; corners, centre, tiled; ink on Auto samples what is under it and
  sets white or near-black with a halo of the other; logos become silhouettes
  through their alpha — or, after "made a shaded box", through their shape
  keyed off the edge colour, since his logo was on an opaque white square.
  Fonts: the system designs plus every installed family; a missing one stands
  down. **Use on every edit** stores the watermark in defaults and starts each
  fresh edit with it.
  - Two of his reports were mine to own (Triage): the logo never loaded into
    the preview because its loader hung off the *Frame* panel's view, and Save
    sat grey for a watermark-only edit because the watermark was not counted
    as a change. The footer says **Done** now when nothing would be written.
  - Caught by the tests before he saw it: CoreText draws black unless the
    attributed string carries `kCTForegroundColorFromContextAttributeName`,
    so the ink chosen after sampling was never used.
- **Light or dark.** "We have no way of shifting the app… we should add a small
  single clickable flip icon." A moon in the light, a sun in the dark, on
  `NSApp.appearance`; right-click follows the Mac again. Kept in defaults.
- Everything looked at off-screen first (`steps`, `bend`, `wm-*`, `flip-*`
  renders in the session scratchpad) and then in the running app, which was
  repackaged and relaunched after every round. 229 tests.

## 2026-09-16, afternoon — 1.6.5 shipped

`serverInfo` → 1.6.5, CHANGELOG dated; the day's work committed in five groups
on `settings-pane` (engine, backlog, the face, appearance, release), promoted
to `main`, tagged `v1.6.5` at `e1b1bea`. Notarized under `shotscribe-notary`
(Apple: Accepted, app and DMG) and verified four ways — `stapler validate` on
the app and the DMG, `spctl` on the DMG, a quarantined copy out of the DMG
through Gatekeeper (Notarized Developer ID) — with the bundle reading 1.6.5.
Pushed with the tag and published as latest:
https://github.com/josh-vanorden/shotscribe/releases/tag/v1.6.5 (4.4 MB DMG).
Toolbelt's pin raised to 1.6.5, built once against the tag, committed there
(`1fc1bf4`) with only the shotscribe hunk of its `Package.resolved`; that repo's
five pin commits stay unpushed, Josh's call. `gh` was on `Chief-Tsunami`, which
holds push and admin on the repo, so the release went through first time.
229 tests.

## 2026-09-17 — the audit stamp, and the menu in order of who does it

Josh, from the watermark panel over a JumpCloud erase result — the kind of
picture that ends up in an audit binder: "add my name and a date / time as an
option here… like a docusigned timestamp I think is the audit option I would
want here." He will bring what this year's ISO audit asks for.

- **`Watermark.Stamp`** (`Watermark.swift`): a third kind beside words and a
  logo. Name (the Mac's logged-in full name by default), Captured (the file's
  creation date), Attested, Mac, SHA-256 — each a flag. The values are filled
  by whoever draws: the editor for its preview (attested "now"), and
  `EditStore.commit` for the file, so the picture carries the moment it was
  saved. The digest is `ImageEditor.pixelDigest` — SHA-256 over width, height
  and every pixel as 8-bit sRGB — so it is the same for any lossless copy
  whatever encoder wrote the file; it is of the picture the edit started from,
  labelled `original` or `as kept`. Drawn as a plate: a card the opposite of
  the ink, edged in it, a bar down the left in the accent, the title in the
  chosen face and the details in mono so the columns line up. Times spell
  their zone, since an auditor reads them somewhere else.
- Not built, said so: Preview's drawn signature (a scribble proves nothing to
  an auditor); anything for recordings; and a `shotscribe digest <file>`
  command, which is the natural companion since only ShotScribe can recompute
  the pixel digest today.
- **"Edit the Image" is "Edit with ShotScribe"** everywhere it is shown, and the
  shot menu runs ShotScribe's own → the Mac's → the bin. Josh: "I like it."
- Three tests: the stamp filled at commit and kept with the edit, a stamp that
  asks for nothing is empty, and the digest survives a PNG round trip while
  noticing one changed pixel. 232 tests; rendered off-screen (`wm-stamp`) and
  relaunched.

## 2026-09-17, afternoon — 1.6.6 shipped

`serverInfo` → 1.6.6, CHANGELOG dated, tag `v1.6.6` at `9a579bb`, pushed with
both branches. Notarized under `shotscribe-notary` (Apple: Accepted, app and
DMG) and verified four ways — `stapler validate` on app and DMG, `spctl` on
the DMG, a quarantined copy out of the DMG through Gatekeeper (Notarized
Developer ID) — bundle 1.6.6. Published as latest:
https://github.com/josh-vanorden/shotscribe/releases/tag/v1.6.6 (4.5 MB DMG).
Toolbelt's pin raised to 1.6.6, built once against the tag, committed there
(`1e6bbc1`, shotscribe hunk only); six pin commits now unpushed there, Josh's.
232 tests.
- `gh release create` was refused the first time — `gh` had drifted back to
  the work account (`jvanorden-it`) since yesterday's `forge auto`, exactly as
  at 1.6.4. `forge auto` immediately before the release, every time, not once
  per session.

## 2026-09-18 — The README becomes a landing page
The README was well-written documentation in the place an advertisement should
be: 425 lines, no picture anywhere, a 26-word average sentence, and "what it
touches" as the first section, ahead of what the app does. Rewritten as a
landing page (194 lines): icon, pitch and badges, a real app shot by line 31, a
before/after filename table, install by line 59 with a dry-run command under
it, a four-box pipeline that says where the data goes at each step, a features
table, and "what it touches" kept as five bullets with its opening line intact.
The reference moved verbatim into nine files under `docs/` (cli, naming,
titlers, mcp, app, hosting, privacy, uninstall, limitations), sliced by heading
with a check that every source line landed; the one rewrite is the Menu bar app
section, a 151-word sentence that is now five paragraphs. Four images went into
`assets/readme/` from the 09-18 brag captures (real app, fictional Halyard
data). Fixed on the way: the intro still called the MCP server and the menu bar
app "next". The star badge carries no count while the count is 0. Not done, by
decision: the GitHub About box (description and topics are drafted; it is public
content and waits for a yes), CONTRIBUTING.md, and a Pages site. Nothing is
committed.

## 2026-09-18 — The release is arm64 only, and now says so
Found while checking a generated landing page's claim of a "universal binary":
`lipo -archs` on the app inside `ShotScribe-1.6.6.dmg` answers `arm64`, and
`package-app.sh` builds for the host architecture only. Neither the old README
nor the new one told an Intel owner the download would not launch. The Install
section now says it needs an Apple silicon Mac. Open question for Josh: keep it
arm64 and say so, or build universal (`swift build --arch arm64 --arch x86_64`).

## 2026-09-18 — Universal build, and a site
Josh's call on the arm64 question: build universal. `package-app.sh` builds
`arm64` and `x86_64` separately and joins them with `lipo` (both `--arch` flags
at once would hand the build to XCBuild and move the products), then
`-verify_arch` stops the ship stage if a slice is missing. Verified without a
release: the script ran into a throwaway output because ShotScribe.app was
running out of `dist/` at the time; the result was `x86_64 arm64`, Developer ID
signature valid, 22 MB against 12. The Intel slice was then executed, not just
inspected: the CLI ran under Rosetta, and the whole suite passed there, 232
tests and no failures (`swift test --arch x86_64` cannot do this, since its
helper launches as arm64; `arch -x86_64 xcrun xctest <bundle>` can). 1.6.6 on
GitHub is still arm64, so README and site keep saying "Apple silicon" until the
next release; three `release-fact` markers find the spots.

The site: Josh ran the landing-page prompt through Google Stitch by hand. Its
design system was kept (tonal surfaces and Material roles grown from `#725DBA`,
the type scale, a Finder window with a before/after switch). Its copy was not:
25 inventions, among them Secure Enclave attestation, App Sandbox entitlements,
a universal binary, a SQLite index, two MCP tools that do not exist, and
Stripe-format keys written into the page as text. Every claim now on the page
comes from the README or the source. `docs/index.html` is 37 KB with four images
in `docs/img/`, which the README shares. Committed on a branch cut from `main`,
so the settings-pane work in progress stayed out of it, and pushed on Josh's
word, to be served by GitHub Pages from `main` `/docs`.

## 2026-09-17, evening — /simplify over the editor, and two capsules that do something
Four cleanup reviews (reuse, simplification, efficiency, altitude) of the
1.6.5–1.6.6 diff, deduplicated into one commit (`992004f`, −487/+440): one
`KeptPictures` store with a cached decode behind backgrounds and logos, so both
loaders and the `onChange` hooks that fed them are gone; `bitmap`/`overlaying`
behind every render; `drawBackground(upright:)` and `drawShadow` drawing the
frame for the file and the canvas alike; `LastAnswer` for the three identity
caches, released when the last editor window closes; `Xattr`; `Capture.takenAt`.
The base picture was being resampled at `.high` on every paint — it is now
resampled once per scale (`ScaledPicture`), and rebakes no longer stack per
mouse event. Skipped as rewrites: `EditDocument` as the editor's state, a panel
enum, `Watermark.content` as an enum. Renders before and after match.
- Josh: the status capsule "needs to be clickable so the user can set a new
  folder, I want a similar button for Tag there too." Both are menus. The first
  render lost the dot and the folder name: a SwiftUI `Menu` label on macOS is a
  button title and keeps only text, so each label is one concatenated `Text`.

## 2026-09-18 — Dock, menu bar, or both; and the panel becomes a menu
Josh's brief, discussed before any code: user-selectable Dock / menu bar
presence, a tray menu in order of purpose, upgrades unchanged. What the repo
said first: the Dock icon was nobody's code (no `LSUIElement` in the generated
plist), the "tray menu" was a 340pt `.window`-style panel repeating the
Library's inspector, and the public version was 1.6.6, not 1.6.3.
- **`Presence`** (Core): dock and menu bar, never neither — the guard is in the
  type, so every door gets it; a key never stored is on, which is the whole
  migration. Six tests.
- **`LSUIElement` is true** and the app promotes itself to a Dock app in
  `applicationWillFinishLaunching`. The other direction flashes a Dock icon on
  every menu-bar-only launch. Cost, stated: Dock users lose the launch bounce.
- **The Library is the app's own `NSWindow`** (`HostedWindow`), not a SwiftUI
  scene: a scene opens itself at launch and only from inside a view, and the
  card, the Dock, the menu and a relaunch all have to open it — and it must
  stay shut on a silent launch. It adopts the old scene's saved frame once;
  the first attempt lost it, because `setFrameAutosaveName` re-applies whatever
  is stored under the new name.
- **`ShotScribeMenu`** lives in `ShotScribeUI` (it needs the model's internal
  actions) with Library, Settings and Quit handed in by the host. Josh added
  two items in discussion: the last capture into the editor, and **Watermark ▸
  Apply / Remove** — `EditStore.setWatermark`, no editor, a kept edit's marks
  untouched.
- **"The Library now opens from the menu bar."** — a line in Settings and a
  callout under the icon. macOS 26 hosts every menu bar icon in Control Center,
  so no outside probe can see ours; in-process `NSStatusBarWindow` still has
  the true frame, one per display.
- Verified on the packaged binary against a scratch settings domain (watching
  off): each launch mode's policy and window, reopen in menu-bar-only, the
  impossible both-off state. The live toggles, the line and the pointer were
  Josh's to test: "Everything works from my end." 238 tests.

## 2026-09-18, afternoon — 1.7.0 shipped, the first universal release
`serverInfo` → 1.7.0, CHANGELOG dated, the three `release-fact` markers flipped
to "Apple silicon and Intel". Committed in four groups on `settings-pane`
(presence, the menu, the capsules, the release), `main` fast-forwarded — it had
moved on its own that morning with the landing README and the site, merged in
here — tagged `v1.7.0` at `18ede21`, pushed. Notarized under `shotscribe-notary`
(Apple: Accepted, app and DMG) and verified four ways, plus the one that is new:
the app *inside the DMG* answers `x86_64 arm64` to `lipo -archs`, version 1.7.0,
`LSUIElement` true. Published as latest:
https://github.com/josh-vanorden/shotscribe/releases/tag/v1.7.0 (7.3 MB, up from
4.5 — two slices). `forge auto` immediately before `gh release create`; gh was
already on the right account this time. Toolbelt's pin raised to `from: "1.7.0"`
— a minor bump `.upToNextMinor(from: "1.6.6")` could never resolve — built once
against the tag, committed there (`b0c05f3`, shotscribe hunk only); seven pin
commits unpushed there, Josh's. 238 tests.

## 2026-09-18, later — the old menu bar panel comes out of ShotScribeUI
Josh asked what "remove the old panel" referred to, then: "remove it." The
340pt popover (`ShotScribeChrome.menuBar`, the `panel` view and the five helpers
only it used, `ShotScribeView`'s `onOpenWindow:`) had no caller left: the app
shows `ShotScribeMenu` since 1.7.0 and Toolbelt mounts `.hosted`. The enum and
the `chrome:` parameter stay, with one case, so a host's
`ShotScribeSurface(chrome: .hosted)` reads the same. An API removal, so it is
in the changelog under Unreleased as Removed. 238 tests; the Library renders
as before.

## 2026-09-20 — interrupted renames are retried, and named properly

Built through claude-kit's `/plan` then `/ship`: six commits, `edf272b` to
`995ef6b`, suite 242 to 250, green throughout.

- **A rename records itself as in flight** (`Sources/ShotScribeCore/InFlight.swift`,
  `Renamer.swift`). `InFlight.begin` before the slow OCR-and-title work,
  cleared in a `defer` on every outcome, so a capture the app was still
  renaming when it quit leaves a trail rather than silently joining the backlog.
- **Both watch starts retry it.** `Backlog.retryInFlight` existed after the
  first pass and **nothing called it** — `grep` found only its own definition.
  The app now calls it when `startWatcher()` arms (both doors into watching go
  through that one function) and the CLI calls it in `case "watch"`.
- **The CLI nearly shipped crashing.** A bare top-level `await` in
  `Sources/shotscribe/main.swift` makes the top level suspend, after which the
  trailing `dispatchMain()` traps: `shotscribe watch` died at startup on every
  run while `swift build` and `swift test` stayed green, because nothing tests
  that file. The retry runs inside a `Task` instead, and the watcher still arms
  **before** it: `FolderWatcher.start()` seeds `seen` from the folder, so
  arming afterwards silently loses any capture that lands during the retry
  (measured with 40 in-flight records — the dropped capture was never mentioned
  across 75 seconds).
- **A retried capture is named by the configured titler.** It was landing with
  the offline keyword name: `rename(_:)` composes the AI title itself and hands
  it down as a *label*, and `Renamer`'s own `KeywordTitler` is only the fallback
  for when that label is nil — which is exactly how `retryInFlight` calls it. A
  `titlerOverride` seam lets a test prove which titler named the file.
- **Titler presets say which are verified.** `docs/titlers.md` now states, per
  preset, a real run or an honest unverified note. Codex is **not installed on
  this Mac** despite Homebrew listing it: `/opt/homebrew/bin/codex` exists and
  its symlink target is gone. Gemini CLI and Cursor Agent are absent too.
- **Verified:** 250 tests, 0 failures, on the exact commit promoted to `main`.

Also 2026-09-20: `settings-pane` was promoted to `main` and retired, along with
the fully merged `security/20260913-1829`. This repo is single-branch now.

## 2026-09-21 — the landscape audited, and 1.7.1 shipped
Josh asked that the weekend's work be captured and that the repo, the DMG and
his local deployment all match. Read-only first:
- **Repo:** clean, `main == origin/main`, single-branch since Sunday, 250 tests
  green at HEAD. The retry feature was in History, Context and Phase but **not
  in the changelog** — added.
- **DMG:** GitHub's `ShotScribe-1.7.0.dmg` and the local one share a SHA-256, so
  the download was exactly what was built — and six code commits behind `main`
  (Friday's panel removal, Sunday's retry work).
- **Local deployment:** the running app was Friday 16:34's build, older than the
  retry commits. And Claude Code's registered MCP server did not exist:
  Friday's universal packaging built x86_64 last, so `.build/release` pointed at
  the Intel folder, which has no `shotscribe-mcp`; the arm64 CLI and MCP
  binaries dated from 16 September. `package-app.sh` now builds the host's
  slice last. Everything rebuilt from HEAD and relaunched.
On his word, **1.7.1**: `serverInfo`, CHANGELOG dated, tagged, notarized under
`shotscribe-notary`, published. The research-driven work that ".1" had been
reserved for is now 1.7.2 (`roadmap.md`). The release's verification and link
are in the commit after this one.

## 2026-09-21, later — 1.7.1 is public, and the three match
Tagged `v1.7.1` at `e759b7e`, notarized under `shotscribe-notary` (Apple:
Accepted, app and DMG), verified four ways plus the two that the universal
build added — the app inside the DMG answers `x86_64 arm64` and reads 1.7.1 —
and published as latest: https://github.com/josh-vanorden/shotscribe/releases/tag/v1.7.1
(7.2 MB). The packaging fix held on its first real run: after both slices were
built, `.build/release` still pointed at the host and `shotscribe-mcp` was
still in it. The local CLI and MCP server were rebuilt after the bump and the
server answers 1.7.1; the running app is the notarized 1.7.1 out of `dist/`.
Toolbelt's pin raised to 1.7.1, built against the tag, committed there
(`7994e97`, shotscribe hunk only); eight pin commits unpushed there, Josh's.
250 tests.

## 2026-09-22 — the picture goes to the chat, the path stays on the Mac
Josh's note from a night of building: Send to Claude put a `/screenshot
"<path>"` line into a claude.ai chat, whose container has never seen his disk,
so nothing arrived. Two destinations now, named by what they can see: **Send to
Claude Code** (the line, for a session on this Mac) and **Send the picture to a
chat** (`SendToClaude.picture`: PNG data, the file URL, the file's name — never
its path — on one pasteboard item, so ⌘V in claude.ai, the Claude app or any
web chat attaches the image). Offered wherever Send to is: the landing zone's
tile and its click-default menu, the capture card, every shot's right-click. A
recording says so rather than pretending. Verified by driving the real model
against a copy of a capture and reading the general pasteboard back (his
clipboard saved and restored around it): the path form carries text only; the
picture form carries `public.png` at the capture's size, `public.file-url`,
and `src.png` as the text. 251 tests. Triage has the entry.

## 2026-09-22, morning — 1.7.2 shipped; the Gap run on the 1.7.3 candidates
On Josh's word: the roster approved (six competitors, four lenses, the five
research candidates as proposed decisions) and the four collection agents
dispatched in parallel; `serverInfo` → 1.7.2, CHANGELOG dated, the release
notes drawn from it, tagged, notarized under `shotscribe-notary`, published,
Toolbelt's pin raised. `main` had not moved since 1.7.1, so the push is a plain
fast-forward — checked with `merge-base --is-ancestor` first, as the 2026-09-18
memory says to. Verification and the release link are in the commit after this.

## 2026-09-22, later — 1.7.2 is public
Tagged `v1.7.2` at `d5d9ee8`, notarized under `shotscribe-notary` (Apple:
Accepted, app and DMG), verified four ways plus the universal check (the app
inside the DMG is `x86_64 arm64`, version 1.7.2), and published as latest:
https://github.com/josh-vanorden/shotscribe/releases/tag/v1.7.2 (7.2 MB). The
local CLI and MCP server rebuilt after the bump and the server answers 1.7.2;
the running app is the notarized 1.7.2 out of `dist/`; `.build/release` still
holds `shotscribe-mcp` after packaging, so the 2026-09-21 fix holds. Toolbelt's
pin raised to 1.7.2, built against the tag, committed there (`30d2688`,
shotscribe hunk only); nine pin commits unpushed there, Josh's. 251 tests.

## 2026-09-22, mid-morning — small print
Josh's org chart came back "Screenshot". Not the titler and not the sign-in:
the fast OCR pass read 75 characters of noise off five-pixel names, and a probe
on the same file showed `.accurate` reading 868 real characters in 0.2 s. The
engine now falls back to the accurate level when the fast pass reads next to
nothing from a picture big enough to hold more (`OCR.sparseChars`,
`OCR.sparseArea`); the fuller reading is kept. `shotscribe label` on the chart:
"Company Org Chart". 253 tests; Triage has the entry.

## 2026-09-24 — naming in four seconds: hooks off, no session saved
Josh: "the OCR rename takes quite a bit of time." Measured before touching
anything, the titler's exact call on one real capture, sent from `/` as the
app sends it: as it was, 8.6–27 s wall with the model answering in 1.9–2.4 s;
with the user's hooks off, 4.0–4.4 s; with user settings skipped entirely,
2.9–4.9 s. Same title every run. Flag by flag, `--setting-sources project`
alone did it, and `disableAllHooks` alone did nearly as well — the hooks were
the wait, not the model, and not Claude Code's own prompt. Skipping user
settings was rejected: some users keep their auth there. Haiku was ruled out
on the numbers, the slowest model that day at 8–20 s of model time; Sonnet and
Opus answered in 1–2 s. `--bare` needs an API key, so it is out for OAuth.

`ClaudeTitler.arguments(prompt:system:model:quiet:)` now adds
`--settings {"disableAllHooks":true}` and `--no-session-persistence`; a CLI
that answers "unknown option '--…'" is asked again without them
(`rejectedAFlag`), never on a reply in the result envelope. The second flag
answered a finding: 457 transcripts in `~/.claude/projects/-/`, one per title
since 2026-08-16, each holding a screenshot's text — left in place, Josh's to
delete. Three tests in `ClaudeTitlerTests`; 285 in all. Live: the CLI titled
three captures in 4.5–4.8 s end to end with no new transcript; the running
app read a raw-named copy of yesterday's alert at 11:49:44 and named it at
11:49:48, against 12 s for the same shot the day before. Copy removed.

## 2026-09-23, afternoon — the consistency pass, the headline rule, and the ceiling
Josh: "do the consistency pass and the headline rule", plus a timer bug
another session had Codex find. Three pieces, one measured.

**The prompt.** `TitlerPrompt.rules`, shared by the plain and the tagged
prompts: prefer the screen's own words, name the subject rather than the app
or a person, no kind-of-picture words unless on screen, no slide numbers, the
plainest reading wins. The first draft said "never a synonym" and "put the
app first", and the measurement caught both: "Suspicious Login Alert" became
"Google Workspace Suspicious", so "app first" went; "Slack Channel Rename"
became "Ksenia Kampf", so literalism was softened to "when the screen names
nothing, say what it shows". `LabelCleaner` turns "&" into "and" before the
word cap. **Measured as self-agreement**, the same 25 captures run twice,
because the eval's other number is confounded: the kept names are the old
prompt's own phrasing ("Agent … Slide"), so any change of style loses
against them by construction — the old prompt scores 60% recall against
them, the new 45–47%. Run to run, old prompt 16 of 25 identical titles, new
20 (case-insensitive, as the eval compares). The five that still vary are
screens with no name of their own: a Slack rename, a ticket board, an org
chart, a maps app menu, a tmux pane.

**The headline rule.** `Titler.labelling(for lines:vocabulary:)`, a protocol
requirement with a default (the static-dispatch trap again), so the offline
titler can see where the words sit. `KeywordTitler.headline(in:)`: the
tallest line with letters in the top 60% of the picture, clearly taller than
the median of the rest of the page, joined with the rest of its row, a
leading number dropped, title-cased with short acronyms kept. Every door
with lines in hand passes them — `Renamer`, the model, `Backlog`, the eval.
Offline recall against kept names 30% → 37%; the numbered slides go from
"Goal Agent Max" to "Loop Engineering". Two flaws surfaced on the way and
are in Triage: a slide's number rode into the title, and one slide's title
was being stripped as a menu bar by `Chrome.app` (a 5%-tall line starting at
19% fit the bar rule; the app's name starts within the leftmost tenth, so
`left < 12`, and a title-bar line must be bar-sized). `HeadlineTests`, nine
cases, including the existential dispatch and the chrome case.

**The ceiling.** `armCeiling` returns while a drag is under way, so a name
landing mid-drag cannot start the forty-second stop; the drag's end arms it
again. Triage has the entry, with the open question about a hidden card's
drop left open on purpose. 282 tests. App rebuilt and relaunched with all of
it; the old-prompt baseline was built from the last commit in a worktree.

## 2026-09-23, midday — the eval, and a title thrown away for an exit code
Josh: "run the eval… can it work better if the user connects AI, of course."
`shotscribe eval --limit 25` twice against the 25 newest kept names in the
folder, Claude signed in: with Claude, exact 36%, title recall 60%, tag
precision 66%, tag recall 81%, in 3:58 (about 9.5 s a shot); offline, exact
8%, title recall 30%, tag precision 33%, tag recall 17%, in 3 s. So yes:
connected, the names are twice as close and the filing four times, and the
offline titler's misses are word salad ("Chief Director Contracto", "Green
Over Gold") where Claude's are alternative phrasings ("Harness Engineering
Diagram" for "Harness Engineering Slide"). The goal card's gate is 80%; the
kept names are mostly the titler's own earlier answers, so exact-match
measures self-consistency as much as quality — read the recall.

The log beside the eval had the finding that matters: two renames in three
days took the offline name although Claude had answered. `titler FAILED:
failed("IT Support Tickets | ticket, dashboard")` — the failure's reason was
the answer. `ClaudeTitler.complete` took a non-zero exit as the verdict and,
with stderr empty, threw stdout as the reason. The CLI prints its reply and
then, now and then, exits non-zero; a plain run exits 0, so the cause is
downstream of the answer and not the app's. The reply is now asked for as
JSON and read from the envelope (`ClaudeTitler.answer(out:err:status:)`):
`result` when `is_error` is false, whatever the exit status; an error
envelope fails in its own words; anything that is not the envelope — a CLI
that ignores the flag, the plain "Failed to authenticate" on stdout with
exit 1 — is judged the old way. `ClaudeTitlerTests` pins the five cases; the
eval's own fallback literal is `LabelCleaner.generic` now too. Triage has the
entry.

## 2026-09-23 — the capture card: naming you can see, a name in colour, a tile you can drag
Josh's spec for 1.7.3, four changes to the card that slides up after a
capture. (1) While the title is being written the card moves: three dots
breathe on the badge and a band of light crosses the place the name will take
(`PulsingDots`, `Shimmer`), instead of a still "Naming…". (2) When the name
lands it fades in, in green — `ShotPalette.named`, a step darker than the
system's in light so it holds on glass, a step lighter in dark. A shot that
got the generic word is set in grey under a badge that says "Nothing to
read". For that the model now says which is which: `NamedCapture.generic`,
computed from the label it passed; on a titler failure the model takes the
offline label itself from the text it already read (`KeywordTitler`), rather
than leaving `Renamer` to read the picture a second time to get it, and the
one word every titler falls back to is one constant, `LabelCleaner.generic`,
in place of seven literals. (3) The tile keeps its picture through the
rename: `CaptureCardState.image` is loaded once when the capture lands and
never reloaded by path — `AspectThumbnail` keyed on the path went blank for a
beat when the path changed under it. (4) The tile is a drag source: `DragTile`,
a real `NSView` with a real `NSDraggingSource`, puts the file URL on the
pasteboard (`NSURL`, so Finder copies it and a browser's upload field, Slack
and Jira take the file — never the pixels), shows the tile itself as the drag
image, is copy-only so a Finder drop cannot move the file out of the folder,
and reports the drag's start and end to the presenter, which holds both the
linger and the forty-second ceiling for as long as the drag lasts. First
built draggable only once the name had landed; Josh dragged while it was
still naming, the tile refused, and the release fired the click instead
("clicking the tile opens preview… it does not allow me to drag"). With
naming at five to sixteen seconds that is the common case, so the tile now
drags from the moment the card appears and the file URL is *provided when
the drop reads it* (`NSPasteboardItemDataProvider`), from the URL as it is at
that moment: picked up raw, delivered renamed if the name landed first. The
log says when a drag began and where it went.

Chosen from renders, not by taste: `scripts/render-card.swift` hosts the real
card off-screen in both appearances and its three states over a busy desktop,
with a row of candidates on the card's glass. Green and gold both read in
both modes; green is the one signal with the green "Named" badge, gold a
second accent saying the same thing. One harness gotcha worth its comment:
`.ultraThinMaterial` does not blur in `cacheDisplay`, so the harness paints
the blurred, tinted patch the material would.

Nine tests in `CaptureCardTests`: the generic word is the one every titler
falls back to; a real title is not generic, the generic word is flagged, a
failing titler gets the offline name and keeps the error; the tile writes a
file URL and no PNG to the pasteboard; not draggable until named; a press
becomes a drag only once it has moved; the state keeps its picture through
the rename; and, driven through the watcher, only the raw capture is
announced as landed — ShotScribe's own output never puts up a card. One
lesson on the way: every test that constructs a `ShotScribeModel` must use
the same settings suite name, because `ShotScribeModel.defaults` is a
`static let` bound to the first suite it sees per process; a second name left
the watcher tests reading a suite nobody wrote to and watching the real
Screenshots folder. 267 tests. `serverInfo` and the changelog at 1.7.3,
unreleased.

## 2026-09-22, late afternoon — accurate, always
The morning's fix had a gate in it, and the gate was the next bug. Josh took
ten captures of numbered slides two minutes apart; the five at about 550 × 720
were named, the five at about 280 × 370 all came out "Screenshot", and the log
showed why: `ocr=0`, `3`, `22`, `0`, `36 chars`. The sparse re-read only ran
for a picture of at least 800 × 500, on the theory that a big picture with
little text read is small print — and a small picture is where `.fast` fails
hardest. A probe on the five files settled the design rather than the
threshold: `.fast` 0–36 characters, `.accurate` 171–317 with four titles of
five (the fifth read a wrong alphabet), `.accurate` on the picture doubled
700–820 with every title clean in about 90 ms; on the largest capture in the
folder, `.accurate` took 197 ms. Against a titler that takes seconds, a fast
pass that saves a tenth of a second and names a shot "Screenshot" is not a
saving. So `OCR.recognizeLines` now reads every frame at `.accurate`, and a
picture under 1,000 pixels on its longer side is doubled first
(`OCR.doubledBelow`, `OCR.enlarged`); `recognizeLayout` reads the same way,
with the file's own size and boxes in percent of it. The `.fast` mentions in
`SearchIndex`, `ChromeTests` and `docs/cli.md` are gone with it.
`SmallPrintTests` draws the 280-pixel slide and requires its title; the test
that had pinned the size gate is replaced by one that pins what is doubled.
258 tests. Rebuilt, packaged and relaunched; `shotscribe label` on the five
files and the morning's chart named all six. Triage has the entry.

## 2026-09-22, afternoon — the words findable in Spotlight at once
The Gap run's one add-now, built directly on Josh's word ("build it now, off by
default"). First the mechanism, checked live before any code: `kMDItemKeywords`
written as a metadata xattr onto a copy of the org chart in a throwaway folder
under Documents was in Spotlight within five seconds, matched by a plain query,
while Apple's own `kMDItemTextContent` was still empty; a dot-prefixed probe
folder had shown nothing, because Spotlight skips hidden folders. Then
`Spotlight.swift`: `keywords(title:tags:text:)` distils the title's words, the
tags, then the distinct significant words of the OCR (three letters or more,
no stopwords, capped at 60); `write`/`read`/`remove` through `Xattr`;
`ShotScribeDefaults.spotlightKeywords`, off by default. `Renamer.rename` takes
the OCR text it or the caller already has (the app passes its own read; the MCP
door pays one fast read only when the switch is on) and writes the list after
the move, beside the Finder tags — so every door writes it. The File tab's
switch back-fills every indexed shot from the index's own text on the way on and
strips them on the way off. Live: the CLI renamed a copy of the chart with the
switch on and Spotlight found it by "muhlenberg" in six seconds; "accounting"
did not match because the five-pixel type had read as "Accauntino" — a reading
limit, said so. 257 tests.
