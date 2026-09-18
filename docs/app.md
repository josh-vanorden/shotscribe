# The menu bar app

[← Back to the README](../README.md)

`ShotScribe.app` is the always-there face: a menu bar panel with an
auto-rename watch toggle, a **configurable watch folder** ("Change…", which
defaults to your macOS screenshot location), an AI titling switch, **launch at
login**, "Rename latest capture now", and a history of recent renames.

The window's inspector has five tabs: **Folder**, **Rename** (the switch, and
the filename template with a live sample), **AI** (who titles; see [Whose AI is
it?](titlers.md)), **File** (the tag vocabulary) and **Keep**. Any shot's context menu can
file it after the fact.

The newest capture sits at the top as the landing zone. Its title edits in
place when a name is not what you would have said: click it, type, Return. The
date stays, the words change. A row of tiles below it carries the icon of each
service it reaches, named on hover: Finder, **Edit with ShotScribe**, **Share**
(which unfolds into AirDrop, Messages, Mail, Notes…), your assistant, code,
tags.

**Edit with ShotScribe** is its own editor. It pixelates or blacks out a
region, and draws boxes, arrows that bend, highlights, labels and step numbers.
It adds a frame with a margin and a gradient or a picture behind it. It crops
and resizes. A watermark can be your name, a logo, or an audit stamp with the
capture time, the save time, the Mac and a SHA-256 of the original, and it can
be set once and put on every edit. Edits stay editable, and Preview is one
right-click away.

Any shot also drags out as a copy. A moon or sun beside the search field flips
the app between light and dark. First launch opens the window on the folder it
is watching with the inspector open, so the settings are found. A folder with
nothing named yet shows the welcome instead of an empty grid.

Activity logs to `~/Library/Logs/ShotScribe.log`.

```bash
./scripts/package-app.sh     # → dist/ShotScribe.app (ad-hoc signed, no Dock icon)
open dist/ShotScribe.app
```

Auto-rename is ON by default: launching an app whose one job is renaming
screenshots is the opt-in. The toggle is right there in the panel.
