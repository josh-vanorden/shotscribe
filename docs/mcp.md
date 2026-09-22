# MCP server and the /screenshot skill

[← Back to the README](../README.md)

`shotscribe-mcp` speaks MCP over stdio and exposes four tools:

| Tool | What it does |
|---|---|
| `latest_screenshots` | List the newest captures from your macOS screenshot folder |
| `ocr_screenshot` | On-device OCR — returns the text (+ an offline suggested title) so the *calling model* composes the label |
| `layout_screenshot` | The text *with its layout*: every line in reading order with top/left/width/height in percent, so a model can rebuild the screen as code. Still on-device; no pixels leave the machine |
| `rename_screenshot` | Safe rename to `<date> <time> <Label>.ext`; takes the caller's `title`, protects user-named files (`force` to override), supports `dry_run` |

Build it once — `swift build -c release` — then register the binary with
whichever client you use (the path is `$(pwd)/.build/release/shotscribe-mcp`):

```bash
claude mcp add shotscribe -- /path/to/shotscribe-mcp            # Claude Code
codex mcp add shotscribe -- /path/to/shotscribe-mcp             # Codex CLI
gemini mcp add shotscribe /path/to/shotscribe-mcp               # Gemini CLI
```

Cursor reads `.cursor/mcp.json`, LibreChat its `librechat.yaml`; both take a
stdio server the same way:

```json
{ "mcpServers": { "shotscribe": { "command": "/path/to/shotscribe-mcp" } } }
```

Then, mid-session: *"grab my latest screenshot and give it a proper name"* —
the model lists, OCRs, composes the title, renames. No nested LLM calls: when
the caller is already a model, the server stays mechanical. It has no network
listener and never calls a model itself.

### The `/screenshot` skill

[`skills/screenshot/SKILL.md`](../skills/screenshot/SKILL.md) turns "see my newest
screenshot" into a one-word gesture for Claude Code: it finds the newest
capture (via ShotScribe's MCP tools when registered, plain `ls` otherwise),
reads it as an image, and addresses it in the context of what you're doing —
then quietly renames it if it still wears a raw capture name, titling from
what Claude *saw* rather than just the OCR text. Install:

```bash
mkdir -p ~/.claude/skills/screenshot
curl -fsSL https://raw.githubusercontent.com/josh-vanorden/shotscribe/main/skills/screenshot/SKILL.md \
  -o ~/.claude/skills/screenshot/SKILL.md
```

Then type `/screenshot` in any Claude Code session. `/screenshot 2` reads the
second-newest; `/screenshot "<path>"` reads that one.

The app's **Send to Claude Code** (on the hero, or any shot's context menu)
copies that second form for the shot you picked, so the gesture works on a
capture from last week as well as the one from a minute ago: paste it into
whatever session you are in and Claude reads the shot there. Nothing can push
into a running session, so the pasteboard is the honest bridge; dragging a tile
into the composer does the same without words.

That line is for a session **on this Mac**. A chat at claude.ai or in the
Claude app runs in a container that has never seen your disk, so a path means
nothing there — use **Send the picture to a chat** instead, which puts the
image itself on the pasteboard (with the file's name, never its path); ⌘V in
the chat attaches it.

`/screenshot code` goes one step further: it rebuilds the newest capture as
code in the project you are standing in — your stack, your components, a diff
to review — using `layout_screenshot` for structure and exact strings and the
image for everything else. The working discipline (create once then edit,
extract assets rather than redraw them, render and verify before stopping) is
borrowed from [abi/screenshot-to-code](https://github.com/abi/screenshot-to-code);
what ShotScribe changes is where the result lands, and that no key or second
app is involved.

From the app, **Rebuild as code** on any shot (the hero's button, or a shot's
context menu) copies the same brief with the layout already in it, and says
where to paste it: into Claude Code, inside the project the code should land
in. That is stage two; stage one was the name and the filing.
