# Sub-Agent 1: Secrets & Credential Exposure

## Assessment

ShotScribe holds exactly one secret — the optional API key for the endpoint
titler — and the handling around it is unusually disciplined for a side
project. The sweep found **no hardcoded secrets, no committed credentials, no
`.env` usage, and no secret-bearing log lines**. The one substantive gap was a
warning that under-stated an exposure: the plain-http notice named the OCR text
but not the API key that rides the same unencrypted request. Fixed (copy only).

What was checked, and what was found:

- **Hardcoded keys / tokens** — none. A full-history scan
  (`git log --all -p -G` for `sk-…`, `AKIA…`, `ghp_…`, `xox…` shapes) came back
  empty. The only key-shaped strings in the tree are obvious test dummies
  (`sk-test`, `sk-abc` in `Tests/ShotScribeCoreTests/AIProviderTests.swift:79,155`).
- **The one real secret** — the endpoint API key — lives in the login Keychain
  via `Sources/ShotScribeCore/Secrets.swift` (`KeychainStore`): service-scoped
  generic password, `kSecAttrAccessibleWhenUnlocked`, delete-then-add on write.
  Tests swap in `MemoryStore` so they never touch the operator's keychain.
- **Settings never carry the key.** `Sources/ShotScribeCore/Settings.swift`
  persists the provider (kind, model, endpoint URL, command template) but not
  the key; `AIProviderTests.swift:159` *pins* that the key never lands in the
  UserDefaults suite. This invariant is test-enforced, not just convention.
- **UI handling** — `Sources/ShotScribeUI/ShotScribeSurface.swift:867` uses
  `SecureField`, clears the draft after save, and the model exposes only
  `endpointKeyStored: Bool` (`ShotScribeModel.swift:89`, commented "Never the
  key itself"). The key has no read-back path in the UI.
- **No CLI path for the key** — `shotscribe` takes no `--api-key` style flag,
  so the key can never land in shell history or `ps` argv. Entry is app-UI-only.
- **Transit** — the key travels only as an `Authorization: Bearer` header
  (`EndpointTitler.swift:50`), never in the URL, so it cannot leak into server
  access logs via query string.
- **Logging** — `Sources/ShotScribeUI/Log.swift` call sites log filenames,
  titles, tags, and error descriptions. `EndpointTitler.Error.http` includes at
  most 160 chars of the *server's* response body (`EndpointTitler.swift:78`) —
  server-controlled text, not the credential. No log line can contain the key.
- **Build/ship credentials** — `scripts/package-app.sh` uses
  `xcrun notarytool --keychain-profile "$APPLE_NOTARY_PROFILE"`; only the
  profile *name* appears in env/echo, credentials stay in the keychain.
  `apple-ship.config.json` carries `"credentialBackend": "keychain"` and no
  secret material.
- **`~/.config/llm/provider.json`** (`LLMPreference.swift`) — ShotScribe reads
  only `provider`/`endpoint`/`model` from it; no key field is read or written.

### Attack scenarios considered

1. **MITM on a plain-http remote endpoint** (the finding that led to the fix):
   `AIProvider.availability()` warns about `http://` to a non-local host, but
   the warning said only that *the text* travels unencrypted — while
   `EndpointTitler` attaches the Bearer key to that same cleartext request. An
   operator could reasonably conclude their key was safe and only screenshot
   text was exposed. A network-position attacker captures the credential, not
   just one screenshot's text — a durable compromise instead of a one-shot one.
2. **Key exfiltration via settings/export** — blocked by design + pinned test.
3. **Key in logs** — no path found; error bodies are capped and key-free.
4. **Key on child-process argv** — impossible; only `EndpointTitler` (network,
   in-process) consumes the key. CLI titlers never see it.
5. **Screenshot OCR text as a *carrier* of third-party secrets** — the OCR text
   itself can contain on-screen credentials (a password field, an open `.env`).
   It is passed as one argv element to CLI titlers (`ClaudeTitler.swift:92`,
   `CommandTitler.swift:51`), where any same-UID process can read it via
   `ps`/`KERN_PROCARGS2`. Noted as Low: same-UID malware could read the
   screenshot files directly, and `/dev/null` stdin is a documented load-bearing
   design constraint (CLIs stall reading stdin). The index file's sensitivity is
   already called out in the CLI usage text.

## Risk ranking

### High (confirmed vulnerability or exposure)
- None.

### Medium (likely issue or weak pattern)
- **API key sent over plain http to remote hosts, with a warning that omitted
  the key** — `Sources/ShotScribeCore/AIProvider.swift:191` +
  `EndpointTitler.swift:50`. The *warning half* is fixed below. The *behavioral
  half* (actually attaching the key over cleartext http) is deferred — see
  Deferred.

### Low (hardening opportunity)
- **OCR text on child-process argv** (`ClaudeTitler.swift:92`,
  `CommandTitler.swift:48-51`) — same-UID processes can read screenshot text
  (which may itself contain on-screen secrets) via `ps`. Not fixed: stdin is
  deliberately `/dev/null` (documented CLI-stall constraint), and the realistic
  attacker in this trust domain can read the source PNGs anyway.
- **`Secrets.store` is a mutable global** (`Secrets.swift:12`) — any in-process
  code can swap the store. It exists as the test seam; in a single-user app
  with no plugin surface this is acceptable. Flag only.
- **Child processes inherit the full parent environment**
  (`CommandRunner.swift:24-27`). The app sets no secret env vars of its own, so
  today this leaks nothing; worth remembering if that ever changes.
- **Up to 160 chars of server error body reach the log**
  (`EndpointTitler.swift:78` → `ShotScribeModel.swift:703`). Server-controlled,
  capped, same-user log file. Flag only.

## Implemented fixes

- **`Sources/ShotScribeCore/AIProvider.swift:191`** — the plain-http-to-remote
  warning now reads "…the text read off each capture, **and any saved API
  key**, travel unencrypted to that host." **Attack prevented:** an operator
  keeping a real key while pointing at an `http://` gateway on the strength of
  a warning that implied only screenshot text was at risk — the informed-consent
  line now covers the credential a MITM would actually take. **Why safe:** copy
  only, no behavior change; the only test touching this string asserts
  `.contains("unencrypted")` (`AIProviderTests.swift:147`), which still holds.
  This extends the 1.6.1 sweep's own "plain http is said out loud" decision.

## Deferred

- **Refusing to attach the Bearer key over plain http to non-local hosts**
  (`EndpointTitler` / `makeTitler`). This is the actual attack-blocker, but it
  would silently break a legitimate setup — an internal gateway on a trusted
  LAN that requires a token over http — and the project's stated posture is
  informed consent ("said out loud") rather than refusal. Behavioral change of
  this kind needs the operator's call, not a sweep's.
- **No rotation performed** — no live secret was found exposed anywhere, so
  nothing needs rotation. The operator's own endpoint key (if one is stored)
  was never at rest outside the Keychain in any commit.

## Validation

- Tests: **143/143 pass** (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`)
- Lint: no linter configured in this repo (none run)
- Build: **clean** (`swift build -c release`, all four products, 24.6s)
- Security scans: full-history grep for common credential shapes (AWS, OpenAI,
  GitHub, Slack) — no hits; no `.env` files present or ignored-but-expected;
  working tree contains no secret material outside the Keychain.
