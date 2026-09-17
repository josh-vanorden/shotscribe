# Phase

## Current phase: Ship
As of 2026-08-12 (commit 9d2c9a2), all four "doors" to the engine are
built and shipped: CLI, MCP server, menu bar app, and the `/screenshot`
skill. The menu bar app is Developer-ID signed, notarized, and stapled
(app + DMG, commit a5b221d) — distribution mechanics work end to end.

## 2026-08-20 — extracted the face
`ShotScribeUI` split out of the menu bar executable so anything can host
ShotScribe; Toolbelt admitted it the same day as one of its first two organs.
No engine changes. Details in `History.md`.

## Gate to next phase (maintain)
- README.md's own roadmap still lists two open items: a "backlog sweep"
  (rename captures that landed while the app wasn't running) and a
  WidgetKit widget. Closing those — or explicitly deferring them — is a
  reasonable gate before calling this "maintain" rather than "ship."
- ~~TODO: no distribution channel confirmed for the notarized DMG.~~ Done
  2026-09-12: GitHub releases carry the DMG (`v1.5.1`, marked latest).

## Discovered sub-issues
- **2026-08-20 — `swift test` was blocked, then unblocked the same day.**
  `xcode-select` had been pointing at CommandLineTools, so `XCTest` was missing
  and the test target would not compile. Once corrected, `ShotScribeCoreTests`
  ran green: 13 tests, 0 failures. The `ShotScribeUI` extraction is therefore
  covered by both the suite and the hand verification below.
- **2026-08-20 — the notarized v0.4.0 DMG predates `ShotScribeUI`.** The
  extraction changed no engine behaviour, but the shipped artifact no longer
  matches the tree. Re-run the ship stage before pointing anyone at `dist/`.

## 2026-09-12 — the 0.7 cycle
The phase line stays **Ship**: 0.6.1 is out and nothing since has shipped.
Done locally on `settings-pane` (11 commits, unpushed): capture detection in
any language, name templates, Finder tags end to end with a switch, a Dock
window beside the menu bar item, and the glass window. 100 tests green.

## 2026-09-12, later — four borrows from screenshot-to-code, all landed
`layout_screenshot` + `/screenshot code`; screen recordings as captures;
`shotscribe eval` (whose first run exposed a fortnight of OCR-noise names and
fixed the offline titler); `{app}` off the capture's chrome, which also found
the menu bar leaking into titles. 118 tests. Still unshipped; the gate below
stands, one item longer.

## Gate to ship 0.7.0 — shipped as 1.5.0 on 2026-09-12
- [ ] `claude` signed in, then `shotscribe eval --limit 25` with Claude: the
      first real quality number, against names that were not the titler's own.
- [ ] One real run each of `/screenshot code` and the "Rebuild as code" paste
      inside a project. Both are prompts; neither has been exercised by a
      model yet, only their inputs verified.
- [x] Josh's live verdict on the glass window. Given 2026-09-12 from a
      screenshot of the window: the hero's action icons were cryptic and a
      disliked rename needed a fix where it lands. Both built the same
      evening (service-icon tiles named on hover; the title edits in place).
- [x] Merge `settings-pane` into `main` and push (`MANUAL_PUSH=1`). Done
      2026-09-12; `main` mirrors `settings-pane`.
- [x] Tagged `v1.5.0` (Josh's number) at `9ddbf8c` and notarized on
      2026-09-12: app and `dist/ShotScribe-1.5.0.dmg` signed, notarized
      (Apple: Accepted, both submissions), stapled; a quarantined copy out of
      the DMG passes Gatekeeper as Notarized Developer ID. `History.md` has
      the commands.
- [ ] Toolbelt: raise `.upToNextMinor(from: "0.6.0")` to `from: "1.5.1"`
      (`toolbelt/Package.swift:34`) and `swift package update shotscribe`, or
      it keeps mounting the 0.6.1 pane — a 1.x tag is out of that range.
- [ ] Live check of the capture flag timing under a custom
      `com.apple.screencapture name` (roadmap step 1).
- [ ] `claude` sign-in: the OAuth session expired 2026-09-10, so every title
      since is the offline titler's.

## Discovered sub-issues (2026-09-11 and 12)
- **`labelling` dispatched to the default.** As an extension-only method it
  bypassed every override through the `Titler` existential; 70 tests passed
  while nothing was tagged. Fixed by making it a protocol requirement, and
  tested through the existential. Found by running the CLI, not by the suite.
- **`mdls` lags the file.** Spotlight showed no tags on files whose xattr
  carried them. Read the xattr for truth.
- **Copied fixtures lie about dates.** A copy gets today's creation date, so
  the "latest" is whichever copied last and everything folds into one burst.
  Hard links keep the inode's date and tags.
- **`Text.foregroundStyle` on concatenated `Text` is macOS 14+.** The floor is
  13; `foregroundColor` is the spelling that works.
- **`chrisop-refresh` regenerates `Index.md` after every commit**, so the tree
  is dirty again the moment a commit lands. Fold it into a docs commit.
- **Tag chips read as actions.** Bare pills styled like buttons, and a tag
  spelled "code" beside a feature called code; Josh asked what the terminal
  button does. Now a tag glyph, the word and a tooltip (9061022), and stage
  two has a real answer, the brief (7f2d09b).

## 2026-09-12, evening — 1.5.0 exists; the phase stays Ship
Tagged, notarized and pushed, but the DMG sits in `dist/` and no GitHub
release carries it, and Toolbelt cannot see a 1.x tag until its pin moves.
The gate to *maintain* above is unchanged: distribution channel unconfirmed,
README's two roadmap items open. Discovered this evening:
- **The window Josh looks at is whichever build was launched, not the one
  in `dist/`.** Two rebuilds went unseen because the 17:26 process kept
  running; the fix is to quit and reopen after every package, which the
  session now does itself.
- **`sharingServices(forItems:)` is deprecated at macOS 13** and its named
  replacement is a menu item, which cannot be laid out as the unfolding row
  Josh asked for. It still answers on macOS 26; one deprecation warning is
  kept on purpose with the reason beside it.

## 2026-09-12, night — 1.5.1 released; the phase is still Ship, by one item
The QA pass (History, same date) fixed three things and shipped `v1.5.1` as
a public GitHub release with the notarized DMG. Of the gate to *maintain*,
the distribution channel is now real; what remains is Josh's call on the
README's two open roadmap items (backlog sweep — 93 raw files are waiting —
and the widget): close them or defer them explicitly, and this is maintain.
Sub-issues found by the pass:
- **`package-app.sh` builds one product.** The CLI and MCP binaries in
  `.build/release` can be days stale; a QA run must `swift build -c release`
  first. The first E2E run was wrong about four features because of this.
- **Fixtures inherit xattrs.** `cp` carries the capture flag and Finder tags;
  use `cp -X`. Hard links share the inode, so never tag through one.

## 2026-09-13 — 1.6.0 built; the phase stays Ship
"Bring your own AI" is built, tested (140) and pushed on `settings-pane`,
unreleased: an AI tab (Rename absorbed Name), seven titlers behind one
setting, the Send-to tile wearing the titler's mark. Release is scheduled for
Monday 2026-09-14; the gate below is that morning's list.

## Gate to ship 1.6.0
- [ ] Josh's click-through of the AI tab on the 08:31 build (each kind, the
      tile's mark, "Try it" on Ollama, the popover switch, an endpoint at
      `http://localhost:11434/v1`).
- [x] `serverInfo` → 1.6.0; CHANGELOG dated 2026-09-13; `/save`.
- [x] Tagged `v1.6.0` at `0a901f6`; notarized under `shotscribe-notary`
      (ShotScribe's own profile, made with `apple-ship credentials`); Apple
      Accepted app and DMG, stapled, spctl and a quarantined copy pass.
- [x] Pushed with the tag; released 2026-09-13 as
      https://github.com/josh-vanorden/shotscribe/releases/tag/v1.6.0 (latest).
- [ ] Toolbelt: `Package.swift:34` → `.upToNextMinor(from: "1.6.0")`,
      `swift package update shotscribe`.

## Discovered sub-issues (2026-09-13)
- **A menu `Picker` on a computed `Binding` changed its face, not the model.**
  Josh: "had to choose twice", tile stale. Plain `@State` + `onChange` both
  ways is the rule (CLAUDE.md, Triage). Proven with `scripts/render-pane.swift`.
- **Rasterising brand SVGs on macOS.** `NSImage` (CoreSVG) dropped Gemini's
  gradient; Quick Look painted it on a white square; a `WKWebView` snapshot on
  a transparent page keeps both — `scripts/svg-to-png.swift`.
- **A blocked CLI looked like a blunt titler.** `Renamer.labelling` swallowed
  the error into "Screenshot"; now reported (`onTitlerError`). Found because
  macOS refused the Homebrew `codex` 0.118.0 binary as known malware and the
  run printed a title. Codex stays unverified here (History, memory).
- **The Codex, Gemini CLI and Cursor Agent presets are their documented
  invocations**, editable, not run end to end on this Mac. Stated in the
  README and the release notes.

## 2026-09-13, afternoon — the day's second half, still unreleased
Added to 1.6.0 after the morning's gate was written: the landing zone in the
list view, the bin that eats its label (with the Keep tab's Trash-or-delete
choice), Josh's icon, the tagline in the README and the welcome, and the
window reloading when the watcher names a capture. Josh took a capture and
watched it land without a relaunch — the first live confirmation of the
watcher-to-window path. The gate to ship 1.6.0 stands as written; Josh's
read at 12:09: "we are set".
- **A capture the watcher named stayed off screen until the next launch**
  (Triage 12:10). The rename path never reloaded the cache; found only
  because the noon captures were the first taken without a relaunch between.
- **The list view had no landing zone** (Triage 09:30). The hero was wired
  into the tiles branch only.

## 2026-09-13, 13:36 — 1.6.0 is public; the phase is still Ship, by Josh's own item
Two gate items remain: Toolbelt's pin (another repo) and Josh's continued
testing, which he chose to keep doing after the release. The gate to
*maintain* is unchanged — the README's two roadmap items are still his call.

## 2026-09-13, evening — 1.6.1 public; phase Ship, gate to maintain unchanged
The day's finds shipped as 1.6.1 under ShotScribe's own notary profile, with
a hand security sweep (two hardenings). Toolbelt's pin is at 1.6.0
(committed there, unpushed). The gate to *maintain* still turns on Josh's
call about the README's two roadmap items; the release machinery itself is
now routine: version, tag, `APPLE_NOTARY_PROFILE=shotscribe-notary`,
verify, push, `gh release create`.
- **Sub-issue:** `/security-team` cannot run while `claude` is signed out
  (each track is a `claude -p`); the hand sweep is the fallback and is
  recorded in History. Run the skill after sign-in for 1.6.2.

## 2026-09-13, late — 1.6.2 public; phase Ship, gate to maintain unchanged
The seven-track `/security-team` pass ran for real after `claude` signed in
(twelve fixes, the deferred four included), and Josh's held-tag item — a
right-click on every shot and a default for the plain click, set from the
landing zone — shipped with it as 1.6.2 under `shotscribe-notary`. Toolbelt's
pin is at 1.6.2 (committed there, unpushed). The gate to *maintain* still
turns on Josh's call about the README's two roadmap items.
- **Sub-issue:** the default tile's mark was invisible in light mode as a
  low-opacity accent ring on the tile's edge (Triage 21:10); it took three
  rounds — outside the circle, then green — to be "unmistakable". Rule: a
  state mark must be rendered in both appearances before Josh sees it.
- **Sub-issue:** `~/.claude.json` still registers the `shotscribe` MCP
  server for the old project path `~/git/personal/shotscribe` (the repo
  moved to `active/`); the binary it names does not exist. Josh's to
  re-register from `active/shotscribe/.build/release/shotscribe-mcp`.

## 2026-09-14 — 1.6.3 public; phase Ship, and the gate to maintain finally moves
Josh's verdict this morning, unprompted: *"The entire app runs flawlessly so far
and does everything we really could ask it to."* The one thing he named as
missing — a greeting on first configuration — was built the same hour. The gate
to *maintain* has always turned on his call about the README's two roadmap items
(the backlog sweep and the widget); they are still open, so the phase line stays
**Ship**, but nothing else is holding it.
- **Sub-issue, fixed:** a hover preview put in a row's own overlay is drawn over
  by every row built after it in a `LazyVStack`, and `zIndex` does not save it.
  An anchor preference read by the container is the shape that works
  (Triage 2026-09-14 08:33).
- **Sub-issue, fixed:** a test fixture drawn through `NSImage.lockFocus` takes
  its scale from the attached display, so the suite went red when the operator
  changed monitors (Triage 2026-09-14 08:27).
- **Still open, unchanged:** the README's backlog sweep (93 raw files) and the
  WidgetKit widget; Codex, Gemini CLI and Cursor Agent presets unverified on
  this Mac; `shotscribe eval --limit 25` for the first real quality number.

## 2026-09-15 — phase Ship; 1.6.4 is built and unreleased
The capture card, the Send-to consolidation and the tag fixes are on
`settings-pane`, unreleased. The gate to *maintain* is unchanged and still
Josh's call: the README's backlog sweep (94 raw files) and the widget.
- **Sub-issue, fixed:** a `DeletePill` that never reset went dead for every
  later shot, because a lazy stack reuses the view and its `@State`
  (Triage 2026-09-15 15:0x). Shipped in 1.6.3 — worth a release when 1.6.4 goes.
- **Sub-issue, fixed:** filing was one-way and the vocabulary could not be
  emptied (Triage, same day). Both shipped behaviours.
- **Discovered:** the watcher reports ShotScribe's own renamed output, so
  anything reacting to "a capture landed" must gate on `Naming.isRawCapture`.
- **Discovered:** a capture interrupted mid-rename (the app quits while the
  titler is thinking) is never retried — it silently joins the backlog.
- **Next:** the backlog sweep is the last roadmap item and the one that needs a
  full library; Josh is holding off clearing his 94 raw captures for it.

## 2026-09-15, evening — 1.6.4 public
Tagged `v1.6.4`, notarized under `shotscribe-notary` (app and DMG accepted,
stapled, a quarantined copy through Gatekeeper), pushed with the tag, released
as latest, Toolbelt's pin raised. The gate to *maintain* is now one item: the
README's backlog sweep — the widget aside, it is the last thing on that list,
and Josh is holding his 94 raw captures for it.
- **Release note:** `gh` had drifted to the work account and refused the
  release for want of a scope; `forge auto` put it back on the personal one.
  Worth running before `gh release create`, not after it fails.

## 2026-09-16 — 1.6.5 shipped; the gate to *maintain* is down to the widget
The editor (marks, kept edits, frames, crop, resize, steps, bent arrows,
watermark, fonts), the backlog sweep and the appearance flip went out as 1.6.5.
The README's backlog sweep is ticked — built, Josh's to run — so the gate to
*maintain* is one item, the WidgetKit widget, and that is his call to build or
defer. The phase line stays **Ship** until he makes it.
- **Sub-issue, fixed:** a view modifier hung off a panel dies with the panel;
  loaders the canvas depends on belong at the root (Triage 2026-09-16 13:44).
- **Sub-issue, fixed:** a grey Save reads as broken; the footer now says
  **Done** when nothing would be written (Triage 2026-09-16 13:51).
- **Sub-issue, fixed:** the watcher re-titled ShotScribe's own output — the
  name check now runs before OCR (Triage 2026-09-16 09:40).
- **Open, Josh's call:** stamping every *capture* with the kept watermark at
  capture time, without the editor. Small to build; it would alter every
  screenshot, personal ones included, so it was asked, not built.
- **Open:** a second bend pin on arrows if one ever proves short; Toolbelt's
  pin commits (1.6.0–1.6.5) still unpushed there; the dead MCP entry in
  `~/.claude.json`; the announcement.

## 2026-09-17 — the audit stamp, unreleased on top of 1.6.5
Phase stays **Ship**; the gate to *maintain* is unchanged (the widget, Josh's
call). New and waiting on him: the ISO evidence list, which decides whether the
stamp needs more lines (a control ID, a ticket, an "evidence for" field) and
whether `shotscribe digest <file>` gets built so the digest is checkable
outside the app.
