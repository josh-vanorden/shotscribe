# Triage — shotscribe

Repo: `~/git/personal/active/shotscribe`

The bug record: one entry per issue, newest first, six fields (schema in `~/.claude/CHRIS-OP.md`). Identifiers go in, values never. `/bug` writes an entry when a cause is established, `/build` fills in the fix and the PR, `/save` catches anything handled in a session, and `/open` reads the newest.

## Log

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
