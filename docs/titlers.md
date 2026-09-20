# Whose AI is it?

[← Back to the README](../README.md)

**Yours.** ShotScribe ships no API keys and has no account of its own. The
**AI** tab names who titles a capture, and every door — the app, the CLI, the
watcher — honours the same choice:

| Titler | What it drives | Where the text goes | Verified here |
|---|---|---|---|
| **Claude Code** (default) | the `claude` CLI you are signed in to, with its tools disabled | Anthropic, on your subscription | Yes — below |
| **Codex** | `codex exec` in a read-only sandbox | OpenAI, on your login | No — not actually installed, below |
| **Gemini CLI** | `gemini -p`, sandboxed | Google, on your login | No — not installed, below |
| **Cursor Agent** | `cursor-agent -p` | Cursor, on your login | No — not installed, below |
| **Ollama** | `ollama run <model>` | nowhere — the model runs on this Mac | Yes — below |
| **An endpoint** | any OpenAI-compatible `/chat/completions` — OpenAI, OpenRouter, LM Studio, Ollama's `/v1`, a team gateway | the endpoint you name; a local one keeps it here | Yes, against a local one — below |
| **Other CLI…** | any tool that answers a prompt on the command line — `llm`, `aichat`, `mods`, a team script | wherever it sends it | No fixed command to test — below |
| **Offline** | the keyword titler | nowhere | Yes — below |

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

## Verified on this Mac (2026-09-20)

Each preset below was actually tried — the shipped binary where the preset
has no CLI of its own, or the exact command line the preset builds. A "yes"
line quotes real output; a "no" line quotes the real error. Run once via the
project's own build (`.build/arm64-apple-macosx/debug/shotscribe`); shown
below as plain `shotscribe`.

- **Claude Code — yes.** `shotscribe ai` reports `claude found.`, and the
  default AI-tab choice ran end to end:
  ```
  $ shotscribe label "~/Desktop/Screenshot ....png"
  AI Web Builder
  tags: browser, design
  ```

- **Codex — no, not actually installed.** Ran the preset's own command line:
  ```
  $ codex exec --sandbox read-only --skip-git-repo-check "…"
  command not found: codex
  ```
  Homebrew's own bookkeeping disagrees — `brew list --cask` still shows
  `codex 0.118.0`, and `/opt/homebrew/bin/codex` exists as a symlink — but the
  symlink's target, `/opt/homebrew/Caskroom/codex/0.118.0/codex-aarch64-apple-darwin`,
  isn't on disk; the version directory is empty. ShotScribe's own resolver
  (`Executables.resolve`, which checks `isExecutableFile`, not just `PATH`)
  would call this the same way the shell does: missing. That's a Homebrew
  reinstall, not a ShotScribe fix.

- **Gemini CLI — no, not installed.** Ran the preset's own command line:
  ```
  $ gemini -p "…" --sandbox
  command not found: gemini
  ```
  No `gemini` binary anywhere checked — `PATH`, `~/.local/bin`,
  `/opt/homebrew/bin`, `/usr/local/bin`, `brew list`, `npm ls -g`, `pipx list`.

- **Cursor Agent — no, not installed.** Ran the preset's own command line:
  ```
  $ cursor-agent -p "…" --output-format text
  command not found: cursor-agent
  ```
  Only the Cursor.app editor is on this Mac (`/Applications/Cursor.app`) — a
  GUI, not the `cursor-agent` CLI this preset shells out to.

- **Ollama — yes.** `ollama --version` → `0.32.5`; `ollama list` already has
  `llama3.2` pulled (the preset's default model). Ran the preset's exact
  command shape, prompt and all:
  ```
  $ ollama run llama3.2 "<system prompt>

  OCR text:
  …

  Label:"
  ZSH Terminal Session
  ```

- **An endpoint — yes, against a local one.** The only OpenAI-compatible
  server on this Mac is Ollama's own `/v1`. Posted the exact body
  `EndpointTitler.request` builds to `http://localhost:11434/v1/chat/completions`:
  ```
  $ curl http://localhost:11434/v1/chat/completions \
      -d '{"model":"llama3.2","messages":[…],"max_tokens":60,"temperature":0}'
  {"choices":[{"message":{"content":"GITHUB STATUS"}, …}]}
  ```
  A real request and reply in the shape `EndpointTitler.parse` expects, over
  loopback — the case `EndpointTitler.isLocal` exists for. Not tried against a
  remote endpoint or a real API key.

- **Other CLI… — no fixed command to test.** This preset ships with no
  default; it's whatever the person types (`llm`, `aichat`, `mods`, a team
  script). Nothing to run until someone sets it.

- **Offline — yes.** No network, no CLI — the keyword titler, run through the
  shipped binary against a real capture:
  ```
  $ shotscribe label --offline "~/Desktop/Screenshot ....png"
  Page Web Landing
  tags: design
  ```
