# Changelog

Dates are release dates. The narrative behind each line is in `History.md`.

## 1.6.0 — unreleased

- **Bring your own AI.** An **AI** tab names who titles a capture, honoured by
  the app, the watcher and the CLI: Claude Code (the default, as before),
  Codex, Gemini CLI, Cursor Agent, Ollama, any OpenAI-compatible endpoint (key
  in the Keychain), or any other CLI that answers a prompt. Presets are visible,
  editable commands with their tool-denying flags; "Try it on the newest
  capture" shows the answer without renaming.
- The **Rename** tab now also holds the filename template; the Name tab is
  gone and the fifth slot is the AI tab.
- **Send to …** wears the mark of the titler in use — Claude, Codex (the
  OpenAI mark), Gemini, Cursor, Ollama, offline — and copies the line that
  chat understands.
- **A new app icon** — Josh's artwork: the capture in its crop marks, the name
  and its tag, the arrow into code. `scripts/fit-icon.swift` puts it on Apple's
  icon grid and `scripts/make-iconset.sh` builds the iconset and icns; the
  robot mascot is gone.
- **A bin on every shot** — the upper corner of a tile and of the landing
  zone (on hover), and beside the date in the list. Hover unfurls "Delete";
  the click sends the letters into the bin, furls the pill to the bin, turns
  an arc for a beat and seals it, then the shot goes to the Trash. Finder's
  Put Back undoes it.
- `shotscribe ai` shows the choice; `--offline` (alias of `--no-claude`) forces
  keywords; `SHOTSCRIBE_DEFAULTS=<domain>` tries another settings domain.
- The MCP server is documented for Cursor, Codex, Gemini CLI and LibreChat as
  well as Claude Code — it always was one.

## 1.5.1 — 2026-09-12

- The search index is written readable by its owner only (0600, folder 0700);
  an existing index is tightened on its next save.
- A title can no longer carry a dot-only word (`..`), the one path fragment
  that survived the character strip.
- The hero's action tiles fit the landing zone on one row.
- `SECURITY.md`, a *Before you install* section, *Uninstall* and *Known
  limitations* in the README.

## 1.5.0 — 2026-09-12

Everything since 0.6.1, as one release:

- Captures are recognised in any language (default-name shape + macOS's own
  capture flag); English names by prefix alone. Screen recordings too.
- The file name is a template: `{date} {time} {title}` by default, spelling
  exactly what 0.6 spelled; `{app}` read off the capture's menu or title bar.
- Finder tags from a closed vocabulary, one model call for title and tags,
  searchable, on the tiles, with a switch.
- The app has a window and a Dock icon beside the menu bar item — the glass
  design: latest capture as a landing zone with an editable title, service
  tiles (Finder, Share unfolding into the Mac's destinations, Send to Claude,
  Rebuild as code, undo, tags), day groups, a tabbed inspector.
- `layout_screenshot` (text with positions) and `/screenshot code`;
  `/screenshot "<path>"`; the code brief on the pasteboard.
- `shotscribe eval`: the folder as the test set.
- Notarized app and DMG.

## 0.6.1 — 2026-09-06

The last release before this cycle: CLI, MCP server, menu bar app,
`ShotScribeUI` as a library, search index, sessions, clean-up and undo.
