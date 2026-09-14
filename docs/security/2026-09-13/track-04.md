# Track 04 — Dependency & Supply Chain Risk

Target: ShotScribe (Swift package, macOS 13 floor). Audited 2026-09-13 on
`security/20260913-1829`.

## Assessment

**The "zero third-party dependencies" claim is true, verified at every layer.**

- `Package.swift` declares **no `dependencies:` array at all** — no external
  packages, no binary targets, no build plugins, no unsafe flags. Five products,
  six targets, all local.
- **No lockfile of any ecosystem exists** — no `Package.resolved` (correct:
  SwiftPM writes one only when there is a graph to pin), no `package.json`,
  `requirements.txt`, `pyproject.toml`, `Gemfile`, `Podfile`, or `Cartfile`
  anywhere in the tree. Lockfile↔manifest sync is trivially satisfied: both
  are empty.
- `.build/workspace-state.json` shows empty `dependencies`, `artifacts` and
  `prebuilts`; `.build/checkouts/`, `.build/repositories/` and
  `.build/artifacts/` are all empty directories. Nothing was ever fetched.
- **No `.gitmodules`, no `.github/` workflows** — there is no CI pipeline to
  poison and no submodule to redirect.
- **Import surface is Apple-only**: Foundation, AppKit, SwiftUI, Vision,
  AVFoundation, Security, ServiceManagement, QuickLookThumbnailing,
  UniformTypeIdentifiers, CoreGraphics, Darwin (plus XCTest in tests).
- **Build and packaging scripts fetch nothing.** `scripts/package-app.sh` uses
  only `git`, `swift build`, `codesign`, `ditto`, `hdiutil`, `notarytool`,
  `stapler`; `make-iconset.sh` uses `sips`/`iconutil`. No `curl`/`wget`/clone
  in any script. The one `curl` in the repo is in `README.md` and downloads a
  markdown skill file to disk — it is not piped to a shell.

With no package graph, the live supply-chain surface is **runtime, not build
time**: the titlers exec external CLIs (`claude`, `codex`, `gemini`,
`cursor-agent`, `ollama` presets). That resolution is well built:
`Executables.resolve` (`Sources/ShotScribeCore/CommandRunner.swift:76`) probes
a fixed list of well-known install paths first, validates a bare name with
`isPlainName` (alphanumerics plus `._+-`) before the `zsh -lc "command -v …"`
fallback ever runs — so a pasted setting cannot smuggle shell metacharacters —
and never installs, updates, or downloads any of these tools itself.

Two facts worth naming about that surface:

1. `~/.local/bin` and `/opt/homebrew/bin` sit early in the candidate list and
   are user-writable. Anything able to plant a fake `claude` there already
   runs as the user — same trust domain, not a boundary ShotScribe can hold.
   Noted, not fixable from inside the account.
2. This surface is live, not theoretical: **macOS flagged the Codex CLI cask
   0.118.0 as malware today (2026-09-13)**. ShotScribe would invoke whatever
   `codex` is installed, but it does not bundle or auto-install any provider
   CLI, so the exposure belongs to the user's install channel (Homebrew), and
   Gatekeeper/XProtect plus the preset's `--sandbox read-only` flag are the
   mitigations. No change to ShotScribe warranted.

`EndpointTitler` (the only network code) POSTs OCR text to a user-configured
endpoint — a data-flow/transport concern for tracks 05/06, not code supply
chain. No telemetry, no update check, no auto-update framework (no Sparkle),
matching SECURITY.md's claims.

## Risk ranking

**High (confirmed):** none.

**Medium (likely):** none.

**Low (hardening):**

1. **No regression guard on the zero-dependency invariant.** The property the
   README and SECURITY.md lean on was enforced only by habit — a quiet
   `.package(` line in a skimmed PR of a public repo would put outside code
   into every user's build. → **Fixed** (see below).
2. **Runtime CLI binaries resolve from user-writable directories** — same-user
   trust domain, flag only (above).
3. **The README's skill install curls `skills/screenshot/SKILL.md` from the
   unpinned `main` branch** (`README.md:217`). A skill file is agent
   instructions, so a repo compromise changes what the skill tells Claude to
   do on installers' machines. It is fetched over TLS from the project's own
   repo, written to a file (never executed), and installed once with no
   auto-update — inherent to any install-from-repo flow. Pinning to a tag
   trades freshness for immutability; maintainer's call, deferred.
4. **No CI** means the test suite (including the new guard) runs only on
   developer machines. The repo states this is deliberate ("There is no CI.
   Tests run locally only."). Systemic observation, out of scope for this
   pass.

## Implemented fixes

**Commit `76b9217` — `Tests/ShotScribeCoreTests/SupplyChainTests.swift` (new,
2 tests):**

- `testTheManifestStaysDependencyFree` asserts `Package.swift` contains no
  `.package(`, no `.binaryTarget(`, and no `.plugin(`/`plugins:`.
- `testNoResolvedDependencyGraphExists` asserts no `Package.resolved` exists
  at the repo root — a second tripwire that fires even if a dependency arrives
  by a spelling the manifest check misses.

**What attack this prevents:** silent introduction of third-party code —
a dependency, prebuilt binary, or compile-time plugin — into a public repo
whose documented security posture rests on there being none. Adding a real
dependency remains possible; it now has to update this test out loud, the same
way `NameTemplateTests` pins the default filename.

## Deferred (and why)

- **Pinning the README skill-install URL to a release tag** — doc-only change
  with a staleness tradeoff; flagged for the maintainer rather than churned
  here.
- **Runtime binary trust** (`~/.local/bin` etc.) — cannot be hardened from
  within the same user account without breaking how every provider CLI is
  legitimately installed; SECURITY.md already documents the command-preset
  trust model.
- **CI for the test suite** — a project-direction decision, not a surgical
  fix.

## Validation

- **Scanner output: no scanner ran, because there is nothing to scan.** No
  lockfile or manifest of any package ecosystem exists (verified by find over
  the tree). `osv-scanner`, `pip-audit`, and `safety` are not installed on
  this machine and the track rules forbid installing scanners in this pass;
  `npm` exists but there is no Node manifest. Manual verification stood in:
  empty `dependencies`/`artifacts`/`prebuilts` in `.build/workspace-state.json`
  and empty `.build/checkouts|repositories|artifacts` directories.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`:
  **146 tests, 0 failures** (baseline before this track: 144, 0 failures).
- `swift build -c release`: **Build complete**, all products.
