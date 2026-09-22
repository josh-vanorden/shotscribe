# Triage — shotscribe

Repo: `~/git/personal/active/shotscribe`

The bug record: one entry per issue, newest first, six fields (schema in `~/.claude/CHRIS-OP.md`). Identifiers go in, values never. `/bug` writes an entry when a cause is established, `/build` fills in the fix and the PR, `/save` catches anything handled in a session, and `/open` reads the newest.

## Log

### 2026-09-22 09:10 — Send to Claude sent a path into a chat that cannot see the disk
- **Bug/Issue:** Josh, after a night of building: Send to Claude "passed a /screenshot command with a local Mac path into a claude.ai chat, which runs in a cloud container and can't see your disk, so nothing arrived."
- **RCA:** The hand-off was one destination, designed for Claude Code on this Mac, where `/screenshot "<path>"` makes the skill read the file. claude.ai and the Claude desktop app run their chats in a container; a local path there is a question about a file that does not exist. The gesture did not say which kind of session it was for.
- **Evidence:** `ShotScribeModel.sendToAssistant` wrote only `public.utf8-plain-text` with the slash line; confirmed by reading the pasteboard after driving the model.
- **Fix/Repair:** Two destinations named by what they can see. `SendToClaude.picture(forImageAt:)` builds a pasteboard item with the PNG, the file URL and the file's *name*; `model.sendPicture` puts it up with a note saying where to paste; `ShotAction.sendPicture` sits beside the path form on the Send tile, the card and the shot menu, and can be the click default. The path form's note now says it is for a session on this Mac. Test: the item carries the image and the name and never the path. Unreleased.
- **Related PR:** none — on `main`

### 2026-09-16 13:44 — The watermark logo never appeared in the preview
- **Bug/Issue:** Josh: "Logo showed up, but we have no watermark preview so any adjustments are made blindly." The saved file carried the logo; the canvas showed nothing while he adjusted it.
- **RCA:** The `onChange` that decodes the chosen logo for the canvas was attached to the Frame panel's background row — a view that only exists while the Frame panel is open. Picked from the Watermark panel, the change fired on nothing; the canvas drew a watermark whose picture it did not have, and Save loaded the file itself.
- **Evidence:** `Editor.swift`, the modifier's position next to `loadBackgroundImage`; text watermarks previewed, logos did not.
- **Fix/Repair:** The modifier moved to the editor's root, where it fires whichever panel picked the logo and on open for a kept edit. 1.6.5.
- **Related PR:** none — on `settings-pane`

### 2026-09-16 13:51 — Save sat grey for a watermark-only edit
- **Bug/Issue:** Josh: "clicked Use on Every edit and now the save button does not work." Then, on a fresh shot with the every-edit watermark taken off: "failing to save now again."
- **RCA:** Save's "anything to save?" rule counted marks, frame, crop, resize and a reopened edit — not the watermark, which was new. The second report was the rule being right — nothing had changed — and reading as a failure because a grey button explains nothing.
- **Evidence:** `.disabled(...)` on the footer button; the main thread sampled idle, no crash log, nothing in `ShotScribe.log`.
- **Fix/Repair:** `hasSomethingToSave` counts the watermark; with nothing to write the button reads **Done** and closes, never grey. 1.6.5.
- **Related PR:** none — on `settings-pane`

### 2026-09-16 13:41 — A logo made a shaded box
- **Bug/Issue:** Josh: "Water mark made a shaded box when I added an image."
- **RCA:** The logo file had no transparency worth the name — a flattened PNG on a white square — so its alpha (or the whole rectangle, when there was none) was the "shape": a solid block in Auto ink, a white box with a halo As is.
- **Evidence:** reproduced with an opaque 128×128 logo in the harness (`wm-logo-flat`).
- **Fix/Repair:** `logoMask` uses the alpha when at least a hundredth of the picture is see-through; otherwise `keyedMask` takes the median colour along the edges as the background and keeps everything that is not it. Test: a red disc on an opaque white square shows no square in either ink. 1.6.5.
- **Related PR:** none — on `settings-pane`

### 2026-09-16 09:40 — The watcher re-titled ShotScribe's own output
- **Bug/Issue:** `ShotScribe.log` showed a titler call for every file ShotScribe had just renamed — 257 in one stretch — each refused by the name check a moment later.
- **RCA:** `rename` ran OCR and the titler before `Naming.isRawCapture`, and the watcher reports ShotScribe's own renamed file landing, so every rename cost a second model call that produced nothing.
- **Evidence:** the log; the order of the guards in `ShotScribeModel.rename`.
- **Fix/Repair:** the name check runs before OCR. 1.6.5.
- **Related PR:** none — on `settings-pane`

### 2026-09-15 15:05 — The bin went dead after the first delete
- **Bug/Issue:** Josh, twice: "I delete one image and then try to delete a second image and the button no longer works until I click somewhere else."
- **RCA:** `DeletePill` runs an animation that ends at `stage = .done` and never returns to `.idle`; `fire()` opens with `guard stage == .idle`. The view normally leaves with the shot it deleted, but in a `LazyVStack`/`LazyVGrid` SwiftUI reuses it for whatever moves into that slot and the `@State` goes with it, so the next shot's bin was born already spent. Clicking elsewhere forced a rebuild, which is why it came back to life.
- **Evidence:** the `guard` and the absent reset in `fire()`; Josh's report reproduced on two different builds. Shipped in 1.6.3 and earlier.
- **Fix/Repair:** `reset()` after the action fires, and `.id(shot.path)` on every bin so reuse cannot carry state across a shot boundary at all. Josh confirmed: "Delete button is fixed." 1.6.4.
- **Related PR:** none — on `settings-pane`

### 2026-09-15 15:30 — A tag could be added but never taken off
- **Bug/Issue:** Josh: "once a tag is selected you cannot change it."
- **RCA:** `Tagging.add` merges and there was no counterpart; every tag menu marked an applied tag `.disabled`, so the first guess was final. Filing is a guess by design — the model proposes tags from a closed vocabulary — which makes an irreversible one worse than none.
- **Evidence:** `Tagging.swift` had `add` and no `remove`; the three menus all disabled applied tags.
- **Fix/Repair:** `Tagging.remove`, `model.untag` / `isTagged` / `toggleTag`; every menu ticks what is on the shot and takes it off when picked, and the card's chips come off on click. Test: a tag comes off without disturbing the others, case-insensitively. 1.6.4.
- **Related PR:** none — on `settings-pane`

### 2026-09-15 15:30 — The tag vocabulary could not be emptied
- **Bug/Issue:** Josh: "deleting the 15 or so examples is still a ?" Removing the words one at a time never finished.
- **RCA:** `setVocabulary([])` removed the stored key, and `vocabulary()` returned the shipped list whenever nothing was stored — so deleting the final word restored all sixteen. The intent was sound (never leave the operator with no list) but it made "nothing stored" and "stored empty" the same answer, and there was a test pinning it.
- **Evidence:** `Settings.setVocabulary` / `vocabulary()`; `TaggingTests.testAnEmptyVocabularyFallsBackToTheShippedList`.
- **Fix/Repair:** an empty list is stored as empty; the shipped words stand in only when the key is absent. `restoreDefaultVocabulary` is the way back, wired to the File tab's **Shipped list** button — which had been calling the emptying path and would have done the opposite of its label. **Remove all** clears it in one gesture, and an empty list says so in warning colour. Test rewritten to pin the new contract. 1.6.4.
- **Related PR:** none — on `settings-pane`

### 2026-09-14 08:33 — The list's hover preview was drawn behind the rows
- **Bug/Issue:** Josh: "the preview is pushed back and covered by the list of shots." The capture appeared under the row names beneath it, and it sat over those names rather than clear of them.
- **RCA:** The preview was an `.overlay` on the row itself with `.zIndex(hovered ? 10 : 0)`. A row's overlay is layered with that row's siblings inside the `LazyVStack`, so every row built after it draws over the top; `zIndex` orders siblings, not a row's overlay against later siblings. Mine to own — it was written that way in the first cut the same morning.
- **Evidence:** Josh's screenshot of the list, names drawn across the preview image.
- **Fix/Repair:** The row publishes its bounds through an `anchorPreference`; `shotsList` reads it with `overlayPreferenceValue` and draws one preview in the container's own overlay, which is above every row by construction — placed 320pt right of the names, clamped to the pane width and flipped above the row near the end of the list. The row's path tooltip went with it. Same day, 1.6.3 (`c6c9ae0`).
- **Related PR:** none — on `settings-pane`

### 2026-09-14 08:27 — The app-name test went red on every commit, old ones included
- **Bug/Issue:** `ChromeTests.testARenameReadsTheAppOffTheImage` began failing consistently — `Chrome.app` read "Terniinal" instead of "Terminal" — after a green run at 08:00 on the same tree, and it failed at 2e6d9cc too, so it was not that morning's UI work.
- **RCA:** The fixture was drawn through `NSImage.lockFocus()`, which takes its scale from the attached display. `OCR.recognizeLines` reads with `.fast` and `usesLanguageCorrection = false`, and a 15pt menu-bar label at 1x is ~15 device pixels — right at that reader's threshold, where "rn" comes back as "ni". A real capture is 2x, so the test was reading a fixture no screenshot looks like, at a fidelity the code never has to handle. The operator moved to two 1x external displays that morning.
- **Evidence:** A standalone probe read the identical image correctly with `.accurate` + language correction and failed under the engine's own `.fast` settings; `NSScreen.screens.map(\.backingScaleFactor)` returned `[1.0, 1.0]`; a worktree at 2e6d9cc failed the same way three runs running.
- **Fix/Repair:** The fixture is drawn into an explicit 2x `NSBitmapImageRep` instead of `lockFocus`, so it matches a real Retina capture and no longer depends on which monitor is plugged in. Green three runs running; 167 tests. 1.6.3.
- **Related PR:** none — on `settings-pane`

### 2026-09-13 21:10 — The default tile's mark could not be seen in light mode
- **Bug/Issue:** Josh, matching the system appearance: the landing-zone tile that is the click default was "barely" visible in dark mode and invisible in light.
- **RCA:** The first mark was the accent (lavender) as a 1.5 pt ring at 0.55 opacity on the tile's own edge plus a soft accent shadow; on the light band, tinted by the hero's thumbnail, a half-transparent lavender over a lavender-grey tile has almost no contrast, and the harness render was only checked in dark.
- **Evidence:** Josh's report on the 20:32 build; `scripts/render-pane.swift`-style harness renders in `.aqua` and `.darkAqua` side by side (session scratchpad `harness-tags/rows-ld-big.png`).
- **Fix/Repair:** Three rounds, each rendered in both appearances first: a solid ring (`ed6f6ea` first cut), then the ring moved 4 pt outside the circle with a glow so the icon is untouched (`ed6f6ea`), then the colour to systemGreen as `ShotPalette.chosen` (`b57dca5`). Same evening, 1.6.2.
- **Related PR:** none — on `settings-pane`

### 2026-09-13 20:40 — A stopped watcher could still rename once
- **Bug/Issue:** `FolderWatcher.stop()` cancelled the dispatch source but not the debounced scan already queued, so a capture that landed inside the half-second window before the watching toggle went off (or before a hosted copy stood down) could still be renamed — the two-watchers-one-capture race the stand-down exists to close.
- **RCA:** `stop()` and `ignore()` both confine work to the watcher's queue; `stop()` never touched the pending `DispatchWorkItem`.
- **Evidence:** `/security-team` track 07 (`docs/security/2026-09-13/track-07.md`); `HardeningTests.testAStoppedWatcherNeverReports` (an inverted expectation across the debounce window).
- **Fix/Repair:** `stop()` cancels the debounce work item on the queue (`3bef5c4`, merged 2026-09-13). 1.6.2.
- **Related PR:** none — `security/20260913-1829` merged into `settings-pane`

### 2026-09-13 16:30 — A tag filter with no way out
- **Bug/Issue:** Josh isolated a tag and "had no way of clearing or returning to the normal view once drilled into an area."
- **RCA:** Two causes. The strip's Clear was a quiet, background-less chip easy to miss. Worse, a filter that narrows to zero shots fell into `content`'s empty branch, which is the first-launch welcome — no strip, no Clear, no count line — so isolating a tag whose only shot was the landing zone, or narrowing to two tags nothing carries together, was a dead end.
- **Evidence:** Josh's report on the 16:15 build; the `content` branch order in `ShotScribeSurface.swift`.
- **Fix/Repair:** The empty-under-filter case keeps the grid head, the strip and a "Nothing filed under X + Y together" line with a prominent Show all; the strip's Clear became a real "Show all" button; a selected chip carries an × to say it comes off; the count line has a Show all link; Esc clears the filter. Same day, 1.6.1.
- **Related PR:** none — on `settings-pane`

### 2026-09-13 12:10 — A capture the watcher named did not appear until the next launch
- **Bug/Issue:** Josh took captures at 12:01 and 12:02; the log shows both renamed and the index holds them, but the window kept showing the morning's shots — "only one screenshot for today".
- **RCA:** `ShotScribeModel.rename` recorded the new file into the index on a detached task and never reloaded the model's cache; `retitle`, `undo`, `tag` and `trash` all call `loadIndex()`, the watcher's own path did not. Every earlier sighting of a fresh capture in the window had a relaunch between the capture and the look.
- **Evidence:** `~/Library/Logs/ShotScribe.log` 12:01–12:02 (renamed, then the re-fire skipped as not raw); `index.json` with four entries for 2026-09-13; the window from an 11:51 launch.
- **Fix/Repair:** After `ShotIndex.record` the detached task hops to the main actor and calls `loadIndex()` and `runSearch()`. Same day, unreleased (1.6.0).
- **Related PR:** none — on `settings-pane`

### 2026-09-13 09:30 — The list view had no landing zone
- **Bug/Issue:** Josh, from a screenshot of the window in list view: the newest capture's landing zone — the hero, with the title edit and the tiles — was missing; only the rows showed. "The landing zone is the key to our system so it missing degrades user functionality."
- **RCA:** `content` built the hero only on the tiles branch; the list branch went `gridHead` → `shotsList` and never asked for `heroShot`. The list predates the hero (2026-09-12) and was not revisited when it landed.
- **Evidence:** `2026-09-13 0925 Sep Screenshots Claude.png` in the Screenshots folder; the off-screen render `7-list.png` (session scratchpad) after the fix, hero above two rows.
- **Fix/Repair:** The list branch renders the hero first and `shotsList(excluding:)` drops the hero's path from the rows, as the grid's day groups already did. Same day, unreleased (1.6.0).
- **Related PR:** none — on `settings-pane`

### 2026-09-13 08:00 — The AI picker changed its face, not the setting
- **Bug/Issue:** Josh: switching the titler "is not switching our icons… I had to choose twice", and with the picker reading Codex the Send-to tile still showed Gemini's "G".
- **RCA:** The menu-style `Picker` was bound to a computed `Binding(get:set:)`; its popup updated its own displayed value while the setter did not reach the model, so nothing published and the tile (which follows the model, proven by an off-screen render driving `setAIProvider` directly) had nothing to follow. The body also called `availability()`, which can spawn a login shell to find a CLI, on the main thread during the menu's commit.
- **Evidence:** `scripts/render-pane.swift` snapshots `1-gemini.png` / `2-codex.png` / `3-cursor.png` (session scratchpad) showing the tile tracking the model; Josh's report of the live window.
- **Fix/Repair:** The picker binds to `@State kindDraft` with `onChange` handlers in both directions, and availability is computed off the main thread into `model.aiAvailability`. Same day, unreleased (1.6.0).
- **Related PR:** none — on `settings-pane`

### 2026-09-13 07:05 — A failing titler became "Screenshot" in the CLI
- **Bug/Issue:** `shotscribe label` with a titler that could not run (a CLI macOS refused to launch) printed the title "Screenshot" and no error, so a broken assistant looked like a blunt one.
- **RCA:** `Renamer.labelling(fileAt:)` wrapped the titler in `try?` and fell through to a literal "Screenshot"; the app's own rename path had reported failures since 2026-08-12, the CLI and MCP paths never did.
- **Evidence:** The Codex run in the 2026-09-13 QA (History, same date); `AIProviderTests.testAFailingTitlerIsReportedAndTheOfflineNameStands`.
- **Fix/Repair:** `Renamer.onTitlerError` reports the failure and the offline titler names the shot; the CLI prints "note: <titler> failed — … Used the offline title." Same day.
- **Related PR:** none — on `settings-pane`, unreleased (1.6.0)

### 2026-09-12 19:40 — The search index was world-readable
- **Bug/Issue:** `~/.shotscribe/index.json` — the text read off every capture — sat at mode 0644 in a 0755 folder, while the README called it more sensitive than the screenshots. Found in the QA pass (`ls -la ~/.shotscribe`).
- **RCA:** `ShotIndex.save` wrote with `Data.write(options: .atomic)` and created the folder with default attributes; nothing ever set a mode, so the umask decided.
- **Evidence:** `ls -la` before: `-rw-r--r--` / `drwxr-xr-x`; `HardeningTests.testTheIndexIsReadableByItsOwnerOnly` after.
- **Fix/Repair:** The folder is created 0700 and the file set 0600 after every save (`.atomic` writes a fresh file, so an old index is tightened on its next save). Commit on `settings-pane`, 2026-09-12 (see `History.md`, 1.5.1).
- **Related PR:** none — released as 1.5.1

### 2026-09-12 19:40 — A dot-only word survived title sanitising
- **Bug/Issue:** `rename_screenshot` with the title `../../etc/passwd Title` produced `2026-09-12 1933 .. etc passwd.png`. Harmless — `/` is stripped, so the file stays in its folder — but `..` reached a file name.
- **RCA:** `Naming.sanitize` removes path-illegal characters and collapses spaces; a word made only of dots contains none of those characters.
- **Evidence:** The MCP driver run in the QA pass (scratch folder); `HardeningTests.testATitleCannotCarryAPathComponent`.
- **Fix/Repair:** `sanitize` drops words that contain nothing but dots; dots inside a word (`v1.5.0`) stay. Same commit as above.
- **Related PR:** none — released as 1.5.1

### 2026-09-12 19:38 — The tag tile wrapped to a second row
- **Bug/Issue:** In the window capture of the 1.5.0 build, the landing zone's seventh tile (File as) sat alone on a second line with visible room to its right.
- **RCA:** The hero splits its width evenly between the thumbnail and the text column, leaving the column about 252 pt; seven 30 pt tiles at 8 pt spacing need 258. `FlowLayout` did what it is for.
- **Evidence:** `window.png` and the `tiles.png` crop in the session scratchpad; the arithmetic.
- **Fix/Repair:** Tiles are 28 pt at 6 pt spacing (232 pt); the row still wraps gracefully below that. Same commit.
- **Related PR:** none — released as 1.5.1

### 2026-09-12 17:40 — Tag chips read as actions
- **Bug/Issue:** Josh, on the new window: "What does the terminal button do?" and "the code button, stage two the user hits code, then what?" The pills under a tile were Finder tags, not controls.
- **RCA:** The chips were bare capsules styled like the window's buttons, with no glyph and a hover that said only "Find everything tagged code"; the shipped vocabulary holds "code" and "terminal", which read as verbs beside a feature called code. Nothing on the chip said what it was.
- **Evidence:** Josh's message of 2026-09-12; the off-screen renders `glass-port-dark.png` (before) and `chips.png` (after) in the session scratchpad.
- **Fix/Repair:** One `TagChip` everywhere: the tag glyph, the word, and the tooltip "Filed under code (a Finder tag). Click to see everything filed the same way." Commit `9061022`. Stage two got its answer in `7f2d09b`, "Rebuild as code".
- **Related PR:** none — `josh-vanorden/shotscribe@9061022`

### 2026-09-12 17:05 — Menu bar words in titles: the offline titler read the chrome
- **Bug/Issue:** A rendered capture with a menu bar ("Terminal Shell Edit View Window Help") and a body ("deploy finished with warnings") was titled "Terminal Shell Edit" under `{date} {app} {title}`, in `ChromeTests.testARenameReadsTheAppOffTheImage`. Every full-screen capture titled by the offline titler had been exposed to the same words.
- **RCA:** The titler was handed the whole OCR text. On a shot whose words each occur once, `KeywordTitler` picks the first three non-stopwords in reading order, and the menu bar is read first. Nothing separated chrome from content.
- **Evidence:** The test's own failure message, listing the recognised lines with positions: `Terminal@top0`, `Shell Edit View Window Help@top0`, `deploy finished with warnings@top46`. Reproduced on the built package before the fix.
- **Fix/Repair:** `Chrome.body(of:)` drops lines in the top strip when the capture has chrome; `Renamer` (both paths) and `ShotScribeModel.rename` hand the titler that body. Commit `82aaf00`.
- **Related PR:** none — committed on `settings-pane` (`josh-vanorden/shotscribe@82aaf00`)

### 2026-09-11 17:27 — Nothing was tagged: `labelling` dispatched to its default
- **Bug/Issue:** The first end-to-end run of tagging, `shotscribe rename --no-claude` on a generated capture, renamed the file and wrote no Finder tags, while all 70 tests passed.
- **RCA:** `Titler.labelling(forOCRText:vocabulary:)` was declared only in a protocol extension. Every door holds a `Titler` existential, and an extension-only method dispatches statically, so the `KeywordTitler` and `ClaudeTitler` overrides were never reached and the default returned no tags. The tests held concrete titlers, so they took the override and stayed green.
- **Evidence:** `./.build/debug/shotscribe rename --no-claude "<scratch>/Screenshot 2026-08-11 at 3.41.07 PM.png"` printed the rename with no `tags` line; after the fix the same command printed `tags  terminal, error`, and `xattr -px com.apple.metadata:_kMDItemUserTags` on the result decoded to `terminal`, `error` in Finder's own plist format. History.md, 2026-09-11, "Tags, written where macOS already looks for them".
- **Fix/Repair:** `labelling` became a protocol requirement with the default kept in the extension (`Sources/ShotScribeCore/Titler.swift`); `TaggingTests.testTaggingSurvivesBeingCalledThroughTheProtocol` holds the existential on purpose. Commit `cb79fcc`.
- **Related PR:** none — committed on the work branch and promoted to `main` (`josh-vanorden/shotscribe@cb79fcc`)
