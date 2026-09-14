# /agent-team — Run Summary

- Worktree: `/private/tmp/claude-503/-Users-vanorden-git-personal-active-shotscribe/db4442c6-73ad-4a8c-8e14-3fac0c61954c/scratchpad/sumtmp`
- Branch:   `unknown`
- Generated: 2026-09-14T00:43:15Z

## Per-track reports

### track-01.md

# Sub-Agent 1: Secrets & Credential Exposure

## Assessment

ShotScribe holds exactly one secret — the optional API key for the endpoint
titler — and the handling around it is unusually disciplined for a side
project. The sweep found **no hardcoded secrets, no committed credentials, no
`.env` usage, and no secret-bearing log lines**. The one substantive gap was a
warning that under-stated an exposure: the plain-http notice named the OCR text
but not the API key that rides the same unencrypted request. Fixed (copy only).

What was checked, and what was found:

- **Hardcoded keys / tokens** — none. A full-history scan
  (`git log --all -p -G` for `sk-…`, `AKIA…`, `ghp_…`, `xox…` shapes) came back
  empty. The only key-shaped strings in the tree are obvious test dummies
  (`sk-test`, `sk-abc` in `Tests/ShotScribeCoreTests/AIProviderTests.swift:79,155`).
- **The one real secret** — the endpoint API key — lives in the login Keychain
  via `Sources/ShotScribeCore/Secrets.swift` (`KeychainStore`): service-scoped
  generic password, `kSecAttrAccessibleWhenUnlocked`, delete-then-add on write.
  Tests swap in `MemoryStore` so they never touch the operator's keychain.
- **Settings never carry the key.** `Sources/ShotScribeCore/Settings.swift`
  persists the provider (kind, model, endpoint URL, command template) but not
  the key; `AIProviderTests.swift:159` *pins* that the key never lands in the
  UserDefaults suite. This invariant is test-enforced, not just convention.
- **UI handling** — `Sources/ShotScribeUI/ShotScribeSurface.swift:867` uses
  `SecureField`, clears the draft after save, and the model exposes only
  `endpointKeyStored: Bool` (`ShotScribeModel.swift:89`, commented "Never the
  key itself"). The key has no read-back path in the UI.
- **No CLI path for the key** — `shotscribe` takes no `--api-key` style flag,
  so the key can never land in shell history or `ps` argv. Entry is app-UI-only.
- **Transit** — the key travels only as an `Authorization: Bearer` header
  (`EndpointTitler.swift:50`), never in the URL, so it cannot leak into server
  access logs via query string.
- **Logging** — `Sources/ShotScribeUI/Log.swift` call sites log filenames,
  titles, tags, and error descriptions. `EndpointTitler.Error.http` includes at
  most 160 chars of the *server's* response body (`EndpointTitler.swift:78`) —
  server-controlled text, not the credential. No log line can contain the key.
- **Build/ship credentials** — `scripts/package-app.sh` uses
  `xcrun notarytool --keychain-profile "$APPLE_NOTARY_PROFILE"`; only the
  profile *name* appears in env/echo, credentials stay in the keychain.
  `apple-ship.config.json` carries `"credentialBackend": "keychain"` and no
  secret material.
- **`~/.config/llm/provider.json`** (`LLMPreference.swift`) — ShotScribe reads
  only `provider`/`endpoint`/`model` from it; no key field is read or written.

### Attack scenarios considered

1. **MITM on a plain-http remote endpoint** (the finding that led to the fix):
   `AIProvider.availability()` warns about `http://` to a non-local host, but
   the warning said only that *the text* travels unencrypted — while
   `EndpointTitler` attaches the Bearer key to that same cleartext request. An
   operator could reasonably conclude their key was safe and only screenshot
   text was exposed. A network-position attacker captures the credential, not
   just one screenshot's text — a durable compromise instead of a one-shot one.
2. **Key exfiltration via settings/export** — blocked by design + pinned test.
3. **Key in logs** — no path found; error bodies are capped and key-free.
4. **Key on child-process argv** — impossible; only `EndpointTitler` (network,
   in-process) consumes the key. CLI titlers never see it.
5. **Screenshot OCR text as a *carrier* of third-party secrets** — the OCR text
   itself can contain on-screen credentials (a password field, an open `.env`).
   It is passed as one argv element to CLI titlers (`ClaudeTitler.swift:92`,
   `CommandTitler.swift:51`), where any same-UID process can read it via
   `ps`/`KERN_PROCARGS2`. Noted as Low: same-UID malware could read the
   screenshot files directly, and `/dev/null` stdin is a documented load-bearing
   design constraint (CLIs stall reading stdin). The index file's sensitivity is
   already called out in the CLI usage text.

## Risk ranking

### High (confirmed vulnerability or exposure)
- None.

### Medium (likely issue or weak pattern)
- **API key sent over plain http to remote hosts, with a warning that omitted
  the key** — `Sources/ShotScribeCore/AIProvider.swift:191` +
  `EndpointTitler.swift:50`. The *warning half* is fixed below. The *behavioral
  half* (actually attaching the key over cleartext http) is deferred — see
  Deferred.

### Low (hardening opportunity)
- **OCR text on child-process argv** (`ClaudeTitler.swift:92`,
  `CommandTitler.swift:48-51`) — same-UID processes can read screenshot text
  (which may itself contain on-screen secrets) via `ps`. Not fixed: stdin is
  deliberately `/dev/null` (documented CLI-stall constraint), and the realistic
  attacker in this trust domain can read the source PNGs anyway.
- **`Secrets.store` is a mutable global** (`Secrets.swift:12`) — any in-process
  code can swap the store. It exists as the test seam; in a single-user app
  with no plugin surface this is acceptable. Flag only.
- **Child processes inherit the full parent environment**
  (`CommandRunner.swift:24-27`). The app sets no secret env vars of its own, so
  today this leaks nothing; worth remembering if that ever changes.
- **Up to 160 chars of server error body reach the log**
  (`EndpointTitler.swift:78` → `ShotScribeModel.swift:703`). Server-controlled,
  capped, same-user log file. Flag only.

## Implemented fixes

- **`Sources/ShotScribeCore/AIProvider.swift:191`** — the plain-http-to-remote
  warning now reads "…the text read off each capture, **and any saved API
  key**, travel unencrypted to that host." **Attack prevented:** an operator
  keeping a real key while pointing at an `http://` gateway on the strength of
  a warning that implied only screenshot text was at risk — the informed-consent
  line now covers the credential a MITM would actually take. **Why safe:** copy
  only, no behavior change; the only test touching this string asserts
  `.contains("unencrypted")` (`AIProviderTests.swift:147`), which still holds.
  This extends the 1.6.1 sweep's own "plain http is said out loud" decision.

## Deferred

- **Refusing to attach the Bearer key over plain http to non-local hosts**
  (`EndpointTitler` / `makeTitler`). This is the actual attack-blocker, but it
  would silently break a legitimate setup — an internal gateway on a trusted
  LAN that requires a token over http — and the project's stated posture is
  informed consent ("said out loud") rather than refusal. Behavioral change of
  this kind needs the operator's call, not a sweep's.
- **No rotation performed** — no live secret was found exposed anywhere, so
  nothing needs rotation. The operator's own endpoint key (if one is stored)
  was never at rest outside the Keychain in any commit.

## Validation

- Tests: **143/143 pass** (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`)
- Lint: no linter configured in this repo (none run)
- Build: **clean** (`swift build -c release`, all four products, 24.6s)
- Security scans: full-history grep for common credential shapes (AWS, OpenAI,
  GitHub, Slack) — no hits; no `.env` files present or ignored-but-expected;
  working tree contains no secret material outside the Keychain.

---

### track-02.md

# Sub-Agent 2: Input Validation & Injection Risk

## Assessment

ShotScribe has no web surface — no API endpoints, query params, forms, headers
or uploads. Its untrusted inputs are stranger and better-considered than most:
**pixels on the user's screen** (OCR text from possibly-hostile pages), **the
titler model's replies** (indirectly attacker-steered via prompt injection
through that OCR text), and **MCP JSON-RPC tool arguments** from a calling
model that itself just read untrusted content. The dangerous sinks are process
spawning, the filesystem (renames), one JSON POST, and the terminal.

The codebase is unusually deliberate about these boundaries — the 1.6.1 sweep
already forced command names through `Executables.isPlainName` before the one
`zsh -lc` interpolation, and tags are vocabulary-gated by design. The gaps
found were at the character level: both label boundaries passed Unicode
control/format characters, and the MCP server handed OCR text to callers with
no marking that it is data, not instructions.

### Where untrusted data enters, and where it flows

| Entry | Flows to | Sink class |
|---|---|---|
| Screenshot pixels → Vision OCR | titler prompts, `{app}` token, `~/.shotscribe/index.json`, `find` snippets, MCP callers | argv, filename, terminal, calling model |
| Titler reply (`claude`/command stdout, endpoint JSON) | `LabelCleaner` → `Naming.sanitize` → **filename on disk**; printed by CLI `label`; shown in panel | filesystem, terminal |
| MCP `tools/call` args (`path`, `title`, `tags`, `force`, `count`) | OCR, `Renamer.rename`, `Tagging` | filesystem |
| Stored settings (command template, endpoint URL, template layout, vocabulary) | `CommandTitler.argv`, `EndpointTitler`, `Naming.filename` | argv, network, filename |
| `~/.config/llm/provider.json`, `index.json` | provider suggestion, search | none dangerous |

### Sink-by-sink findings

- **Command injection — none.** `CommandRunner` runs argv arrays via `Process`,
  never a shell, with `{prompt}` always one whole argument
  (`CommandTitler.argv`, `ClaudeTitler.complete`). The single shell use —
  `zsh -lc "command -v <name>"` in `Executables.compute` — is reachable only
  after `isPlainName` restricts the name to `[alnum._+-]` (the 1.6.1 fix), and
  path-shaped names are checked as paths, never shelled. Verified: the only
  two `Process()` constructions in the tree are these.
- **SQL / template injection — no SQL, no template engine.** `NameTemplate` is
  token replacement into a filename, validated before storage (`Naming.validate`
  refuses unknown tokens, path-illegal characters, and the self-rename shape).
- **Unsafe deserialization — none.** Everything is `JSONDecoder`/
  `JSONSerialization`; the one `PropertyListSerialization` reads macOS's own
  capture xattr into a `Bool`. No `NSKeyedUnarchiver`, no eval-alikes.
- **Path traversal — blocked, with a character-level gap (fixed below).**
  `Naming.sanitize` strips `/\:*?"<>|`, drops dot-only words (`..`), and
  renames land via `dir.appendingPathComponent` in the file's own directory.
  But Unicode control (Cc) and invisible-format (Cf) characters passed both
  `LabelCleaner.clean` and `Naming.sanitize`.
- **MCP argument validation — sound.** `count` clamped 1–20; `title` goes
  through `LabelCleaner` + `Naming.sanitize`; `tags` through
  `Tagging.accepted` against the closed vocabulary (the repo's own invariant);
  `path` may be any file, but see Deferred on `force`.
- **Endpoint POST** — body built by `JSONSerialization` (no string-spliced
  JSON), key only in a header. Reply parsed defensively (`EndpointTitler.parse`).

## Risk ranking

### High (confirmed)
- None.

### Medium (likely / weak pattern)
- **Control and bidi/format characters survived both label boundaries**
  (`Sources/ShotScribeCore/LabelCleaner.swift`, `Naming.sanitize`). A
  prompt-injected titler reply could put U+202E (right-to-left override) into
  a filename — Finder then displays the name reversed, misrepresenting the
  extension/content — or a raw ESC into text the CLI prints, driving the
  operator's terminal. **Fixed.**
- **MCP OCR output carried no untrusted-data marking**
  (`Sources/shotscribe-mcp/main.swift`, `ocr_screenshot` / `layout_screenshot`).
  A screenshot of a hostile page IS a prompt-injection carrier into the calling
  model, which typically holds Bash/Write. **Fixed** (advisory, defense-in-depth
  — the caller's harness is the real control).

### Low (hardening / flag only)
- **MCP `rename_screenshot` with `force: true` renames any file the user can
  write**, not just captures (`Renamer.rename` skips `isRawCapture` under
  force). In-directory move only, extension preserved, and the caller (Claude
  Code) almost always holds broader tools than this server grants — but a
  prompt-injected caller could scramble names of arbitrary user files.
  Restricting `force` to `Capture.isCapture` files would narrow the documented
  contract ("Also rename files that aren't raw macOS captures"), so flagged,
  not fixed.
- **`shotscribe find` prints index text and on-disk filenames raw to the
  terminal.** Vision OCR emits glyphs, not control bytes, and names ShotScribe
  writes are now sanitized — but a file named by *other* software could still
  carry escapes into the terminal. Fixing would mean scattering print-time
  filtering; flagged.
- **`SendToClaude.quoted` escapes `"` but not `\`** — a path ending in a
  backslash would corrupt the quoted pasteboard line. It feeds a chat prompt,
  not a shell; malformed, not injectable. Flagged.
- **MCP tool schema embeds the live vocabulary** into `rename_screenshot`'s
  description — a hostile vocabulary entry would be prompt text to the caller.
  Requires same-user defaults write, which is outside this trust boundary.

## Implemented fixes

1. **`Sources/ShotScribeCore/Naming.swift` — `sanitize` now treats Unicode
   Cc + Cf as illegal** (`.union(.controlCharacters)`; that set is exactly
   categories Cc and Cf). **Injection class prevented:** filename spoofing /
   path-adjacent injection — a bidi override or control byte in a
   model-supplied title can no longer reach a filename ShotScribe writes, so
   `Report\u{202E}gnp.png` can't display as `Report png.png` in Finder and a
   NUL can't truncate the name at the syscall layer. Covers every door: titler
   replies, MCP `title`, `{app}` read off the chrome, and template layouts at
   render (`tidy` routes through `sanitize`).
2. **`Sources/ShotScribeCore/LabelCleaner.swift` — Cc/Cf stripped from the
   reply after the first-line cut** (after, so `\n`/`\r` still perform the cut
   the existing tests pin). **Injection class prevented:** terminal escape
   injection — CLI `label`, the panel, and the MCP suggested title print this
   value without passing through `sanitize`, and a raw ESC in it could
   manipulate the operator's terminal (title, screen state).
3. **`Sources/shotscribe-mcp/main.swift` — `ocr_screenshot` and
   `layout_screenshot` descriptions now mark their output as screen content to
   be treated as data, never instructions.** **Injection class prevented:**
   indirect prompt injection via screenshot — the standard MCP mitigation for
   tools that return attacker-authored text to a tool-holding model. Additive
   sentences only; tool names, schemas and result formats unchanged.
4. **`Tests/ShotScribeCoreTests/HardeningTests.swift` —
   `testALabelCannotSmuggleControlOrBidiCharacters`** pins U+202E, ESC and NUL
   stripping at both boundaries, and pins that U+202F (macOS's own narrow
   no-break space in capture names — Zs, not a control) is untouched.

All three code fixes are boundary-level (the two label boundaries and the tool
contract text), none change any API surface, and none remove code.

## Deferred

- **Restricting MCP `force` renames to capture files** — would narrow a
  documented tool contract; the operator should decide whether "rename any
  file" is a feature or a bug (hard constraint: no breaking API contracts).
- **Print-time filtering of foreign filenames in `find`/`eval` output** — the
  attack needs a hostile file already named with escapes in the watched
  folder; filtering at every `print` violates "validation at boundaries only."
- **Backslash escaping in `SendToClaude.quoted`** — cosmetic-severity; the
  spelling is pinned by `SendToClaudeTests` against the shipped skill, so
  changing it is a compatibility decision, not a sweep's.
- **`Naming.validate` does not flag control characters typed into a layout** —
  render-time `sanitize` now strips them anyway; refusing them at save would
  change the settings-pane error contract for no added protection.

## Validation

- Tests: **144/144 pass** (was 143; one added)
  (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`)
- Build: **clean**, all four products (`swift build -c release`, 8.8s)
- Lint: no linter configured in this repo (none run)
- Grep sweeps: only two `Process()` sites (both in `CommandRunner`); no
  `NSKeyedUnarchiver` / `NSAppleScript` / `system(` anywhere in `Sources/`.

---

### track-03.md

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

---

### track-04.md

# Track 04 — Dependency & Supply Chain Risk

Target: ShotScribe (Swift package, macOS 13 floor). Audited 2026-09-13 on
`security/20260913-1829`.

## Assessment

**The "zero third-party dependencies" claim is true, verified at every layer.**

- `Package.swift` declares **no `dependencies:` array at all** — no external
  packages, no binary targets, no build plugins, no unsafe flags. Five products,
  six targets, all local.
- **No lockfile of any ecosystem exists** — no `Package.resolved` (correct:
  SwiftPM writes one only when there is a graph to pin), no `package.json`,
  `requirements.txt`, `pyproject.toml`, `Gemfile`, `Podfile`, or `Cartfile`
  anywhere in the tree. Lockfile↔manifest sync is trivially satisfied: both
  are empty.
- `.build/workspace-state.json` shows empty `dependencies`, `artifacts` and
  `prebuilts`; `.build/checkouts/`, `.build/repositories/` and
  `.build/artifacts/` are all empty directories. Nothing was ever fetched.
- **No `.gitmodules`, no `.github/` workflows** — there is no CI pipeline to
  poison and no submodule to redirect.
- **Import surface is Apple-only**: Foundation, AppKit, SwiftUI, Vision,
  AVFoundation, Security, ServiceManagement, QuickLookThumbnailing,
  UniformTypeIdentifiers, CoreGraphics, Darwin (plus XCTest in tests).
- **Build and packaging scripts fetch nothing.** `scripts/package-app.sh` uses
  only `git`, `swift build`, `codesign`, `ditto`, `hdiutil`, `notarytool`,
  `stapler`; `make-iconset.sh` uses `sips`/`iconutil`. No `curl`/`wget`/clone
  in any script. The one `curl` in the repo is in `README.md` and downloads a
  markdown skill file to disk — it is not piped to a shell.

With no package graph, the live supply-chain surface is **runtime, not build
time**: the titlers exec external CLIs (`claude`, `codex`, `gemini`,
`cursor-agent`, `ollama` presets). That resolution is well built:
`Executables.resolve` (`Sources/ShotScribeCore/CommandRunner.swift:76`) probes
a fixed list of well-known install paths first, validates a bare name with
`isPlainName` (alphanumerics plus `._+-`) before the `zsh -lc "command -v …"`
fallback ever runs — so a pasted setting cannot smuggle shell metacharacters —
and never installs, updates, or downloads any of these tools itself.

Two facts worth naming about that surface:

1. `~/.local/bin` and `/opt/homebrew/bin` sit early in the candidate list and
   are user-writable. Anything able to plant a fake `claude` there already
   runs as the user — same trust domain, not a boundary ShotScribe can hold.
   Noted, not fixable from inside the account.
2. This surface is live, not theoretical: **macOS flagged the Codex CLI cask
   0.118.0 as malware today (2026-09-13)**. ShotScribe would invoke whatever
   `codex` is installed, but it does not bundle or auto-install any provider
   CLI, so the exposure belongs to the user's install channel (Homebrew), and
   Gatekeeper/XProtect plus the preset's `--sandbox read-only` flag are the
   mitigations. No change to ShotScribe warranted.

`EndpointTitler` (the only network code) POSTs OCR text to a user-configured
endpoint — a data-flow/transport concern for tracks 05/06, not code supply
chain. No telemetry, no update check, no auto-update framework (no Sparkle),
matching SECURITY.md's claims.

## Risk ranking

**High (confirmed):** none.

**Medium (likely):** none.

**Low (hardening):**

1. **No regression guard on the zero-dependency invariant.** The property the
   README and SECURITY.md lean on was enforced only by habit — a quiet
   `.package(` line in a skimmed PR of a public repo would put outside code
   into every user's build. → **Fixed** (see below).
2. **Runtime CLI binaries resolve from user-writable directories** — same-user
   trust domain, flag only (above).
3. **The README's skill install curls `skills/screenshot/SKILL.md` from the
   unpinned `main` branch** (`README.md:217`). A skill file is agent
   instructions, so a repo compromise changes what the skill tells Claude to
   do on installers' machines. It is fetched over TLS from the project's own
   repo, written to a file (never executed), and installed once with no
   auto-update — inherent to any install-from-repo flow. Pinning to a tag
   trades freshness for immutability; maintainer's call, deferred.
4. **No CI** means the test suite (including the new guard) runs only on
   developer machines. The repo states this is deliberate ("There is no CI.
   Tests run locally only."). Systemic observation, out of scope for this
   pass.

## Implemented fixes

**Commit `76b9217` — `Tests/ShotScribeCoreTests/SupplyChainTests.swift` (new,
2 tests):**

- `testTheManifestStaysDependencyFree` asserts `Package.swift` contains no
  `.package(`, no `.binaryTarget(`, and no `.plugin(`/`plugins:`.
- `testNoResolvedDependencyGraphExists` asserts no `Package.resolved` exists
  at the repo root — a second tripwire that fires even if a dependency arrives
  by a spelling the manifest check misses.

**What attack this prevents:** silent introduction of third-party code —
a dependency, prebuilt binary, or compile-time plugin — into a public repo
whose documented security posture rests on there being none. Adding a real
dependency remains possible; it now has to update this test out loud, the same
way `NameTemplateTests` pins the default filename.

## Deferred (and why)

- **Pinning the README skill-install URL to a release tag** — doc-only change
  with a staleness tradeoff; flagged for the maintainer rather than churned
  here.
- **Runtime binary trust** (`~/.local/bin` etc.) — cannot be hardened from
  within the same user account without breaking how every provider CLI is
  legitimately installed; SECURITY.md already documents the command-preset
  trust model.
- **CI for the test suite** — a project-direction decision, not a surgical
  fix.

## Validation

- **Scanner output: no scanner ran, because there is nothing to scan.** No
  lockfile or manifest of any package ecosystem exists (verified by find over
  the tree). `osv-scanner`, `pip-audit`, and `safety` are not installed on
  this machine and the track rules forbid installing scanners in this pass;
  `npm` exists but there is no Node manifest. Manual verification stood in:
  empty `dependencies`/`artifacts`/`prebuilts` in `.build/workspace-state.json`
  and empty `.build/checkouts|repositories|artifacts` directories.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`:
  **146 tests, 0 failures** (baseline before this track: 144, 0 failures).
- `swift build -c release`: **Build complete**, all products.

---

### track-05.md

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

---

### track-06.md

# Sub-Agent 6: Transport & Configuration Security

## Assessment

Most of this track's checklist does not apply to ShotScribe, and saying so
precisely is the assessment. There is **no server**: no HTTP listener, no
routes, no HTML served to a browser, no origin that could make a CORS request,
no session a CSRF token would protect. CSP, HSTS, X-Frame-Options,
Referrer-Policy, CORS policy and middleware ordering are properties of a thing
ShotScribe deliberately is not. Verified, not assumed: `URLSession` appears in
exactly one file (`Sources/ShotScribeCore/EndpointTitler.swift:75`), and
`NWListener`/`NWConnection`/`bind` appear nowhere; the MCP server speaks
JSON-RPC over **stdio** only, so its "transport" is the pipe to the local
caller, with process identity as the boundary (track-03's territory).

The real transport surface is one **outbound** HTTP client — `EndpointTitler`,
which POSTs OCR-derived screen text plus an optional Bearer key to a
user-configured OpenAI-compatible endpoint — and the configuration channels
that decide where that request goes. Everything below is about that seam.

### What was verified, and how

1. **TLS is never weakened.** No custom `URLSession` delegate overrides server
   trust, no `NSAppTransportSecurity` dictionary appears in the generated
   Info.plist (`scripts/package-app.sh:33-52`), so certificate validation is
   the system default everywhere. There is nothing here to tighten — the
   important check was that nothing loosens it, and nothing does.

2. **App Transport Security is asymmetric across the four doors** — confirmed
   empirically, not from documentation. A bare compiled Swift binary (the same
   shape as `shotscribe` and `shotscribe-mcp`) was probed against
   `http://ats-probe.invalid` and the TEST-NET IP `http://192.0.2.1`: the
   errors were −1003 (DNS attempted) and −1001 (TCP connect attempted), never
   −1022 (ATS block). **ATS does not enforce for the unbundled CLI/MCP
   binaries** — cleartext HTTP to any remote host is possible there. The
   packaged app, which declares no ATS exceptions, keeps whatever enforcement
   the OS applies to bundles. Consequence: the operative cleartext control is
   not the OS but the app's own warning — `AIProvider.availability()` says
   "plain http: the text read off each capture, and any saved API key, travel
   unencrypted to that host" for any non-loopback/non-`.local` host
   (strengthened by track-01, pinned by
   `AIProviderTests.testPlainHTTPToARemoteHostIsSaidOutLoud`). That warning
   lives in Core, so every door that surfaces availability shows it.

3. **The Bearer key cannot be replayed to a third host via redirect** — also
   confirmed empirically. A loopback pair (127.0.0.1:9060 → 307 →
   127.0.0.1:9061, ports from the personal-backend band) with a client built
   exactly like `EndpointTitler` showed URLSession following the cross-origin
   redirect and re-sending the POST body, but **stripping the Authorization
   header**: the redirector saw `Bearer test-…`, the target saw none. CFNetwork
   already enforces what a custom redirect delegate would have added, so no
   delegate code was written — adding unverifiable "hardening" to the one
   network file would have been pure risk.

4. **The endpoint URL was stored and consumed without a scheme check** — the
   one confirmed gap, now fixed. `ShotScribeDefaults.setAIProvider` persists
   the provider verbatim (`Settings.swift:102`; the endpoint field has no
   validation gate the way name templates do), and `makeTitler()` required
   only that `URL(string:)` parse. A stored `file:` or `ftp:` endpoint would
   have handed URLSession a non-web URL: for `file:`, the "POST" returns the
   file's bytes, `parse()` reads them as a chat reply, and local file content
   flows into filenames, Finder tags, the log and the index. The stored value
   does not always arrive through the AI tab's text field — `defaults write`,
   a `SHOTSCRIBE_DEFAULTS` domain, or the machine preference file can all
   plant it — so the check belongs in Core, at both the readiness line and
   the factory.

5. **Configuration channels are consent-mediated where it matters.** The
   machine-level preference `~/.config/llm/provider.json` (`LLMPreference`)
   can name an arbitrary endpoint, but it is only ever a *suggestion* — the UI
   shows "This Mac prefers …" with a Use-it button
   (`ShotScribeSurface.swift:820-825`); nothing auto-applies it. The
   `SHOTSCRIBE_DEFAULTS` / `SHOTSCRIBE_INDEX` environment overrides require
   control of the process environment, which is already code-execution as the
   user; they are dev affordances, not an exposure. No debug mode, verbose
   traceback surface, or admin panel exists to be left on: the closest
   analogue, `~/Library/Logs/ShotScribe.log`, was made owner-only by track-05
   and never carries raw OCR text.

6. **Residue of the one network call** (fixed): `URLSession.shared` carries a
   persistent cookie jar and a disk `URLCache` shared with nothing else in
   this process worth sharing with. A cooperating endpoint could set durable
   cookies (a cross-call tracking channel), and any cacheable reply — text
   derived from the user's screen — could land under `~/Library/Caches`,
   outside the files whose permissions tracks 03/05 tightened.

## Risk ranking

- **High (confirmed):** none.
- **Medium (likely):** non-web URL schemes reached the network titler's
  factory unchecked (finding 4). **Fixed.**
- **Low (hardening):** shared-session cookie/cache residue (finding 6,
  **fixed**); ATS asymmetry between the bundled app and the CLI/MCP binaries
  (finding 2, **deferred — documented here**); cleartext HTTP to a remote host
  remains *possible with informed consent* rather than refused (finding 2,
  **deferred by design**).

## Implemented fixes

1. **`security(track-06): only http(s) reaches the endpoint titler, from any
   door`** — `AIProvider.isWebScheme` allowlists `http`/`https`
   (case-insensitive) in both `availability()` (readiness line explains: "The
   endpoint must be an http or https URL.") and `makeTitler()` (no titler is
   built otherwise, matching the existing malformed-URL behaviour). New test
   `AIProviderTests.testOnlyWebSchemesReachTheEndpointTitler` pins `ftp:`,
   `file:`, `gopher:` out and uppercase `HTTPS:` in.
   **Attack class mitigated:** configuration-channel scheme smuggling — a
   planted `file:` endpoint turning "the only network code" into a local file
   reader whose contents flow into names, tags, the log and the index.

2. **`security(track-06): the endpoint call keeps no cookies and no cache on
   disk`** — `EndpointTitler` now uses one private
   `URLSession(configuration: .ephemeral)` instead of `URLSession.shared`.
   TLS validation and system proxy behaviour are unchanged; connection reuse
   is kept by sharing the session across calls.
   **Attack class mitigated:** screen-derived request/response data and
   server-set cookies persisting under `~/Library` outside the app's
   permission-tightened files, and cookie-based cross-call tracking by the
   endpoint.

## Deferred, and why

- **Refusing to attach the Bearer key to cleartext remote requests** (or
  refusing cleartext remotes outright). This would break the setup the code
  explicitly supports — a plain-http LAN gateway that wants a key — and the
  informed-consent warning from track-01 already names exactly what is
  exposed. Forcing it is a product decision, not a patch. If taken up: gate it
  in `EndpointTitler.request` so all doors inherit it.
- **ATS parity for the CLI/MCP binaries** (embedding an `__info_plist`
  section, or an in-code cleartext refusal). Same product decision as above
  wearing a build flag: it would hard-fail LAN named-host setups
  (`http://myserver.lan`) that currently work from the CLI. Flagged for the
  maintainer; the report's empirical probe is the evidence to decide with.
- **Certificate pinning** — wrong tool here: the endpoint is user-chosen and
  arbitrary by design; pinning would break every legitimate configuration to
  defend against a CA-compromise attacker far outside this threat model.
- **CSP / HSTS / X-Frame-Options / CORS / middleware ordering** — not
  applicable; there is no server, no served HTML, and no browser origin. No
  header was added anywhere because there is no response to add it to.
- **Redirect-policy delegate** — verified unnecessary (finding 3); recorded so
  a future reader doesn't add one "just in case" into the one network file.

## Validation

- Full suite after both fixes: **149 tests, 0 failures** via
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`;
  `swift build` clean for all products.
- ATS probe: compiled standalone binary, `http://ats-probe.invalid` → −1003
  and `http://192.0.2.1` → −1001 (both *attempted*, neither ATS-blocked);
  `.invalid`/TEST-NET targets so no probe traffic could leave the machine.
- Redirect probe: loopback 9060→9061 (personal-backend port band), 307 with
  Authorization set exactly as `EndpointTitler.request` sets it; result
  `{"redirector_saw_auth": "Bearer …", "target_saw_auth": null,
  "target_body_present": true}`. Both probe servers exited; ports verified
  clear afterwards.

---

### track-07.md

# Sub-Agent 7: Unsafe Patterns & Runtime Risk

## Assessment

ShotScribe is a Swift package with no dynamic execution surface at all — no
eval-alikes, no `NSAppleScript`, no scripting bridges, no plugin loading. Its
runtime risk lives in three places: **process spawning** (`CommandRunner`, the
one runner every CLI titler shares), **file operations under concurrency**
(the folder watcher, the renamer's check-then-move, an index file shared by
four processes), and **trust of external text on the failure path** (a child
CLI's streams, an endpoint's HTTP error body — shown to the operator raw,
where the *success* path had already been sanitized by track-02).

### Pattern-by-pattern findings

- **Dynamic execution — none.** The only two `Process()` sites are in
  `Sources/ShotScribeCore/CommandRunner.swift`: the argv-array runner (no
  shell), and the one `zsh -lc "command -v <name>"` in `Executables.compute`,
  reachable only after `isPlainName` restricts the name to `[alnum._+-]` and
  path-shaped names are checked as paths. Verified sound; not touched.
- **Insecure randomness — not applicable.** The only randomness in the tree
  is a `UUID()` for a SwiftUI row identity (`RenameEvent.id`). No tokens,
  session IDs, or filenames derive from randomness anywhere; nothing needs
  `SecRandomCopyBytes`.
- **Unsafe file access** — rename targets are always
  `dir.appendingPathComponent(sanitizedName)` in the file's own directory;
  `Naming.sanitize` strips separators, dot-only words, and (since track-02)
  Cc/Cf. The MCP door tilde-expands caller paths by design ("~ allowed") and
  is gated to capture extensions (track-03). No traversal path found.
- **TOCTOU around file ops — present but fail-safe.** Every
  `Naming.uniqueName` check-then-`moveItem` (rename, retitle, undo, archive)
  can lose its race, but `FileManager.moveItem` **refuses to overwrite** — the
  loser throws and the error surfaces; no file can be clobbered through this
  window. Annotated here rather than churned.
- **Unsafe concurrency — one real hole, fixed.** `FolderWatcher.stop()`
  cancelled the dispatch source but not the debounced scan already queued on
  its serial queue, so a "stopped" watcher could still report a file — and
  trigger a rename — for up to half a second. Everything else checks out:
  `seen`/`debounce` are confined to the watcher's queue (`ignore` uses
  `queue.sync`), `ShotIndex`'s load-modify-save runs under an `NSLock`,
  `Executables`' cache is locked, `DataBox` establishes happens-before via
  `DispatchGroup.wait`, and the app model is `@MainActor`.
- **Trust of external systems** — `EndpointTitler` keeps system TLS validation
  and proxies (no `URLSessionDelegate` trust override anywhere), the session
  is ephemeral (track-06), the scheme is allowlisted (track-06), and replies
  are parsed defensively then label-sanitized. The gap was the **error body**:
  up to 160 bytes of a server-controlled HTTP body (and up to 200 bytes of a
  child CLI's streams in `ClaudeTitler`/`CommandTitler`) were thrown verbatim,
  and those strings reach the operator's terminal (`onTitlerError` → stderr),
  the panel (`lastError`), and the log (`Log.write("titler FAILED: \(error)")`
  — reflection prints the raw associated value, not `errorDescription`).
  Fixed at construction.
- **AI-slop security — none found.** No TODO/FIXME stubs in production paths;
  every comment claiming validation has real code under it
  (`Naming.validate`, `Tagging.accepted`, `Executables.isPlainName`,
  `LabelCleaner.clean` were each read against their claims). The codebase's
  security comments are unusually honest — several document their own attack
  model correctly.

### Looks scary, verified constrained (annotated, not churned)

- **Watchdog pid-reuse race** (`CommandRunner.swift`): `kill(pid, SIGKILL)`
  three seconds after SIGTERM could theoretically hit a reused pid. The
  `proc.isRunning` guard sits immediately before the kill, the child holds its
  pid as a zombie until Foundation reaps it, and the window is microseconds
  wide requiring pid wraparound. Foundation offers no reap-safe kill;
  rewriting the runner for this is not a surgical fix.
- **`Cleanup.apply` acts on a plan the user confirmed earlier** — paths can
  change between preview and apply. The operations are symlink-shallow
  (`removeItem`/`moveItem`/`trashItem` act on the entry, not through it),
  same-user, and scoped to the watched folder; the residual is inherent to any
  confirm-then-act UI.
- **`CommandTitler` runs whatever command template is stored in defaults.**
  An attacker who can write the user's defaults already runs code as the user;
  this is the settings trust boundary, consistent with the repo's model.

## Risk ranking

### High (confirmed)
- None.

### Medium (likely)
1. **A stopped `FolderWatcher` could still fire**
   (`Sources/ShotScribeCore/FolderWatcher.swift`). The hosted-copy stand-down
   (`ShotScribeModel.observeOtherInstances`) exists precisely so two watchers
   never race one capture; the leftover debounced scan reopened that window —
   and a scan could also land a rename *after* the operator toggled watching
   off. **Fixed.**
2. **Untrusted failure text reached the terminal, panel and log raw**
   (`EndpointTitler.Error.http` body, `ClaudeTitler.CLIError.failed`,
   `CommandTitler.Error.failed`). A hostile or compromised endpoint answers
   4xx/5xx with ANSI/OSC escapes in the body; the operator runs
   `shotscribe rename`; the escapes drive their terminal (clear screen, spoof
   output, OSC title/clipboard on some terminals). **Fixed.**

### Low (hardening)
3. **`ShotIndex.save` sealed the index folder after writing, not before**
   (`Sources/ShotScribeCore/SearchIndex.swift`). On the first save after an
   upgrade from a build that created `~/.shotscribe` with default permissions,
   the fresh index and `.atomic`'s adjacent temp file (default 0644) sat
   briefly inside a traversable directory. **Fixed** (reorder only).
4. **The index lock is per-process, but the file is shared by four doors**
   (app, CLI, MCP server, hosted surface). `NSLock` cannot serialize the CLI's
   `record` against the app's `reindex`; `.atomic` prevents corruption but not
   a lost update — including `original`, the name an undo needs. Integrity
   nuisance, not an exploit path. **Deferred** (cross-process file locking is
   an architecture decision, not a surgical fix).
5. **`uniqueName` → `moveItem` TOCTOU** — fail-safe as analyzed above; the
   race loser throws `NSFileWriteFileExists` and the error is reported.
   **No change needed**; noted so a future "fix" doesn't make the move
   overwriting.

## Implemented fixes

1. **`security(track-07): a stopped watcher stays stopped — the pending scan
   dies with it`** — `FolderWatcher.stop()` now cancels the debounced
   `DispatchWorkItem` on the watcher's own queue (`queue.sync`, the same
   confinement `ignore` uses).
   **Old code enabled:** a rename firing up to 0.5s after the caller said
   stop — after the watching toggle was switched off, or after the hosted
   copy stood down because ShotScribe.app owns the folder, recreating the
   two-watchers-one-capture race the stand-down exists to prevent.
   **New code enforces:** `stop()` is a barrier — once it returns, `onNewFile`
   will not be called again.

2. **`security(track-07): failure text is printable before it reaches
   terminal, panel or log`** — new internal `CommandRunner.printable(_:)`
   (Cc/Cf → spaces, the exact rule `LabelCleaner` applies to labels), applied
   at all three error-construction sites: `ClaudeTitler.complete`,
   `CommandTitler.complete` (both also trim, so an all-control reason
   degrades to `.empty`, not `.failed("  ")`), and `EndpointTitler.complete`'s
   HTTP error body.
   **Old code enabled:** terminal escape injection from a hostile endpoint's
   error body or a child CLI's streams — strings printed to stderr by the CLI,
   shown in the panel, and interpolated raw into `~/Library/Logs` (reflection
   bypasses `errorDescription`, so display-time filtering would not have
   covered the log).
   **New code enforces:** every byte of failure text shown anywhere is
   printable; construction-site sanitizing covers all three sinks at once.

3. **`security(track-07): the index folder is sealed before bytes land in
   it`** — `ShotIndex.save` chmods the directory 0700 *before* encoding and
   writing, instead of after; the file chmod to 0600 stays after the write as
   before.
   **Old code enabled:** a same-machine local user reading the freshly
   written index (or the atomic temp file beside it) during the first save
   after an upgrade, while the pre-existing folder was still traversable —
   and the index is, as the repo says, more sensitive than the screenshots.
   **New code enforces:** the directory is owner-only before any index bytes
   exist inside it, on every save.

Three tests pin the fixes in
`Tests/ShotScribeCoreTests/HardeningTests.swift`:
`testAStoppedWatcherNeverReports` (inverted expectation across the debounce
window), `testFailureTextIsPrintableBeforeItIsShown` (ESC/CSI, OSC+BEL, bidi
override, and that ordinary punctuation survives), and
`testSaveSealsAPreexistingLooseIndexFolder` (a 0755 folder ends 0700 after
one save).

## Deferred

- **Cross-process index serialization** (Medium→Low integrity): the honest
  fix is `O_EXLOCK`/`flock` around load-modify-save or an SQLite store —
  either is an architecture change to a file four binaries share, and a lost
  update loses convenience (an undo name), not confidentiality. Flagged as
  systemic.
- **Watchdog pid-reuse hardening**: would mean replacing `Process` with
  `posix_spawn` + `waitpid` bookkeeping to kill only an unreaped child.
  Disproportionate to a microsecond window; flagged.
- **`Cleanup.apply` re-verification** (re-stat each planned path before
  moving): the plan is user-confirmed seconds earlier against user-owned
  files in the watched folder; re-checking adds a new failure mode (plan
  drift) for negligible attack surface. Annotated only.
- **Print-time filtering of foreign on-disk filenames** in `find`/`eval`
  output — already flagged by track-02; unchanged here for the same reason
  (validation belongs at boundaries, and the hostile-filename precondition
  requires another program to have written it).

## Validation

- Tests: **152/152 pass** (was 149; three added) —
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- Build: **clean**, all four products — `swift build -c release` (11.8s)
- Lint: no linter configured in this repo (none run)
- Grep sweeps re-verified: two `Process()` sites only; no
  `eval`/`NSAppleScript`/`system(`/`popen`; no `random`-derived secrets; no
  TODO/FIXME/stub validation in `Sources/`
- API surface: unchanged — no public signature added, removed, or altered
  (`CommandRunner.printable` is internal)

---

## Commits on this branch

```
