# ShotScribe CLI reference

[← Back to the README](../README.md)

## Usage

```bash
# Print the title shotscribe would give a shot (no rename) — the quickest way
# to see the Claude connection working end-to-end:
shotscribe label "~/Desktop/Screenshot 2026-08-11 at 3.41.07 PM.png"

# Rename one capture in place:
shotscribe rename "~/Desktop/Screenshot 2026-08-11 at 3.41.07 PM.png"

# See what it WOULD do, without moving anything:
shotscribe rename --dry-run "~/Desktop/Screenshot ....png"

# Watch a folder and rename new captures as they land
# (defaults to your macOS screenshot location):
shotscribe watch
shotscribe watch ~/Pictures/Screenshots

# Skip the AI tab's choice for one run and use the offline keyword titler:
shotscribe label --offline "~/Desktop/Screenshot ....png"

# Who titles, as the AI tab set it (SHOTSCRIBE_DEFAULTS=<domain> tries another):
shotscribe ai

# Rename without filing it under Finder tags:
shotscribe rename --no-tags "~/Desktop/Screenshot ....png"

# How good is the titler? Score it against the names you kept:
shotscribe eval --limit 25
```

`eval` treats your own folder as the test set: every capture that is already
named is a judged answer, and its Finder tags a judged filing. It re-titles each
one and reports exact matches, title recall and tag precision and recall, so a
prompt change or a different titler gets a number instead of a feeling. (The
shape is borrowed from screenshot-to-code's evals; the twist is that no fixture
set is needed.) One honest caveat: the names it judges against are only as good
as whoever kept them. If the offline titler named a fortnight of captures while
Claude was signed out, it will agree with itself; the number is a regression
check then, not a quality score.

## Finding a screenshot again

ShotScribe reads every capture to name it. It now **keeps** that text instead of
discarding it, so you can search what a screenshot *said* rather than what it got
called — a three-word title is a thin hook a month later.

```bash
shotscribe index            # read the watched folder into the index
shotscribe find "NXDOMAIN"  # search what they say
shotscribe find error       # …or how they are filed
```

The search field in the app does the same thing, and new captures index
themselves the moment they are renamed. Tags are searched alongside the text and
rank with the filename, since a tag was chosen deliberately and body text merely
crossed the screen. In the app the tags sit on each tile; clicking one isolates
everything filed the same way, a strip above the grid lists every tag in use
with its count (click to isolate, a second to narrow, Clear to undo), and
**By tag** in the sort menu groups the grid by filing. A tag you add by hand in Finder is picked up by
the next sweep.

`SHOTSCRIBE_INDEX=/tmp/scratch.json shotscribe …` points the index somewhere
else, which is how to try the CLI against a folder without writing into your own
searchable history.

Two deliberate choices:

- **The index OCRs again rather than reusing the label's text.** Labelling is
  capped at 900 characters — right for a title, wrong for search, since 900
  characters stops partway down most screenshots and the strings you would
  search for (`i-0a3f`, `NXDOMAIN`, `PROJ-4821`) are as likely below the cut.
- **It indexes the folder, not the rename history.** That history is capped and
  holds no paths, so a search built on it would only ever see the last handful.

The index is more sensitive than the screenshots it describes: see [Privacy](privacy.md#on-sensitivity).
