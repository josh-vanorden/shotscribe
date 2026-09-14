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
