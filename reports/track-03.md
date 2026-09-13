# Sub-Agent 3: Authentication & Authorization Integrity

## Assessment

ShotScribe has none of the machinery this track usually audits — no login, no
sessions, no cookies, no tokens minted or validated, no roles. It is a local,
single-user macOS tool, and macOS's own user boundary is its authentication
system. What it *does* have is an authorization story: several principals of
very different trustworthiness can ask the engine to perform privileged file
operations, and the question is whether the checks sit server-side (in the
engine, at each door) or are merely hoped for from the caller.

### The principals, and what each may do

| Principal | Door | Trust | Authority |
|---|---|---|---|
| The operator | CLI flags, app UI | full | everything, including `--force` and destructive clean-up |
| An MCP caller (Claude Code / Cowork) | `shotscribe-mcp` stdio JSON-RPC | semi-trusted — a model that may just have read a hostile page | mechanical ops on **captures** only, by design intent |
| The titler model's output | every door | untrusted | may *propose* a title and tags; both are gated |
| Any other same-UID process | filesystem, `defaults`, env | outside the boundary | can already do anything the user can — not defendable from inside the app |

### The privileged operations, and where their checks live

- **Rename.** Gate: `Naming.isRawCapture` in `Renamer.rename`
  ([Renamer.swift:73](../Sources/ShotScribeCore/Renamer.swift)) — enforced in
  core, before anything else, at every door. `force` bypasses it. The UI door
  **never** passes `force`; the CLI passes it only when the human types
  `--force`. The MCP door passed whatever the calling model sent — the gap
  this track closed (see Medium finding).
- **Tagging.** Gate: `Tagging.accepted` *inside* `Renamer.rename`, matched
  against a closed vocabulary — server-side, applied to proposals from the
  model and from MCP callers alike. This is the codebase's own stated
  invariant ("a tag only ever comes from the vocabulary") and it holds. The
  one soft spot was the operator's tagging-off *switch*, which the MCP door
  did not honour (see Low finding, fixed).
- **Destructive clean-up** (`Cleanup.apply`, including `.delete`). Reachable
  from the UI only, behind an explicit plan-then-confirm flow (`plan` is pure,
  `apply` takes the plan the user just looked at). Not exposed over MCP or the
  CLI at all. Correct by construction.
- **Undo/restore** (`Renamer.restore`) — a plain move, UI-driven only. Fine.
- **Settings as a gate.** A stored name template is validated *before storage*
  (`ShotScribeDefaults.setNameTemplate`) **and re-validated at load**
  (`nameTemplate()` falls back to the default if the stored value no longer
  validates) — so even a poisoned defaults domain cannot make the watcher
  rename ShotScribe's own output. That is defense in depth done right.

### Token validation

The only credential in the system is the optional endpoint API key: Keychain
generic password, `kSecAttrAccessibleWhenUnlocked`, not synchronizable, read
only by `EndpointTitler` (in-process, never on argv). Presence-only Bearer
auth with no expiry is the standard shape for API keys; there is nothing for
ShotScribe to validate locally. Storage and transport were track-01's
territory and are covered there.

### The MCP transport itself

`shotscribe-mcp` speaks newline-delimited JSON-RPC on stdio with no
authentication of its own. That is inherent to MCP's stdio transport: the
client that spawned the process *is* the principal, and the OS already
guarantees only the user's own processes can spawn it. Nothing to add; noted
so nobody mistakes the absence for an oversight.

## Risk ranking

### High (confirmed vulnerability)
- None.

### Medium (likely issue / weak pattern) — fixed
- **MCP `force` was a caller-asserted privilege with no server-side bound**
  (`Sources/shotscribe-mcp/main.swift`, `runRenameScreenshot`). `force: true`
  in the tool arguments bypassed `isRawCapture` — the only gate protecting
  user-named files — and `path` is deliberately unconstrained (`~` allowed).
  Net effect: a calling model could rename **any file the user can write**,
  anywhere on disk, through a tool described as "safe rename". The realistic
  attack: the user screenshots a hostile page, the calling model ingests the
  OCR text (or the page's content directly), injected instructions tell it to
  `rename_screenshot` a name-load-bearing file (`~/.zshrc`, a LaunchAgent
  plist, a contract PDF) with `force: true` — disrupting whatever finds that
  file by name, or effectively hiding it under a plausible date-stamped title.
  The tool's own description said "user-named files are never touched unless
  `force` is true" — but the entity supplying `force` is the model, not the
  user, so the sentence described a consent that was never actually obtained.

### Low (hardening)
- **Caller tags landed even when the operator turned tagging off** — fixed.
  The MCP door builds its `Renamer` with an empty vocabulary when
  `taggingEnabled()` is false, but `Renamer.rename` falls back to the
  *shipped* vocabulary for explicit tags when its own list is empty
  ([Renamer.swift:77](../Sources/ShotScribeCore/Renamer.swift)), so an MCP
  caller's tags were written anyway. Tags stayed vocabulary-bound (the closed
  list held), but a client-supplied field overrode an operator permission
  switch.
- **`ocr_screenshot` / `layout_screenshot` accept any image path** — flag
  only. For an MCP client whose *own* file access is restricted, these are a
  confused-deputy read primitive over every image the user owns. It is also
  documented, deliberate surface ("~ allowed" — the whole point is OCRing a
  shot wherever it sits), and a Claude Code caller can read files anyway.
  Left as accepted design; overlaps track-05 (data exposure).
- **Systemic, informational: the settings domain selects code to execute.**
  `defaults write com.joshvanorden.shotscribe shotscribe.ai …` (or
  `SHOTSCRIBE_DEFAULTS`) can point the titler at `CommandTitler`, which runs
  an arbitrary stored command on every capture — a living-off-the-land
  persistence spot for same-user malware. No privilege boundary is crossed
  (anything that can write the plist already has user-level code execution),
  so this is the macOS trust model, not a ShotScribe bug. Recorded so the
  pattern is a known, deliberate one.

### Strengths worth keeping on record
- `Tagging.accepted` enforced in core, not at doors — a new door cannot forget it.
- Stored templates re-validated on every load, not just at save.
- The UI door cannot express `force` at all; the CLI requires a human to type it.
- The MCP server is pinned to `KeywordTitler` — no nested model call to confuse.
- Destructive operations are UI-only and plan-confirmed; MCP exposes no delete.

## Implemented fixes

Both in `Sources/shotscribe-mcp/main.swift`, committed as
`security(track-03): the MCP rename tool renames captures only, and the
tagging-off switch holds at this door` (14a8ee1). The tool schema is unchanged
— same four tools, same parameters — only two behaviors at the edge tightened,
and both bounds are now stated in the tool descriptions so a caller is told
rather than surprised.

1. **Capture-type bound on `rename_screenshot`**
   ([main.swift:245](../Sources/shotscribe-mcp/main.swift)): the handler now
   refuses any path whose type is not a capture (`Capture.isCapture` — png,
   jpg, jpeg, gif, tiff, heic, bmp, mov, mp4) before the renamer runs, force
   or no force. **What unauthorized action does this prevent?** A
   prompt-injected calling model using `force: true` to rename arbitrary
   non-media files the user owns — config files, launch agents, documents —
   for disruption or concealment. The documented use survives intact:
   `force` still renames a screenshot the user had renamed, anywhere on disk.
2. **The operator's tagging switch enforced at the door**
   ([main.swift:168](../Sources/shotscribe-mcp/main.swift),
   [main.swift:252](../Sources/shotscribe-mcp/main.swift)): a startup
   `taggingOn` constant now gates caller-supplied `tags`; while tagging is
   off they are dropped before reaching the renamer, instead of riding its
   empty-vocabulary fallback onto the file. **What unauthorized action does
   this prevent?** A caller filing the user's screenshots under Finder tags —
   visible in Finder and Spotlight — after the operator explicitly turned
   filing off; client-supplied data no longer overrides an operator
   permission setting.

## Deferred

- **Confining MCP rename/OCR paths to the configured screenshot folder.**
  It would be the stronger authorization statement, but "path (~ allowed)" is
  documented surface and renaming a capture that sits on the Desktop or in a
  project folder is a legitimate, advertised use. The capture-type bound
  removes the sharp end (arbitrary-file rename); folder confinement would
  need the operator's product call.
- **`Renamer.rename`'s shipped-vocabulary fallback for explicit tags**
  ([Renamer.swift:77](../Sources/ShotScribeCore/Renamer.swift)). It
  contradicts the type's own doc comment ("Empty — the default — means this
  renamer files nothing") but has been there since tags landed (cb79fcc) and
  bare `Renamer(titler:)` callers plus tests lean on it. I enforced the
  *consequence* at the affected door rather than changing core semantics in a
  sweep; deciding what an empty vocabulary means is an API decision for the
  operator.
- **Rate limiting on MCP tools** — meaningless over stdio with one local
  client; deliberately not added.
- **Anything touching the endpoint key's transport** — track-01 assessed and
  deferred the behavioral half (refusing Bearer-over-plain-http); same
  posture kept here, no double-fix.

## Validation

- Build: **clean** — `swift build -c release`, all four products.
- Tests: **144/144 pass**
  (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`).
  The MCP server is an executable target, so the new behavior is not
  XCTest-reachable; it was verified end-to-end instead:
- Live JSON-RPC smoke test against the built `shotscribe-mcp` binary, in the
  session scratchpad with scratch `defaults` domains (created and deleted in
  the same run, real settings untouched):
  - `rename_screenshot` on `secret-notes.txt` with `force: true` →
    `isError: true`, "Not a capture file", file untouched on disk.
  - Same call on `myphoto.png` with `force: true, dry_run: true` →
    "would rename → 2026-09-13 1846 Legit Title.png" (capture types still pass).
  - Raw-named capture with `tags: ["code"]` under a tagging-off domain →
    renamed with **no** "Tagged:" in the outcome; identical call under a
    tagging-on domain → "Tagged: code."
