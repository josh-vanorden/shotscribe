# Whose AI is it?

[← Back to the README](../README.md)

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
