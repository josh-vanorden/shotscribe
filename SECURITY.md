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
  execute. The reply is cut to a few words and stripped of path characters
  before it becomes a file name; a title cannot carry a path component.
- **Tags come only from the user's list.** Whatever proposes a tag — the
  model, an MCP caller, anything — `Tagging.accepted` drops what is not in the
  vocabulary. A screenshot never invents its own filing.
- **Only macOS default capture names are renamed.** A user-named file is
  protected unless the user passes `force`. The MCP server takes the caller's
  title but keeps the same rule.
- **The MCP server is mechanical.** It never calls a model; it reads and
  renames on behalf of the model that called it, on the caller's machine, over
  stdio. It has no network listener.
- **Nothing leaves the machine except the text handed to `claude -p`** when
  Claude titling is on. No telemetry, no update check, no network code of its
  own. The app is Developer ID signed and notarized; the hardened runtime is
  on and it holds no entitlements.
- **The index is the most sensitive artefact.** `~/.shotscribe/index.json`
  holds the text of every capture and is written mode 0600 in a 0700 folder.
  Treat it like the screenshots.

## Supported versions

The latest release. Older tags are not patched.
