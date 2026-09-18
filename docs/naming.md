# Naming and tags

[← Back to the README](../README.md)

## Naming

The name is a template. `{date} {time} {title}` is the default and spells
exactly what ShotScribe has always spelled, so an upgrade changes nobody's
names. Edit it in the window's **Name** tab: the layout carries the separators
(`{date}_{time}_{title}` is how you get underscores), and pickers cover the
date style, the time style, how the title's words are joined, and how many are
kept. A fourth token, `{app}`, is the app or window name read off the capture's
own menu bar or title bar; it is best effort and simply empty when the shot has
no chrome. A template that would spell a name macOS uses for a fresh capture is
refused, because the watcher would then rename its own output forever.

## Tags

A renamed capture is also filed under up to two **Finder tags** — so it shows in
Finder, sorts in the sidebar, and answers a Spotlight search without ShotScribe
running at all.

Tags come from a fixed list (`terminal`, `code`, `error`, `browser`, `docs`,
`chat`, `email`, `calendar`, `design`, `dashboard`, `settings`, `logs`,
`ticket`, `meeting`, `diagram`, `receipt`). That is deliberate: the text on your
screen is not always text you wrote, so a screenshot never gets to invent a tag
of its own — anything off the list is dropped. Tags you added by hand are kept.
`--no-tags` turns filing off.
