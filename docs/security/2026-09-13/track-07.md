# Sub-Agent 7: Unsafe Patterns & Runtime Risk

## Assessment

ShotScribe is a Swift package with no dynamic execution surface at all — no
eval-alikes, no `NSAppleScript`, no scripting bridges, no plugin loading. Its
runtime risk lives in three places: **process spawning** (`CommandRunner`, the
one runner every CLI titler shares), **file operations under concurrency**
(the folder watcher, the renamer's check-then-move, an index file shared by
four processes), and **trust of external text on the failure path** (a child
CLI's streams, an endpoint's HTTP error body — shown to the operator raw,
where the *success* path had already been sanitized by track-02).

### Pattern-by-pattern findings

- **Dynamic execution — none.** The only two `Process()` sites are in
  `Sources/ShotScribeCore/CommandRunner.swift`: the argv-array runner (no
  shell), and the one `zsh -lc "command -v <name>"` in `Executables.compute`,
  reachable only after `isPlainName` restricts the name to `[alnum._+-]` and
  path-shaped names are checked as paths. Verified sound; not touched.
- **Insecure randomness — not applicable.** The only randomness in the tree
  is a `UUID()` for a SwiftUI row identity (`RenameEvent.id`). No tokens,
  session IDs, or filenames derive from randomness anywhere; nothing needs
  `SecRandomCopyBytes`.
- **Unsafe file access** — rename targets are always
  `dir.appendingPathComponent(sanitizedName)` in the file's own directory;
  `Naming.sanitize` strips separators, dot-only words, and (since track-02)
  Cc/Cf. The MCP door tilde-expands caller paths by design ("~ allowed") and
  is gated to capture extensions (track-03). No traversal path found.
- **TOCTOU around file ops — present but fail-safe.** Every
  `Naming.uniqueName` check-then-`moveItem` (rename, retitle, undo, archive)
  can lose its race, but `FileManager.moveItem` **refuses to overwrite** — the
  loser throws and the error surfaces; no file can be clobbered through this
  window. Annotated here rather than churned.
- **Unsafe concurrency — one real hole, fixed.** `FolderWatcher.stop()`
  cancelled the dispatch source but not the debounced scan already queued on
  its serial queue, so a "stopped" watcher could still report a file — and
  trigger a rename — for up to half a second. Everything else checks out:
  `seen`/`debounce` are confined to the watcher's queue (`ignore` uses
  `queue.sync`), `ShotIndex`'s load-modify-save runs under an `NSLock`,
  `Executables`' cache is locked, `DataBox` establishes happens-before via
  `DispatchGroup.wait`, and the app model is `@MainActor`.
- **Trust of external systems** — `EndpointTitler` keeps system TLS validation
  and proxies (no `URLSessionDelegate` trust override anywhere), the session
  is ephemeral (track-06), the scheme is allowlisted (track-06), and replies
  are parsed defensively then label-sanitized. The gap was the **error body**:
  up to 160 bytes of a server-controlled HTTP body (and up to 200 bytes of a
  child CLI's streams in `ClaudeTitler`/`CommandTitler`) were thrown verbatim,
  and those strings reach the operator's terminal (`onTitlerError` → stderr),
  the panel (`lastError`), and the log (`Log.write("titler FAILED: \(error)")`
  — reflection prints the raw associated value, not `errorDescription`).
  Fixed at construction.
- **AI-slop security — none found.** No TODO/FIXME stubs in production paths;
  every comment claiming validation has real code under it
  (`Naming.validate`, `Tagging.accepted`, `Executables.isPlainName`,
  `LabelCleaner.clean` were each read against their claims). The codebase's
  security comments are unusually honest — several document their own attack
  model correctly.

### Looks scary, verified constrained (annotated, not churned)

- **Watchdog pid-reuse race** (`CommandRunner.swift`): `kill(pid, SIGKILL)`
  three seconds after SIGTERM could theoretically hit a reused pid. The
  `proc.isRunning` guard sits immediately before the kill, the child holds its
  pid as a zombie until Foundation reaps it, and the window is microseconds
  wide requiring pid wraparound. Foundation offers no reap-safe kill;
  rewriting the runner for this is not a surgical fix.
- **`Cleanup.apply` acts on a plan the user confirmed earlier** — paths can
  change between preview and apply. The operations are symlink-shallow
  (`removeItem`/`moveItem`/`trashItem` act on the entry, not through it),
  same-user, and scoped to the watched folder; the residual is inherent to any
  confirm-then-act UI.
- **`CommandTitler` runs whatever command template is stored in defaults.**
  An attacker who can write the user's defaults already runs code as the user;
  this is the settings trust boundary, consistent with the repo's model.

## Risk ranking

### High (confirmed)
- None.

### Medium (likely)
1. **A stopped `FolderWatcher` could still fire**
   (`Sources/ShotScribeCore/FolderWatcher.swift`). The hosted-copy stand-down
   (`ShotScribeModel.observeOtherInstances`) exists precisely so two watchers
   never race one capture; the leftover debounced scan reopened that window —
   and a scan could also land a rename *after* the operator toggled watching
   off. **Fixed.**
2. **Untrusted failure text reached the terminal, panel and log raw**
   (`EndpointTitler.Error.http` body, `ClaudeTitler.CLIError.failed`,
   `CommandTitler.Error.failed`). A hostile or compromised endpoint answers
   4xx/5xx with ANSI/OSC escapes in the body; the operator runs
   `shotscribe rename`; the escapes drive their terminal (clear screen, spoof
   output, OSC title/clipboard on some terminals). **Fixed.**

### Low (hardening)
3. **`ShotIndex.save` sealed the index folder after writing, not before**
   (`Sources/ShotScribeCore/SearchIndex.swift`). On the first save after an
   upgrade from a build that created `~/.shotscribe` with default permissions,
   the fresh index and `.atomic`'s adjacent temp file (default 0644) sat
   briefly inside a traversable directory. **Fixed** (reorder only).
4. **The index lock is per-process, but the file is shared by four doors**
   (app, CLI, MCP server, hosted surface). `NSLock` cannot serialize the CLI's
   `record` against the app's `reindex`; `.atomic` prevents corruption but not
   a lost update — including `original`, the name an undo needs. Integrity
   nuisance, not an exploit path. **Deferred** (cross-process file locking is
   an architecture decision, not a surgical fix).
5. **`uniqueName` → `moveItem` TOCTOU** — fail-safe as analyzed above; the
   race loser throws `NSFileWriteFileExists` and the error is reported.
   **No change needed**; noted so a future "fix" doesn't make the move
   overwriting.

## Implemented fixes

1. **`security(track-07): a stopped watcher stays stopped — the pending scan
   dies with it`** — `FolderWatcher.stop()` now cancels the debounced
   `DispatchWorkItem` on the watcher's own queue (`queue.sync`, the same
   confinement `ignore` uses).
   **Old code enabled:** a rename firing up to 0.5s after the caller said
   stop — after the watching toggle was switched off, or after the hosted
   copy stood down because ShotScribe.app owns the folder, recreating the
   two-watchers-one-capture race the stand-down exists to prevent.
   **New code enforces:** `stop()` is a barrier — once it returns, `onNewFile`
   will not be called again.

2. **`security(track-07): failure text is printable before it reaches
   terminal, panel or log`** — new internal `CommandRunner.printable(_:)`
   (Cc/Cf → spaces, the exact rule `LabelCleaner` applies to labels), applied
   at all three error-construction sites: `ClaudeTitler.complete`,
   `CommandTitler.complete` (both also trim, so an all-control reason
   degrades to `.empty`, not `.failed("  ")`), and `EndpointTitler.complete`'s
   HTTP error body.
   **Old code enabled:** terminal escape injection from a hostile endpoint's
   error body or a child CLI's streams — strings printed to stderr by the CLI,
   shown in the panel, and interpolated raw into `~/Library/Logs` (reflection
   bypasses `errorDescription`, so display-time filtering would not have
   covered the log).
   **New code enforces:** every byte of failure text shown anywhere is
   printable; construction-site sanitizing covers all three sinks at once.

3. **`security(track-07): the index folder is sealed before bytes land in
   it`** — `ShotIndex.save` chmods the directory 0700 *before* encoding and
   writing, instead of after; the file chmod to 0600 stays after the write as
   before.
   **Old code enabled:** a same-machine local user reading the freshly
   written index (or the atomic temp file beside it) during the first save
   after an upgrade, while the pre-existing folder was still traversable —
   and the index is, as the repo says, more sensitive than the screenshots.
   **New code enforces:** the directory is owner-only before any index bytes
   exist inside it, on every save.

Three tests pin the fixes in
`Tests/ShotScribeCoreTests/HardeningTests.swift`:
`testAStoppedWatcherNeverReports` (inverted expectation across the debounce
window), `testFailureTextIsPrintableBeforeItIsShown` (ESC/CSI, OSC+BEL, bidi
override, and that ordinary punctuation survives), and
`testSaveSealsAPreexistingLooseIndexFolder` (a 0755 folder ends 0700 after
one save).

## Deferred

- **Cross-process index serialization** (Medium→Low integrity): the honest
  fix is `O_EXLOCK`/`flock` around load-modify-save or an SQLite store —
  either is an architecture change to a file four binaries share, and a lost
  update loses convenience (an undo name), not confidentiality. Flagged as
  systemic.
- **Watchdog pid-reuse hardening**: would mean replacing `Process` with
  `posix_spawn` + `waitpid` bookkeeping to kill only an unreaped child.
  Disproportionate to a microsecond window; flagged.
- **`Cleanup.apply` re-verification** (re-stat each planned path before
  moving): the plan is user-confirmed seconds earlier against user-owned
  files in the watched folder; re-checking adds a new failure mode (plan
  drift) for negligible attack surface. Annotated only.
- **Print-time filtering of foreign on-disk filenames** in `find`/`eval`
  output — already flagged by track-02; unchanged here for the same reason
  (validation belongs at boundaries, and the hostile-filename precondition
  requires another program to have written it).

## Validation

- Tests: **152/152 pass** (was 149; three added) —
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- Build: **clean**, all four products — `swift build -c release` (11.8s)
- Lint: no linter configured in this repo (none run)
- Grep sweeps re-verified: two `Process()` sites only; no
  `eval`/`NSAppleScript`/`system(`/`popen`; no `random`-derived secrets; no
  TODO/FIXME/stub validation in `Sources/`
- API surface: unchanged — no public signature added, removed, or altered
  (`CommandRunner.printable` is internal)
