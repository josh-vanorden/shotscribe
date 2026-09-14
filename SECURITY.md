# Security

## Reporting

Open a private security advisory on this repository (GitHub › Security ›
Report a vulnerability). Please do not file a public issue for anything that
could expose a user's screenshots or their text. Reports get a reply within a
week; a fix ships as a patch release and is named in `CHANGELOG.md`.

## What ShotScribe trusts, and what it does not

- **Text on the screen is untrusted.** It reaches the titler as data. When
  Claude titles, `claude -p` runs with every tool disabled
  (`--disallowedTools Bash,Read,Write,Edit,WebFetch,…`) and `--strict-mcp-config`
  with no servers, so a prompt-injection payload in a screenshot has nothing to
  execute. The other CLI presets ship with their tool-denying flags (`codex
  exec --sandbox read-only`, `gemini --sandbox`); they are commands the user
  can see and edit, and the AI tab says to keep those flags. A custom command
  is the user's own responsibility; its first token must be a plain name
  (letters, digits, `._+-`) or a path before the login-shell lookup runs, so
  a pasted setting cannot smuggle a shell metacharacter into `command -v`. The reply is cut to a few words and
  stripped of path characters before it becomes a file name; a title cannot
  carry a path component.
- **The endpoint titler is the only network code.** It POSTs to the base URL
  the user typed, only when an endpoint is the chosen titler, with a key read
  from the login Keychain (`com.joshvanorden.shotscribe` / `endpoint-api-key`)
  and never written to the settings file. A plain-`http` base URL to a
  host that is not local is accepted but said out loud in the AI tab: the text
  read off each capture would travel unencrypted.
- **Tags come only from the user's list.** Whatever proposes a tag — the
  model, an MCP caller, anything — `Tagging.accepted` drops what is not in the
  vocabulary. A screenshot never invents its own filing.
- **Only macOS default capture names are renamed.** A user-named file is
  protected unless the user passes `force`. The MCP server takes the caller's
  title but keeps the same rule.
- **The MCP server is mechanical.** It never calls a model; it reads and
  renames on behalf of the model that called it, on the caller's machine, over
  stdio. It has no network listener.
- **Nothing leaves the machine except the text handed to the chosen titler**
  when AI titling is on — and with Ollama or the offline titler, nothing at
  all. No telemetry, no update check. The app is Developer ID signed and
  notarized; the hardened runtime is on and it holds no entitlements.
- **The index is the most sensitive artefact.** `~/.shotscribe/index.json`
  holds the text of every capture and is written mode 0600 in a 0700 folder.
  Treat it like the screenshots.

## Supported versions

The latest release. Older tags are not patched.

## The sweeps on record

- **2026-09-12, 1.5.1** — by hand: the index made owner-only; a dot-only title
  word dropped.
- **2026-09-13, 1.6.1** — by hand: a command name validated before the shell
  lookup; plain http to a remote host flagged.
- **2026-09-13, 1.6.2** — the seven-track `/security-team` pass (reports in
  `docs/security/2026-09-13/`), twelve surgical fixes, none High: a saved API
  key is never sent over plain http to a non-local host; only `http(s)` reaches
  the endpoint titler, on an ephemeral session (no cookies, no cache); `force`
  renames captures only, and the MCP door honours the tagging-off switch; a
  label and a titler's failure text cannot carry control or bidi characters;
  the MCP OCR tools mark their text as data, never instructions; the log is
  owner-only and the index folder is sealed before bytes land; a stopped
  watcher takes its pending scan with it; the CLI strips control characters at
  print; the dependency-free manifest is pinned by a test.

