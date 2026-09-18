# Hosting the ShotScribe pane

[← Back to the README](../README.md)

## Mounting the face somewhere else

The panel is a library, not a private part of the app. `ShotScribeUI` exposes
one view:

```swift
import ShotScribeUI

ShotScribeSurface(chrome: .hosted)   // roomy detail pane
ShotScribeSurface(chrome: .menuBar)  // the 340pt popover
```

It owns its own state, takes no other arguments, and knows nothing about what's
hosting it. `.hosted` omits "Launch at login" and "Quit" on purpose —
`SMAppService.mainApp` and `NSApplication.shared.terminate` would act on the
*host*, not on ShotScribe.

Two things a host gets for free, because they're ShotScribe's job and not the
host's:

- **Your settings come with it.** The surface reads the
  `com.joshvanorden.shotscribe` preferences domain by name, so a copy running
  inside another app sees the watch folder you actually chose and the history
  you actually have — rather than starting blank and renaming files somewhere
  you never pointed it at.
- **It won't fight ShotScribe.app.** Two live watchers would race to rename the
  same capture. A hosted copy notices the standalone app running, says so, and
  stands down until you quit it.

[Toolbelt](https://github.com/josh-vanorden/toolbelt) mounts it this way; its
whole integration is a twenty-line adapter. ShotScribe has no dependency on
Toolbelt and never will.
