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
- TODO: no distribution channel (e.g. a GitHub release, Homebrew tap)
  confirmed yet for the notarized DMG sitting in `dist/` — worth checking
  before treating "ship" as complete.

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

## Gate to ship 0.7.0
- [ ] `claude` signed in, then `shotscribe eval --limit 25` with Claude: the
      first real quality number, against names that were not the titler's own.
- [ ] Josh's live verdict on the glass window. It was rendered off-screen in
      both appearances; hover captions and the inspector animation are unseen.
- [ ] Merge `settings-pane` into `main` and push (`MANUAL_PUSH=1`).
- [ ] Tag `v0.7.0` and run `APPLE_NOTARY_PROFILE=… ./scripts/package-app.sh`.
      `dist/` holds a locally signed build of the branch; the notarized app is
      0.6.1, inside the DMG.
- [ ] Toolbelt: raise `.upToNextMinor(from: "0.6.0")` and update its pin, or it
      keeps mounting the old pane.
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
