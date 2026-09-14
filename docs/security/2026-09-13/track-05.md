# Sub-Agent 5: Data Exposure & Logging Hygiene

## Assessment

ShotScribe has **no telemetry, no analytics, no crash reporter, and no server**
— the classic surfaces this track exists for are absent by design. What it does
have is one debug log, one search index, one settings domain, and four doors
(app, CLI, MCP server, network titler) that each hand information to somebody.
The question for every surface was the track's: *where does information useful
for internal debugging also reach an observer who shouldn't have it?*

The sensitive data category here is singular and unusual: **text read off the
user's screen**. OCR output, and everything derived from it — titles, tags,
filenames, error strings quoting titler output — is a record of what the user
was looking at. The repo already treats the worst store of it (the index) as
"more sensitive than the screenshots themselves" and keeps it 0600/0700 with a
test pinning that (`HardeningTests.swift:8`). The gap this track found and
closed: the *log* carries the same category of text and was written 0644.

### Surface-by-surface

- **`~/Library/Logs/ShotScribe.log`** (`Sources/ShotScribeUI/Log.swift`, written
  only by the menu bar app via `ShotScribeModel`). Content per line: filenames,
  titles and tags derived from screen content, old→new rename pairs, outcome
  enums with full paths, and error interpolations. Raw OCR text is **never**
  logged — `ShotScribeModel.swift:693` logs `ocr=\(count) chars`, the count
  alone, which is exactly right. But the file was created with default
  permissions (644 — confirmed on the live machine) while the index gets 600.
  Same data category, weaker treatment. **Fixed.**
- **Error strings that reach the log** are bounded at the source, not at the
  logger: `EndpointTitler.Error.http` caps the server body at 160 chars
  (`EndpointTitler.swift:78`), `ClaudeTitler`/`CommandTitler` cap the child's
  stdout/stderr at 200 (`ClaudeTitler.swift:102`, `CommandTitler.swift:74`).
  Track-01 verified no path exists for the API key to reach any of them.
- **Error responses to callers.** The MCP server returns paths and outcome
  detail to its stdio caller — appropriate, since the caller is the user's own
  local agent operating on those very files; there is no anonymous or remote
  client to be terse toward. JSON-RPC protocol errors carry only the method /
  tool name. The CLI prints to the invoking user about their own files. No
  stack traces, no internals-vs-external split needed: every "client" is the
  operator.
- **The search index** (`~/.shotscribe/index.json`) stores up to 8,000 chars of
  accurate OCR per shot — the most sensitive file the app writes. Already
  0600 file / 0700 dir, enforced on every save and pinned by a test. No action.
- **Settings** (`com.joshvanorden.shotscribe` domain): provider kind, model,
  endpoint URL, command template, name template, vocabulary, plus a capped
  rename history (`RenameEvent` date/from/to — titles, no OCR text,
  `ShotScribeModel.swift:985`). No secrets (pinned by `AIProviderTests`). Fine.
- **The network titler** sends OCR text to the user-chosen endpoint — that is
  its function, the user opted in, and `shotscribe ai` prints a
  `text <where it goes>` line so the flow is visible. Plain-http warning was
  track-01's fix; transport generally is track-06's beat.
- **Keychain** — the endpoint key never appears in any output path: it flows
  `Secrets.store.get` → `Authorization` header (`EndpointTitler.swift:50`) and
  nowhere else; UI shows only `endpointKeyStored: Bool` behind a `SecureField`.
- **No debug modes.** No `NSLog`/`os_log`/`debugPrint`, no verbose flag, no
  env-var that widens output anywhere in `Sources/`.

## Risk ranking

- **High:** none.
- **Medium:** none confirmed. (The 644 log is graded Low because stock macOS
  `~/Library` is 0700, so a second local user hits the parent directory first;
  the fix matters for the non-stock cases below.)
- **Low (hardening):**
  1. **Log file world-readable at rest** — screen-derived activity history
     (titles, tags, rename pairs) readable by any process able to traverse the
     parent, and mode 644 travels with the file into backups and copies.
     **Fixed** (see below).
  2. **OCR text on child-process argv** — `ClaudeTitler`/`CommandTitler` pass
     the prompt (screen text) as an argument, visible to same-uid processes via
     `KERN_PROCARGS2`. Deferred: same-uid processes can already read the PNGs
     themselves, so no boundary is actually crossed, and moving the prompt to
     stdin collides with the load-bearing `/dev/null`-stdin fix (CLIs that
     stall waiting on stdin). Not worth the regression risk.
  3. **Log retention** — the log keeps old→new pairs for names the user later
     retitled away, and grows without rotation (191 KB after ~2 months on the
     dev machine). Deferred: this *is* the debugging record the log exists to
     be ("why didn't it rename?"), truncation would delete exactly that, and
     no attack is prevented by rotating it. With 0600 now enforced, retention
     is an owner-only concern; `rm` of the log is always safe.

## Implemented fixes

**One batch — the log gets the index's owner-only rule**
(`security(track-05)` commit):

1. `Sources/ShotScribeUI/Log.swift` — the log file is now **created 0600**, and
   the mode is re-asserted on every append, so a log written 644 before this
   rule tightens on the next line (mirroring how `ShotIndex.save` re-tightens
   the index on every save). Also cut a `urlOverride` test seam, following
   `ShotIndex.storeOverride` — without it, a test of this behaviour would have
   to append to the operator's real log.
   - **Leak prevented:** the category is *screen-derived activity history*
     (titles, tags, filenames, rename pairs, bounded error text) at
     `~/Library/Logs/ShotScribe.log`. A 644 mode exposes it whenever the
     parent-directory assumption fails: a machine where `~/Library` perms were
     loosened, the file copied into a shared location or permissive backup, or
     any log-collection tooling that sweeps `~/Library/Logs`. 0600 makes the
     file carry its own protection instead of borrowing the directory's.
2. `Tests/ShotScribeCoreTests/LogHardeningTests.swift` (new) — pins both
   behaviours: fresh log is 0600, and a pre-existing 644 log tightens on the
   next write **without truncating**. `Package.swift` test target gains the
   `ShotScribeUI` dependency to reach `Log`.

No log line was removed or reworded — debugging value is untouched; only the
file's mode changed.

## Deferred (and why)

- **argv exposure of OCR text to CLI titlers** — no boundary crossed
  (same-uid), and the fix conflicts with a documented load-bearing invariant.
- **Log rotation / retention cap** — prevents no attack; deletes the exact
  history the log exists to provide. Owner-only now that the mode is 0600.
- **MCP tool description embeds the tag vocabulary**
  (`shotscribe-mcp/main.swift:120`) — the caller must know the accepted tags
  for the tool to be usable, and the vocabulary is category names, not content.
  By design, not an exposure.
- **Terse-vs-detailed error split by environment** — not applicable: there is
  no production/remote client anywhere in the system; every consumer of an
  error message is the operator or the operator's own local agent.

## Validation

- `swift build` — clean (all four products).
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` —
  **148 tests, 0 failures**, including the two new `LogHardeningTests`.
- Live check: `~/Library/Logs/ShotScribe.log` was `-rw-r--r--` before the fix;
  the shipped code tightens it to 0600 on the app's next log line, no manual
  step needed.
