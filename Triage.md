# Triage — shotscribe

Repo: `~/git/personal/active/shotscribe`

The bug record: one entry per issue, newest first, six fields (schema in `~/.claude/CHRIS-OP.md`). Identifiers go in, values never. `/bug` writes an entry when a cause is established, `/build` fills in the fix and the PR, `/save` catches anything handled in a session, and `/open` reads the newest.

## Log

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
