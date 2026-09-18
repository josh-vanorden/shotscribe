# Contributing to ShotScribe

Issues and pull requests are welcome. ShotScribe renames people's files and
reads what is on their screen, so a few of its rules are load-bearing. None of
them can be guessed from the code, which is why this file exists.

## Before you write code

**A security report does not go in a public issue.** Open a private advisory
(Security › Report a vulnerability). [SECURITY.md](SECURITY.md) has the detail.

For anything else, an issue first can save you a weekend: say what you want to
change and why, before building it.

## The rules a pull request has to respect

### 1. No dependencies

Every product builds from Apple's SDKs alone. That is what makes "no telemetry,
no update check" something a reader can audit. `SupplyChainTests` fails if
`Package.swift` gains a `.package(`, a `.binaryTarget(` or a build plugin, or if
a `Package.resolved` appears. The test is not broken. If you think a dependency
is worth it, make the case in an issue; a change that adds one also changes that
test, on purpose and in the open.

### 2. The default name never changes

`NameTemplateTests` pins `{date} {time} {title}` to spell exactly what
ShotScribe has always spelled, so an upgrade renames nobody's files differently.
New tokens and styles are welcome. A different default is not.

### 3. A screenshot never invents a tag

Tags come from the user's list (`Settings.vocabulary()`). Every titler is handed
that list and may only answer from it; anything else is dropped. The text on a
screen is not always text the user wrote, so a capture must not be able to write
its own filing. A feature that lets the titler "suggest new tags" breaks this,
however helpful it sounds.

### 4. A titler must not be able to act

The same reasoning covers the Claude titler (`ClaudeTitler.swift`) and the CLI
presets in `AIProvider.swift`. Each ships with the flags that stop the tool from
doing anything with the text except answer:
`--disallowedTools` and `--strict-mcp-config` for Claude Code,
`--sandbox read-only` for Codex, `--sandbox` for Gemini CLI. A new preset needs
its equivalent. One without it will not be merged.

### 5. Most fixes belong in ShotScribeCore

`ShotScribeCore` is the engine behind all three doors: the app (`ShotScribeUI`,
`shotscribe-menubar`), the CLI (`shotscribe`) and the MCP server
(`shotscribe-mcp`). A fix that lands in one door leaves the bug in the other
two. The MCP server stays mechanical: it never calls a model and has no network
listener.

## Build and test

```bash
swift build
swift test
```

The release is universal, so a change has to work on Intel too. On an Apple
silicon Mac, `swift test --arch x86_64` builds the Intel tests and then does not
run them: its helper launches as arm64 and cannot load the bundle. Run the Intel
slice under Rosetta instead:

```bash
swift build --build-tests --arch x86_64
arch -x86_64 xcrun xctest .build/x86_64-apple-macosx/debug/shotscribePackageTests.xctest
```

## Sending the change

- One change per pull request, with the reason in the description.
- New behaviour comes with a test. `Tests/ShotScribeCoreTests` is where they live.
- If a user would notice the change, add a line under **Unreleased** in
  `CHANGELOG.md`, in the voice of the lines already there.
- Redact any screenshot you attach to an issue or a pull request. ShotScribe's
  own editor does that.

Contributions are MIT, like the rest.
