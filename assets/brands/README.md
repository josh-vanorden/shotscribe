# Brand marks for the "Send to …" tile

Drop the official mark for each assistant here as a PNG (square, 128 px or
more, transparent background), named by the assistant:

    claude.png   codex.png   gemini.png   cursor.png   ollama.png

then run `scripts/make-brand-art.swift` (compile line in its header, from the repo root) to regenerate
`Sources/ShotScribeUI/BrandArtData.swift`, which embeds them (no resource
bundle to ship). The tile prefers the installed app's own icon when the app is
present (Claude.app, Cursor.app, ChatGPT.app, Ollama.app) and falls back to
these; with neither it draws the assistant's initial.

Each mark belongs to its owner and is used only to point at that service, per
the owner's brand guidelines. Get them from the owners' press pages, never
redrawn.

## What is here (2026-09-13)

`claude`, `codex` (the OpenAI mark), `gemini`, `cursor` and `ollama`, as SVG
sources from [Lobe Icons](https://github.com/lobehub/lobe-icons) 1.95.0 (MIT
for the collection; each mark stays its owner's trademark) and the 256 px PNGs
rasterised from them with `scripts/svg-to-png.swift` (WebKit: CoreSVG drops
Gemini's gradient and Quick Look paints a white background). `<name>.mono` marks the single-colour ones, rendered as
templates. Josh chose to ship them (2026-09-13) knowing OpenAI's and Google's
own downloads are gated; they point at the service the user signed in to and
are never more prominent than ShotScribe's own icon. Remove on an owner's request.

## Where the marks stood before that (checked 2026-09-13)

| Assistant | Mark on the tile today | Getting the official mark |
|---|---|---|
| Claude | Claude.app's icon when installed; else the initial | Anthropic's press page did not answer; the app is the common case |
| Cursor | Cursor.app's icon when installed; else the initial | cursor.com/brand ships a kit (`cursor-brand-assets.zip`, 1.9 MB); naming rule: "Cursor", never "Cursor AI" |
| Codex | ChatGPT.app or Codex.app icon when installed; else the initial | openai.com/brand: the logo download is disabled; use is by permission — partnercomms@openai.com |
| Gemini | the initial | Google product icons need a Partner Marketing Hub account and an approval form; no download |

The initial is drawn on the accent, never in a brand's colours, because Google's
rules forbid imitating its colour treatment and OpenAI's forbid colouring the
Blossom. Nothing here is fetched without the owner's terms allowing it.

## editor

ShotScribe's own mark for **Edit the Image**, drawn for this app on 2026-09-16 —
not a borrowed logo. A picture with a pen across it, and a mosaic over the
mountain's flank: the editor's reason to exist is hiding part of a screenshot,
which Preview will not do. `editor.svg` is the source; `editor.png` is rendered
through `scripts/svg-to-png.swift` at 256 pt (512 px) and embedded by
`scripts/make-brand-art.swift` like the brand marks.
