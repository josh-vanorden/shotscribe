# ShotScribe

**Every screenshot, named — the moment it lands, by the AI you already use,
and it stays a file in your folder.**

Turn `Screenshot 2026-08-11 at 3.41.07 PM.png` into
`2026-08-11 1541 AWS Billing Console.png` — automatically, on-device, and
findable later.

`shotscribe` watches your screenshot folder, reads the text in each new capture
with Apple's **on-device Vision OCR** (nothing leaves your machine), asks a
local LLM for a 2–3 word title, and renames the file: **date first** (so
name-sort stays chronological) then a scannable label. macOS default capture
names, in any language, are the only ones it touches — a file you named
yourself is never renamed.

Screen recordings too: macOS drops `Screen Recording … .mov` into the same
folder, and ShotScribe names one from a couple of its frames, same OCR, same
titler, same template, `.mov` kept.

It's one small, single-purpose tool. The logic lives in a reusable core
(`ShotScribeCore`) so the same engine backs the CLI today and — next — an MCP
server, a menu-bar app, and a widget.

## Before you install — what it touches

ShotScribe is a small tool with a sharp edge: it renames files. Read this
once.

- **It renames only macOS default capture names** (`Screenshot …`, `Screen
  Shot …`, `Screen Recording …`, and the equivalents in other languages when
  the file carries macOS's own capture flag). A file you named yourself is
  never touched unless you pass `--force` on the CLI. **Auto-rename is on by
  default** the moment the app runs; the switch is on the Rename tab.
- **It writes Finder tags** (up to two per capture, from a list you control)
  onto the renamed file. Tags you added by hand are kept; the switch is on the
  File tab.
- **It keeps a search index at `~/.shotscribe/index.json`**: the text read off
  every capture. It never leaves the machine and is readable by your user
  only, but it is more sensitive than the screenshots — see *Privacy*.
- **With AI titling on, the text read off each capture goes to whichever
  assistant the AI tab names** — Claude Code by default, through the `claude`
  CLI on your own subscription; Codex, Gemini CLI, Cursor, an endpoint, or
  Ollama on this Mac. Offline, nothing leaves the machine. The only network
  code in the app is the endpoint titler, and it runs only when an endpoint is
  the choice; there is no telemetry.
- **macOS may ask for folder access.** If your captures land on the Desktop
  (or in Documents or Downloads), the first look there triggers the standard
  folder-access prompt; denying it leaves the app idle. `~/Pictures` needs no
  prompt.
- **Signed and notarized** by Apple's notary service under a Developer ID, so
  Gatekeeper opens it without a warning. It is not App Store sandboxed.
- **One watcher at a time.** ShotScribe.app and a copy mounted in another host
  (Toolbelt) both watch the same folder; the hosted copy notices the app
  running and stands down.

Everything it writes and how to remove it is under *Uninstall*.

## Whose AI is it?

**Yours.** ShotScribe ships no API keys and has no account of its own. The
**AI** tab names who titles a capture, and every door — the app, the CLI, the
watcher — honours the same choice:

| Titler | What it drives | Where the text goes |
|---|---|---|
| **Claude Code** (default) | the `claude` CLI you are signed in to, with its tools disabled | Anthropic, on your subscription |
| **Codex** | `codex exec` in a read-only sandbox | OpenAI, on your login |
| **Gemini CLI** | `gemini -p`, sandboxed | Google, on your login |
| **Cursor Agent** | `cursor-agent -p` | Cursor, on your login |
| **Ollama** | `ollama run <model>` | nowhere — the model runs on this Mac |
| **An endpoint** | any OpenAI-compatible `/chat/completions` — OpenAI, OpenRouter, LM Studio, Ollama's `/v1`, a team gateway | the endpoint you name; a local one keeps it here |
| **Other CLI…** | any tool that answers a prompt on the command line — `llm`, `aichat`, `mods`, a team script | wherever it sends it |
| **Offline** | the keyword titler | nowhere |

The CLI presets are commands you can see and edit in the tab (`{prompt}` is
the instruction plus the text read off the capture, as one argument); each
ships with the flags that stop the tool from *acting* on that text, because
what is on your screen is not always text you wrote. An endpoint's key lives
in your Keychain, never in the settings file. **Try it on the newest capture**
shows the title the choice would give, without renaming anything. Nothing
installed? Everything still works with the offline titler — just blunter
labels.

The inversion also exists: **`shotscribe-mcp`** is an MCP server (stdio) that
lets Claude Code, Cursor, Codex, Gemini CLI, LibreChat or any MCP client call
the same engine as tools *during a session* — there, the calling model IS the
intelligence, so the server only does the mechanical, on-device parts and
takes the model's title as input.

## Install

**The app:** download `ShotScribe-<version>.dmg` from the
[latest release](https://github.com/josh-vanorden/shotscribe/releases/latest),
open it, drag ShotScribe to Applications. The app and the disk image are
Developer ID signed, notarized and stapled, so macOS 13 and later open them
without a warning. Requires macOS 13.

**The CLI and the MCP server** build from source in under a minute, with no
dependencies beyond Xcode's toolchain:

```bash
git clone https://github.com/josh-vanorden/shotscribe.git && cd shotscribe
swift build -c release
cp .build/release/shotscribe /usr/local/bin/   # or anywhere on your PATH
```

## Usage

```bash
# Print the title shotscribe would give a shot (no rename) — the quickest way
# to see the Claude connection working end-to-end:
shotscribe label "~/Desktop/Screenshot 2026-08-11 at 3.41.07 PM.png"

# Rename one capture in place:
shotscribe rename "~/Desktop/Screenshot 2026-08-11 at 3.41.07 PM.png"

# See what it WOULD do, without moving anything:
shotscribe rename --dry-run "~/Desktop/Screenshot ....png"

# Watch a folder and rename new captures as they land
# (defaults to your macOS screenshot location):
shotscribe watch
shotscribe watch ~/Pictures/Screenshots

# Skip the AI tab's choice for one run and use the offline keyword titler:
shotscribe label --offline "~/Desktop/Screenshot ....png"

# Who titles, as the AI tab set it (SHOTSCRIBE_DEFAULTS=<domain> tries another):
shotscribe ai

# Rename without filing it under Finder tags:
shotscribe rename --no-tags "~/Desktop/Screenshot ....png"

# How good is the titler? Score it against the names you kept:
shotscribe eval --limit 25
```

`eval` treats your own folder as the test set: every capture that is already
named is a judged answer, and its Finder tags a judged filing. It re-titles each
one and reports exact matches, title recall and tag precision and recall, so a
prompt change or a different titler gets a number instead of a feeling. (The
shape is borrowed from screenshot-to-code's evals; the twist is that no fixture
set is needed.) One honest caveat: the names it judges against are only as good
as whoever kept them. If the offline titler named a fortnight of captures while
Claude was signed out, it will agree with itself; the number is a regression
check then, not a quality score.

## Naming

The name is a template. `{date} {time} {title}` is the default and spells
exactly what ShotScribe has always spelled, so an upgrade changes nobody's
names. Edit it in the window's **Name** tab: the layout carries the separators
(`{date}_{time}_{title}` is how you get underscores), and pickers cover the
date style, the time style, how the title's words are joined, and how many are
kept. A fourth token, `{app}`, is the app or window name read off the capture's
own menu bar or title bar; it is best effort and simply empty when the shot has
no chrome. A template that would spell a name macOS uses for a fresh capture is
refused, because the watcher would then rename its own output forever.

## Tags

A renamed capture is also filed under up to two **Finder tags** — so it shows in
Finder, sorts in the sidebar, and answers a Spotlight search without ShotScribe
running at all.

Tags come from a fixed list (`terminal`, `code`, `error`, `browser`, `docs`,
`chat`, `email`, `calendar`, `design`, `dashboard`, `settings`, `logs`,
`ticket`, `meeting`, `diagram`, `receipt`). That is deliberate: the text on your
screen is not always text you wrote, so a screenshot never gets to invent a tag
of its own — anything off the list is dropped. Tags you added by hand are kept.
`--no-tags` turns filing off.

## MCP server (Claude Code, Cursor, Codex, Gemini CLI, LibreChat…)

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

[`skills/screenshot/SKILL.md`](skills/screenshot/SKILL.md) turns "see my newest
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

The app's **Send to Claude** (on the hero, or any shot's context menu) copies
that second form for the shot you picked, so the gesture works on a capture
from last week as well as the one from a minute ago: paste it into whatever
session you are in and Claude reads the shot there. Nothing can push into a
running session, so the pasteboard is the honest bridge; dragging a tile into
the composer does the same without words.

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

## Menu bar app

`ShotScribe.app` is the always-there face: a menu bar panel with an
auto-rename watch toggle, a **configurable watch folder** ("Change…" — defaults
to your macOS screenshot location), an AI titling switch, **launch at login**,
"Rename latest capture now", and a history of recent renames. The window's
inspector has five tabs: **Folder**, **Rename** (the switch, and the filename
template with a live sample), **AI** (who titles — see *Whose AI is it?*),
**File** (the tag vocabulary) and **Keep**; any shot's context menu can file it
after the fact. The newest capture sits at the top as the landing zone: its title edits in
place (click it, type, Return — the date stays, the words change) when a name is
not what you would have said, and a row of tiles below it carries the icon of
each service it reaches, named on hover — Finder, **Share** (which unfolds into
AirDrop, Messages, Mail, Notes…), Claude, code, tags. Any shot also drags out as
a copy. First launch opens the window on the folder it is watching with the
inspector open, so the settings are found; a folder with nothing named yet
shows the welcome instead of an empty grid.
Activity logs to `~/Library/Logs/ShotScribe.log`.

```bash
./scripts/package-app.sh     # → dist/ShotScribe.app (ad-hoc signed, no Dock icon)
open dist/ShotScribe.app
```

Auto-rename is ON by default — launching an app whose one job is renaming
screenshots is the opt-in; the toggle is right there in the panel.

## Mounting the face somewhere else

The panel is a library, not a private part of the app. `ShotScribeUI` exposes
one view:

```swift
import ShotScribeUI

ShotScribeSurface(chrome: .hosted)   // roomy detail pane
ShotScribeSurface(chrome: .menuBar)  // the 340pt popover
```

It owns its own state, takes no other arguments, and knows nothing about what's
hosting it. `.hosted` omits "Launch at login" and "Quit" on purpose —
`SMAppService.mainApp` and `NSApplication.shared.terminate` would act on the
*host*, not on ShotScribe.

Two things a host gets for free, because they're ShotScribe's job and not the
host's:

- **Your settings come with it.** The surface reads the
  `com.joshvanorden.shotscribe` preferences domain by name, so a copy running
  inside another app sees the watch folder you actually chose and the history
  you actually have — rather than starting blank and renaming files somewhere
  you never pointed it at.
- **It won't fight ShotScribe.app.** Two live watchers would race to rename the
  same capture. A hosted copy notices the standalone app running, says so, and
  stands down until you quit it.

[Toolbelt](https://github.com/josh-vanorden/toolbelt) mounts it this way; its
whole integration is a twenty-line adapter. ShotScribe has no dependency on
Toolbelt and never will.

## Privacy

OCR runs entirely on-device (Apple Vision). Only the *extracted text* is sent
to the titler — and offline, or with Ollama, nothing leaves the machine at all.
With the default, that text goes to `claude -p` (inference on Anthropic's
servers, billed to your Claude subscription) with Claude Code's tools disabled
and no MCP servers, because the text on your screen is not always text you
wrote; the other CLI presets carry their own tool-denying flags, and you can
see and edit every one of them in the AI tab.

What ShotScribe keeps on the machine, and where:

| What | Where | Contains |
|---|---|---|
| Search index | `~/.shotscribe/index.json` (mode 0600) | The text read off every capture, its name, tags, original name |
| Settings | `defaults` domain `com.joshvanorden.shotscribe` | Watch folder, template, vocabulary, switches, recent renames |
| Log | `~/Library/Logs/ShotScribe.log` | File names and outcomes — never the text of a capture |
| Finder tags | On the renamed files themselves | The tags chosen from your list |
| Endpoint key | Your login Keychain, item `endpoint-api-key` | Only when you enter one; removable from the AI tab |

Treat the index like the screenshots it describes: keep it out of backups
and shared folders you would not trust with them. Nothing here is uploaded,
synced or reported anywhere.

## Uninstall

```bash
osascript -e 'tell application "ShotScribe" to quit'
rm -rf /Applications/ShotScribe.app
rm -rf ~/.shotscribe                       # the search index
defaults delete com.joshvanorden.shotscribe # settings
rm -f ~/Library/Logs/ShotScribe.log
```

Renamed files keep their names and tags; nothing else is left behind. If you
turned on launch at login, the entry under System Settings › General › Login
Items goes with the app.

## Known limitations

- `{app}` on a browser window names the tab, not the browser: it reads what
  the window's chrome says.
- Screen recordings are recognised by their English default name only; macOS
  puts no capture flag on a recording, so other languages are not detected.
- The offline titler picks salient words, which can include OCR noise; any
  assistant in the AI tab gives titles that read like titles, and
  `shotscribe eval` measures the difference.
- The Claude Code, Ollama, custom-command and endpoint titlers have been run
  end to end; the Codex, Gemini CLI and Cursor Agent presets are shipped as
  their documented invocations and are editable — the "Try it" button is the
  check. Keep a CLI's tool-denying flags, and keep the CLI itself current and
  signed: macOS will refuse a binary it recognises as malware, and ShotScribe
  then reports the failure rather than working around it.
- The window and the menu bar item are one process; a copy of the pane hosted
  in another app stands down while ShotScribe.app runs.

## Roadmap

- [x] Core engine + CLI (`rename` / `label` / `watch`)
- [x] MCP server target (`shotscribe-mcp`) — Claude Code / Cowork call it as tools
- [x] `MenuBarExtra` app — the always-there local UI (`scripts/package-app.sh`)
- [x] App icon, first-launch welcome, configurable folder, launch at login
- [x] Notarized distribution — Developer ID signed, notarized, stapled (app + DMG)
- [x] `/screenshot` skill — the gesture, for any Claude Code user
- [x] `ShotScribeUI` — the face as a mountable library, so any shell can host it
- [ ] Backlog sweep — rename captures that landed while the app wasn't running
- [ ] WidgetKit widget — a one-tap App Intent front door

## Why this exists

Extracted from a larger app ("Navi") as its own tool, on the theory that a
handful of small, sharp, open-source tools beats one monolith — each easy to
understand, iterate, and hand to Claude as a capability.

## Finding a screenshot again

ShotScribe reads every capture to name it. It now **keeps** that text instead of
discarding it, so you can search what a screenshot *said* rather than what it got
called — a three-word title is a thin hook a month later.

```bash
shotscribe index            # read the watched folder into the index
shotscribe find "NXDOMAIN"  # search what they say
shotscribe find error       # …or how they are filed
```

The search field in the app does the same thing, and new captures index
themselves the moment they are renamed. Tags are searched alongside the text and
rank with the filename, since a tag was chosen deliberately and body text merely
crossed the screen. In the app the tags sit on each tile; clicking one shows
everything filed the same way. A tag you add by hand in Finder is picked up by
the next sweep.

`SHOTSCRIBE_INDEX=/tmp/scratch.json shotscribe …` points the index somewhere
else, which is how to try the CLI against a folder without writing into your own
searchable history.

Two deliberate choices:

- **The index OCRs again rather than reusing the label's text.** Labelling uses
  `.fast` recognition capped at 900 characters — right for a title, wrong for
  search, since 900 characters stops partway down most screenshots and `.fast`
  misreads exactly the strings you would search for (`i-0a3f`, `NXDOMAIN`,
  `PROJ-4821`).
- **It indexes the folder, not the rename history.** That history is capped and
  holds no paths, so a search built on it would only ever see the last handful.

### On sensitivity

`~/.shotscribe/index.json` never leaves this machine, and it is **more sensitive
than the screenshots it describes**. Tokens, hostnames and customer names get
caught in captures in passing; in a PNG they are buried in pixels, and in an
index they are greppable and durable. Keep it out of backups you would not trust
with the screenshots themselves.
