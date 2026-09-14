# Changelog

Dates are release dates. The narrative behind each line is in `History.md`.

## 1.6.3 — 2026-09-14

- **A welcome, once.** The first run says what ShotScribe is and asks the one
  thing that has to be right before anything else means anything: which folder
  it watches, and whether it names what lands there. The empty state said the
  same words, but only someone whose folder was already empty ever saw it.
- **The window opens on the screenshots.** The inspector starts closed rather
  than open — settings are what you visit, not what you arrive at — and it
  remembers how you left it. When it does open, it opens on **Folder**, not
  Rename.

- **The carousel replaces the grid, and is what opens.** Each day lays out on
  one line as overlapping cards — upright, on one baseline, no arch. The card
  under the cursor rises out of the row and the ones after it step aside.
  Everything a tile did it does: click, right-click, drag out, the bin, tags.
  The numbers came off a bake-off rather than a guess: 260pt cards at the
  tiles' own 4:3, 40pt of overlap, a 22pt lift, neighbours stepping 60pt, a
  10pt corner, over 0.6s. **Two views now, not three** — Carousel and List.
  The adaptive grid sat between them and answered neither question better.
- **The list shows the picture.** Hovering a row shades it and hangs the
  capture itself underneath, at the carousel's card size — the list was names
  and matched text, which says nothing about what the shot looked like.

- **The landing zone is yours to arrange.** Right-click any tile → **Arrange
  tiles…**: drag to reorder, the minus puts a tile away, and under each one is
  the count of how often you have actually used it — so the row can lead with
  what earns its place. Put-away tiles wait at the end of the arrange row with
  a plus to bring them back; **Reset** restores the shipped row and keeps the
  counts. The tally is a number in this Mac's own preferences: nothing counts
  it anywhere else and nothing leaves the machine.

## 1.6.2 — 2026-09-13

- **Right-click any screenshot** — a tile, a list row, the landing zone, the
  popover — for the landing zone's functions: Reveal, Mark up, Share, Send to,
  Rebuild as code, File as, Restore, the bin. **The click has a default:**
  right-click a landing-zone tile, "Set as default", and a plain click on any
  screenshot does that (Reveal in Finder to start). The default tile wears a
  green halo outside its circle, unmistakable in light and dark, and the menu
  marks it.
- **The seven-track security pass**, twelve fixes, none High (see
  `SECURITY.md`, *The sweeps on record*, and `docs/security/2026-09-13/`).
  Behaviour that changes: a saved API key is refused over plain `http` to a
  non-local host (the AI tab says so); an endpoint URL must be `http(s)`;
  `force` renames captures only; the MCP server honours tagging-off; a
  watcher that stops takes its queued scan with it.

## 1.6.1 — 2026-09-13

- **Security sweep.** A custom command's first token must be a plain name or
  a path before the login-shell lookup runs; plain `http` to a remote endpoint
  is flagged in the AI tab. Nothing else found: no secrets, no new logging of
  screen text, deletes only under the Keep tab's own choice.
- **Tags as a filter.** A strip under the grid head lists every tag in use
  with its count: click one to isolate, a second to narrow to both, Clear to
  see everything. A tag chip on a tile does the same. **By tag** joins the
  sort menu and groups the grid by filing, the untagged last.
- **Mark up in Preview** on the landing zone and in every shot's menu: the
  capture opens in macOS's own Preview for the pencil. "Restore" moved beside
  the "was …" line it puts back, so the tile row stays one row.

## 1.6.0 — 2026-09-13

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
