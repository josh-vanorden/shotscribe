# Brand marks for the "Send to …" tile

Drop the official mark for each assistant here as a PNG (square, 128 px or
more, transparent background), named by the assistant:

    claude.png   codex.png   gemini.png   cursor.png   ollama.png

then run `swift scripts/make-brand-art.swift` to regenerate
`Sources/ShotScribeUI/BrandArtData.swift`, which embeds them (no resource
bundle to ship). The tile prefers the installed app's own icon when the app is
present (Claude.app, Cursor.app, ChatGPT.app, Ollama.app) and falls back to
these; with neither it draws the assistant's initial.

Each mark belongs to its owner and is used only to point at that service, per
the owner's brand guidelines. Get them from the owners' press pages, never
redrawn.

## Where the marks stand (checked 2026-09-13)

| Assistant | Mark on the tile today | Getting the official mark |
|---|---|---|
| Claude | Claude.app's icon when installed; else the initial | Anthropic's press page did not answer; the app is the common case |
| Cursor | Cursor.app's icon when installed; else the initial | cursor.com/brand ships a kit (`cursor-brand-assets.zip`, 1.9 MB); naming rule: "Cursor", never "Cursor AI" |
| Codex | ChatGPT.app or Codex.app icon when installed; else the initial | openai.com/brand: the logo download is disabled; use is by permission — partnercomms@openai.com |
| Gemini | the initial | Google product icons need a Partner Marketing Hub account and an approval form; no download |

The initial is drawn on the accent, never in a brand's colours, because Google's
rules forbid imitating its colour treatment and OpenAI's forbid colouring the
Blossom. Nothing here is fetched without the owner's terms allowing it.
