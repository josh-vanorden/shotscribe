# Triage — shotscribe

Repo: `~/git/personal/active/shotscribe`

The bug record: one entry per issue, newest first, six fields (schema in `~/.claude/CHRIS-OP.md`). Identifiers go in, values never. `/bug` writes an entry when a cause is established, `/build` fills in the fix and the PR, `/save` catches anything handled in a session, and `/open` reads the newest.

## Log

### 2026-09-11 17:27 — Nothing was tagged: `labelling` dispatched to its default
- **Bug/Issue:** The first end-to-end run of tagging, `shotscribe rename --no-claude` on a generated capture, renamed the file and wrote no Finder tags, while all 70 tests passed.
- **RCA:** `Titler.labelling(forOCRText:vocabulary:)` was declared only in a protocol extension. Every door holds a `Titler` existential, and an extension-only method dispatches statically, so the `KeywordTitler` and `ClaudeTitler` overrides were never reached and the default returned no tags. The tests held concrete titlers, so they took the override and stayed green.
- **Evidence:** `./.build/debug/shotscribe rename --no-claude "<scratch>/Screenshot 2026-08-11 at 3.41.07 PM.png"` printed the rename with no `tags` line; after the fix the same command printed `tags  terminal, error`, and `xattr -px com.apple.metadata:_kMDItemUserTags` on the result decoded to `terminal`, `error` in Finder's own plist format. History.md, 2026-09-11, "Tags, written where macOS already looks for them".
- **Fix/Repair:** `labelling` became a protocol requirement with the default kept in the extension (`Sources/ShotScribeCore/Titler.swift`); `TaggingTests.testTaggingSurvivesBeingCalledThroughTheProtocol` holds the existential on purpose. Commit `cb79fcc`.
- **Related PR:** none — committed on the work branch and promoted to `main` (`josh-vanorden/shotscribe@cb79fcc`)
