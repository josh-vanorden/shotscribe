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
