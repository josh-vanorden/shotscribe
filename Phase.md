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
