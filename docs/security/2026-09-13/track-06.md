# Sub-Agent 6: Transport & Configuration Security

## Assessment

Most of this track's checklist does not apply to ShotScribe, and saying so
precisely is the assessment. There is **no server**: no HTTP listener, no
routes, no HTML served to a browser, no origin that could make a CORS request,
no session a CSRF token would protect. CSP, HSTS, X-Frame-Options,
Referrer-Policy, CORS policy and middleware ordering are properties of a thing
ShotScribe deliberately is not. Verified, not assumed: `URLSession` appears in
exactly one file (`Sources/ShotScribeCore/EndpointTitler.swift:75`), and
`NWListener`/`NWConnection`/`bind` appear nowhere; the MCP server speaks
JSON-RPC over **stdio** only, so its "transport" is the pipe to the local
caller, with process identity as the boundary (track-03's territory).

The real transport surface is one **outbound** HTTP client — `EndpointTitler`,
which POSTs OCR-derived screen text plus an optional Bearer key to a
user-configured OpenAI-compatible endpoint — and the configuration channels
that decide where that request goes. Everything below is about that seam.

### What was verified, and how

1. **TLS is never weakened.** No custom `URLSession` delegate overrides server
   trust, no `NSAppTransportSecurity` dictionary appears in the generated
   Info.plist (`scripts/package-app.sh:33-52`), so certificate validation is
   the system default everywhere. There is nothing here to tighten — the
   important check was that nothing loosens it, and nothing does.

2. **App Transport Security is asymmetric across the four doors** — confirmed
   empirically, not from documentation. A bare compiled Swift binary (the same
   shape as `shotscribe` and `shotscribe-mcp`) was probed against
   `http://ats-probe.invalid` and the TEST-NET IP `http://192.0.2.1`: the
   errors were −1003 (DNS attempted) and −1001 (TCP connect attempted), never
   −1022 (ATS block). **ATS does not enforce for the unbundled CLI/MCP
   binaries** — cleartext HTTP to any remote host is possible there. The
   packaged app, which declares no ATS exceptions, keeps whatever enforcement
   the OS applies to bundles. Consequence: the operative cleartext control is
   not the OS but the app's own warning — `AIProvider.availability()` says
   "plain http: the text read off each capture, and any saved API key, travel
   unencrypted to that host" for any non-loopback/non-`.local` host
   (strengthened by track-01, pinned by
   `AIProviderTests.testPlainHTTPToARemoteHostIsSaidOutLoud`). That warning
   lives in Core, so every door that surfaces availability shows it.

3. **The Bearer key cannot be replayed to a third host via redirect** — also
   confirmed empirically. A loopback pair (127.0.0.1:9060 → 307 →
   127.0.0.1:9061, ports from the personal-backend band) with a client built
   exactly like `EndpointTitler` showed URLSession following the cross-origin
   redirect and re-sending the POST body, but **stripping the Authorization
   header**: the redirector saw `Bearer test-…`, the target saw none. CFNetwork
   already enforces what a custom redirect delegate would have added, so no
   delegate code was written — adding unverifiable "hardening" to the one
   network file would have been pure risk.

4. **The endpoint URL was stored and consumed without a scheme check** — the
   one confirmed gap, now fixed. `ShotScribeDefaults.setAIProvider` persists
   the provider verbatim (`Settings.swift:102`; the endpoint field has no
   validation gate the way name templates do), and `makeTitler()` required
   only that `URL(string:)` parse. A stored `file:` or `ftp:` endpoint would
   have handed URLSession a non-web URL: for `file:`, the "POST" returns the
   file's bytes, `parse()` reads them as a chat reply, and local file content
   flows into filenames, Finder tags, the log and the index. The stored value
   does not always arrive through the AI tab's text field — `defaults write`,
   a `SHOTSCRIBE_DEFAULTS` domain, or the machine preference file can all
   plant it — so the check belongs in Core, at both the readiness line and
   the factory.

5. **Configuration channels are consent-mediated where it matters.** The
   machine-level preference `~/.config/llm/provider.json` (`LLMPreference`)
   can name an arbitrary endpoint, but it is only ever a *suggestion* — the UI
   shows "This Mac prefers …" with a Use-it button
   (`ShotScribeSurface.swift:820-825`); nothing auto-applies it. The
   `SHOTSCRIBE_DEFAULTS` / `SHOTSCRIBE_INDEX` environment overrides require
   control of the process environment, which is already code-execution as the
   user; they are dev affordances, not an exposure. No debug mode, verbose
   traceback surface, or admin panel exists to be left on: the closest
   analogue, `~/Library/Logs/ShotScribe.log`, was made owner-only by track-05
   and never carries raw OCR text.

6. **Residue of the one network call** (fixed): `URLSession.shared` carries a
   persistent cookie jar and a disk `URLCache` shared with nothing else in
   this process worth sharing with. A cooperating endpoint could set durable
   cookies (a cross-call tracking channel), and any cacheable reply — text
   derived from the user's screen — could land under `~/Library/Caches`,
   outside the files whose permissions tracks 03/05 tightened.

## Risk ranking

- **High (confirmed):** none.
- **Medium (likely):** non-web URL schemes reached the network titler's
  factory unchecked (finding 4). **Fixed.**
- **Low (hardening):** shared-session cookie/cache residue (finding 6,
  **fixed**); ATS asymmetry between the bundled app and the CLI/MCP binaries
  (finding 2, **deferred — documented here**); cleartext HTTP to a remote host
  remains *possible with informed consent* rather than refused (finding 2,
  **deferred by design**).

## Implemented fixes

1. **`security(track-06): only http(s) reaches the endpoint titler, from any
   door`** — `AIProvider.isWebScheme` allowlists `http`/`https`
   (case-insensitive) in both `availability()` (readiness line explains: "The
   endpoint must be an http or https URL.") and `makeTitler()` (no titler is
   built otherwise, matching the existing malformed-URL behaviour). New test
   `AIProviderTests.testOnlyWebSchemesReachTheEndpointTitler` pins `ftp:`,
   `file:`, `gopher:` out and uppercase `HTTPS:` in.
   **Attack class mitigated:** configuration-channel scheme smuggling — a
   planted `file:` endpoint turning "the only network code" into a local file
   reader whose contents flow into names, tags, the log and the index.

2. **`security(track-06): the endpoint call keeps no cookies and no cache on
   disk`** — `EndpointTitler` now uses one private
   `URLSession(configuration: .ephemeral)` instead of `URLSession.shared`.
   TLS validation and system proxy behaviour are unchanged; connection reuse
   is kept by sharing the session across calls.
   **Attack class mitigated:** screen-derived request/response data and
   server-set cookies persisting under `~/Library` outside the app's
   permission-tightened files, and cookie-based cross-call tracking by the
   endpoint.

## Deferred, and why

- **Refusing to attach the Bearer key to cleartext remote requests** (or
  refusing cleartext remotes outright). This would break the setup the code
  explicitly supports — a plain-http LAN gateway that wants a key — and the
  informed-consent warning from track-01 already names exactly what is
  exposed. Forcing it is a product decision, not a patch. If taken up: gate it
  in `EndpointTitler.request` so all doors inherit it.
- **ATS parity for the CLI/MCP binaries** (embedding an `__info_plist`
  section, or an in-code cleartext refusal). Same product decision as above
  wearing a build flag: it would hard-fail LAN named-host setups
  (`http://myserver.lan`) that currently work from the CLI. Flagged for the
  maintainer; the report's empirical probe is the evidence to decide with.
- **Certificate pinning** — wrong tool here: the endpoint is user-chosen and
  arbitrary by design; pinning would break every legitimate configuration to
  defend against a CA-compromise attacker far outside this threat model.
- **CSP / HSTS / X-Frame-Options / CORS / middleware ordering** — not
  applicable; there is no server, no served HTML, and no browser origin. No
  header was added anywhere because there is no response to add it to.
- **Redirect-policy delegate** — verified unnecessary (finding 3); recorded so
  a future reader doesn't add one "just in case" into the one network file.

## Validation

- Full suite after both fixes: **149 tests, 0 failures** via
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`;
  `swift build` clean for all products.
- ATS probe: compiled standalone binary, `http://ats-probe.invalid` → −1003
  and `http://192.0.2.1` → −1001 (both *attempted*, neither ATS-blocked);
  `.invalid`/TEST-NET targets so no probe traffic could leave the machine.
- Redirect probe: loopback 9060→9061 (personal-backend port band), 307 with
  Authorization set exactly as `EndpointTitler.request` sets it; result
  `{"redirector_saw_auth": "Bearer …", "target_saw_auth": null,
  "target_body_present": true}`. Both probe servers exited; ports verified
  clear afterwards.
