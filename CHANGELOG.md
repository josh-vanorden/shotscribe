# Changelog

Dates are release dates. The narrative behind each line is in `History.md`.

## 1.7.3 — unreleased

- **The capture card: naming you can see, a name in colour, a tile you can
  drag.** While the title is being written the card moves — pulsing dots on
  the badge, a shimmer where the name will go — instead of a still
  "Naming…". When the name lands it fades in, in green; a shot that got the
  generic word because nothing could be read is set in grey, under a badge
  that says so. The tile keeps its picture through the rename (it used to
  blank for a beat when the file's path changed under it) and is a drag
  source: drag it into Finder, Slack, a browser's upload field or Jira and
  the renamed file on disk arrives, never a bag of pixels. Draggable once
  named, and the card stays put for as long as a drag lasts.
- **The words in a shot, findable in Spotlight at once.** A switch in the File
  tab writes each capture's significant words — the title's, the tags, then the
  distinct words the text read — into the file's Spotlight keywords, so a plain
  Spotlight search for what a shot showed finds it within seconds instead of
  the hours or days Apple's own image-text pass takes. **Off by default**: the
  words travel with the file on AirDrop and in an archive. Switching on writes
  them to every shot in the library from the text the index already holds;
  switching off takes them off again.
- **Every capture is read at the accurate level, and a small one is doubled
  first.** Two kinds of shot came back titled "Screenshot" from the fast text
  pass in one day: a wide org chart with five-pixel names (75 characters of
  noise), then five small captures of slides, 280 pixels wide with the title
  in plain sight (0 to 36 characters). The fast pass is gone. Every picture is
  read at Vision's accurate level — 40 to 200 ms on real captures, against a
  titler that takes seconds — and a picture under 1,000 pixels on its longer
  side is read at twice its size, which turned 171 characters of the wrong
  alphabet into 797 clean ones on one of the slides. The chart titles as
  "Company Org Chart"; the slides as what they say.

## 1.7.2 — 2026-09-22

- **Send the picture to a chat.** "Send to Claude" copied a `/screenshot
  "<path>"` line, which is right for a Claude Code session on this Mac and
  useless in claude.ai or the Claude app — their chats run in a container that
  has never seen your disk, so nothing arrived. There are two destinations now,
  named by what they can see: **Send to Claude Code** copies the line as
  before; **Send the picture to a chat** copies the image itself (with the
  file's name, never its path), so ⌘V in any chat attaches it. Both are on the
  landing zone's Send tile, the capture card and every shot's right-click, and
  either can be the click default.

## 1.7.1 — 2026-09-21

- **An interrupted rename is retried.** A rename now records itself as in
  flight before the slow part — reading the picture, asking for a title — and
  clears the record on every outcome. If ShotScribe quits mid-rename, the
  capture used to join the backlog silently; now it is picked up and named the
  next time watching starts, in the app and in `shotscribe watch` alike, ahead
  of the backlog sweep, and by the titler you chose rather than the offline one.
- **Fixed before it shipped: `shotscribe watch` would have crashed at startup.**
  The retry was first written as a bare top-level `await`, which traps at
  `dispatchMain()`; it runs in a task now, and the watcher arms *before* the
  retry so a capture landing meanwhile is not lost.
- **The titler presets say which are verified.** `docs/titlers.md` states, for
  each preset, a real run on this Mac or an honest "unverified".
- **Packaging leaves the CLI and the MCP server findable.** The universal build
  now builds the host's slice last, so `.build/release` still holds
  `shotscribe` and `shotscribe-mcp` afterwards.
- **Removed: the menu bar popover in `ShotScribeUI`.** `ShotScribeChrome.menuBar`
  — the 340pt panel the menu bar item opened through 1.6.6 — and
  `ShotScribeView`'s `onOpenWindow:` are gone; 1.7.0 replaced the panel with a
  menu and nothing used it. `ShotScribeSurface(chrome: .hosted)` is unchanged.
  A host that built its own popover on `.menuBar` should mount
  `ShotScribeMenu` instead.

## 1.7.0 — 2026-09-18

- **Dock, menu bar, or both.** Settings (⌘,) has **Show in Dock** and **Show in
  menu bar**. Both are on by default, so an upgrade changes nothing, and they
  can never both be off — the last one ticked is disabled rather than refused.
  Switching is live, no restart. In the menu bar only, launch is silent: no
  Dock icon appears even for a moment, no window opens, and the Library opens
  from the menu (or by launching ShotScribe again). Launch at login moved here
  too.
- **A real menu.** The menu bar icon opens a menu, not a panel, in order of
  whose job it is: **Go to Library** first; pause, and rename the capture that
  was missed; the last capture into the editor, or under your kept watermark
  (**Watermark ▸ Apply / Remove**, no editor); the five most recent, each with
  Edit, Reveal and Undo Rename; then Settings and Quit. The folder and AI
  controls it used to repeat are where they always also were, in the Library.
- **Go to Library.** The window has a name, and the capture card's button and
  the menu use it.
- **The folder and the tags, from the top of the Library.** The status capsule
  is a menu now — the four usual folders, a picker, Finder, pause — and a Tags
  capsule beside it shows whether new captures are filed and under how many
  words, with the switch, a search by tag, and the vocabulary behind it.
- **A lighter editor.** The picture is resampled once per size instead of on
  every mouse move, a dragged pixelation no longer queues a full render per
  event, and the frame you see is drawn by the same code that writes the file.
- **Universal.** The app builds for Apple silicon and Intel. Through 1.6.6 the
  release carried only the build host's slice (`arm64`), so it never launched
  on an Intel Mac that macOS 13 still supports, and nothing said so.
  `package-app.sh` now builds one slice per architecture, joins them with
  `lipo`, and stops if either is missing. All 232 tests pass on the Intel slice
  under Rosetta.
- **The README is a landing page.** The reference moved verbatim into `docs/`;
  the README shows the app, then says what it touches.
- **A site.** `docs/index.html`, ready for GitHub Pages from `main` `/docs`:
  one file, four images, no third-party requests.

## 1.6.6 — 2026-09-17

- **An audit stamp.** The watermark panel's third kind, beside Text and Logo:
  a signature block with your name, when the picture was taken, when you saved
  it (the moment of the save, not of opening the panel), which Mac, and a
  SHA-256 of the original picture's pixels — the same for any lossless copy,
  so an auditor holding the original can check it. Each line is a checkbox;
  the times carry their zone; the digest reads `original` while ShotScribe
  still has the untouched capture and `as kept` once a redaction has been
  burned in. It can be the standing watermark ("Use on every edit").
- **Edit with ShotScribe.** What was "Edit the Image" says whose editor it is,
  everywhere it appears.
- **The right-click menu, in order of who does it.** What ShotScribe adds
  first (edit, send to your assistant, rebuild as code, tag, restore the
  name), what the Mac already does next (Finder, Preview, Share), the bin last.

## 1.6.5 — 2026-09-16

- **Edit the Image.** ShotScribe has its own editor now — the landing zone's
  mark-up tile opens it (Preview is still one right-click away). Pixelate or
  black out a region, boxes, ellipses, lines, arrows (drag the middle handle to
  bend one), highlights, labels, and **step numbers** that count up as you click
  — bubble, square, chevron, flag or pin. Every mark stays an object until Save:
  select it, move it, resize it, recolour it, delete it. Colour is black by
  default, then white, then the palette; size is a slider. Undo and redo.
- **Edits stay editable.** Saving writes a flat picture for everyone else and
  keeps the untouched capture and the marks beside it, so opening the same
  shot again puts everything back where it was. **Revert to original** is
  honest: it is offered only while nothing has been redacted, because a
  redaction is burned in on purpose and there is no lifting it.
- **Frame, crop, resize.** Corners, margin and shadow as sliders; the margin
  filled with a colour, a two-colour gradient (six shipped combos and **+** for
  your own, by hex or the colour wheel) or a picture of your own. Crop to what
  matters — the rest stays in the edit and can come back — and save at a
  smaller size.
- **Watermark.** Your name or logo over the picture: a corner, the centre, or
  tiled across everything. With ink on **Auto** it is set in white or near-black
  against whatever is under it, with a soft halo; a logo becomes a silhouette,
  and a logo exported on a white square is keyed off that square rather than
  drawn as a box. **Use on every edit** keeps one watermark and starts every
  new edit with it on.
- **Fonts.** Labels, step numbers and watermark text can be set in the system
  face, Rounded, Serif, Mono, or any family installed on the Mac; a face that
  is not installed stands down to the system one and says so.
- **Backlog sweep.** Captures that landed while ShotScribe was not running —
  still called `Screenshot …` — can be named after the fact: the Folder tab
  and the window's "never named" link propose names three at a time, and you
  approve, drop or apply. Never automatic, never a file you named yourself.
- **Light or dark, your call.** A moon or sun beside the search field flips
  the whole app; right-click it to follow the Mac again.
- **Fixed: the watcher was re-titling ShotScribe's own output.** Every renamed
  file came back through the watcher and was read again before the name check
  said no — 257 wasted titler calls in one log. The name check runs first now.

## 1.6.4 — 2026-09-15

- **A card when a capture lands.** It slides up from the bottom centre about a
  second after the shot arrives, saying "Naming…", then fills in the name and
  widens to fit it. The name is the point, so it is never truncated. On it: the
  picture, the tags it was filed under (click one to take it off, or **+ Tag**
  to add), **Open ShotScribe**, **Send to** your assistant, **Finder**,
  **Preview**, and a bin. It lingers eight seconds from the moment the *name*
  arrives, pauses while the cursor is on it, and has a hard stop so a resting
  pointer cannot pin it. Switch it off in the **Rename** tab — and beside it,
  a switch that mutes macOS's own thumbnail, which appears before the rename
  and so can only ever show an unnamed file.
- **Send to carries both AI jobs.** "Rebuild as code" was its own tile doing a
  different job to the same destination; it now lives under Send to's
  right-click, along with the assistant to use and which of the two a plain
  click performs. Six tiles in the landing zone instead of seven.
- **Tags come off again.** A tag could only ever be added — every menu greyed
  out the ones already on a shot, so the first guess was permanent. Now a
  ticked tag comes off when picked, anywhere: the landing zone, a shot's
  right-click, the card's chips. "File as" is called **Tag**, and **+ New Tag**
  is the first thing in the menu.
- **The tag vocabulary can be emptied.** Removing the last word used to put all
  sixteen shipped ones straight back, so clearing the list never finished.
  **Remove all** does it in one gesture and **Shipped list** is the way back.
- **A bin on every day.** The day heading carries one, and the word it eats
  says how many go with it — "Delete 12", not "Delete".
- **Fixed: the bin went dead after one delete.** It never reset after firing,
  and in a lazy list SwiftUI hands that state to whatever takes the slot, so
  every later click was swallowed until something forced a rebuild.

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
