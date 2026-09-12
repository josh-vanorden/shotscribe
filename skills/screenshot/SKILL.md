---
name: screenshot
description: Look at the newest screenshot and address it — the "see my newest screenshot" gesture as one word. Pairs with ShotScribe when its MCP server is registered. Optional argument N = the Nth-newest instead.
---

# /screenshot — read the newest screenshot

When invoked, immediately:

1. **Find the newest capture.**
   - If the ShotScribe MCP tools are available, call `latest_screenshots`
     with `{"count": 1}` (or N for the optional argument) — it already knows
     the right folder.
   - Otherwise, resolve the folder yourself: `defaults read
     com.apple.screencapture location` (falls back to `~/Desktop`), then
     newest by modification time: `ls -t <folder>/*.png | head -1`.
2. **Read it with the Read tool** (it renders as an image).
3. **Address it** in the context of whatever the user is working on. If they
   gave no accompanying words, describe what's notable and ask nothing unless
   truly ambiguous.
4. **Housekeeping (ShotScribe bonus):** if the file still wears a raw
   `Screenshot …` name (or macOS's default in another language, e.g.
   `Bildschirmfoto …`) and the ShotScribe tools are available, rename it via
   `rename_screenshot` with a 2–3 word Title Case `title` composed from what
   you actually SAW — you have the full image, so your title can beat the
   OCR-only one. Mention the new name in passing; don't make it the headline.

Notes:
- Screenshots you take yourself (during testing, verification) belong in the
  session scratchpad, NOT the user's capture folder.
- Optional argument: a number N = read the Nth-newest instead ("/screenshot 2").

## `/screenshot code [stack]` — rebuild the newest capture as code, here

The capture shows a screen; build it in the project you are standing in, as a
reviewable change, not as a demo page. (The working discipline is borrowed
from `abi/screenshot-to-code`; the difference is where the result lands: your
repo, your stack, your Claude, a diff.)

1. **Find and read it** as above. If ShotScribe's MCP tools are registered,
   also call `layout_screenshot` on it: every text line with its position, in
   percent, top-left origin. Positions say what is a title, a row of buttons, a
   sidebar; the strings are exact, use them verbatim. The image is for colour,
   spacing and everything the text cannot say.
2. **Pick the stack from the repo** — `package.json`, `Package.swift`,
   `pyproject.toml` — unless one was given. A repo with a framework gets a
   component in its own idiom, never a single file of CDN scripts.
3. **Create once, then edit.** Write the file once; every change after that is
   an exact-string edit. Never regenerate a file you already wrote.
4. **Extract, don't redraw.** Logos, photos, icons: reference the project's
   existing assets, or leave a labelled placeholder slot. Never embed the
   screenshot, never hand-draw SVG art, never paraphrase a string that
   `layout_screenshot` gave you exactly.
5. **Render and verify before you say done.** Web: `/preview` or the project's
   dev server, side by side with the capture. SwiftUI: the off-screen render
   in the repo's `CLAUDE.md`. Fix what differs, then stop; do not polish past
   the capture.
6. **Housekeeping** as in the base gesture: rename the capture if it is raw.
7. Say what you built in two sentences and offer the diff.
