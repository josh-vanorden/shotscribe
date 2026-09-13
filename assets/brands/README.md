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
