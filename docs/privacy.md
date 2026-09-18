# Privacy, and what ShotScribe touches

[← Back to the README](../README.md)

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
  only, but it is more sensitive than the screenshots — see [Privacy](#privacy).
- **With AI titling on, the text read off each capture goes to whichever
  assistant the [AI tab](titlers.md) names** — Claude Code by default, through the `claude`
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

Everything it writes and how to remove it is under [Uninstall](uninstall.md).

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

## On sensitivity

`~/.shotscribe/index.json` never leaves this machine, and it is **more sensitive
than the screenshots it describes**. Tokens, hostnames and customer names get
caught in captures in passing; in a PNG they are buried in pixels, and in an
index they are greppable and durable. Keep it out of backups you would not trust
with the screenshots themselves.
