# Spotlight Index TODO

## Current Reality

The local service now resolves the acceptance matrix with real data when launched from `~/Applications/Spotlight Index.app` with Full Disk Access:

- `passport` resolves Photos image results.
- `bennett` resolves Photos person results.
- `bennett` resolves Mail results.
- `bennett` resolves Contacts results.
- `bennett` resolves Calendar birthday results.
- `bennett` resolves Notes results.
- `amazon` resolves Safari history results.

The app uses bundle id `com.bennett.spotlight-index.local`. Mail, Notes, Safari, and other protected stores depend on macOS privacy grants for that bundle identity. Rebuilds should use stable local signing so Full Disk Access survives normal installs.

## Todo

1. [x] Build a real macOS menu bar app.
   - Show service status, provider readiness, and recent searches.
   - Add a permissions page for Full Disk Access, Contacts, Calendar, and Reminders management.
   - Show provider updates and permission failures without requiring terminal output.
   - Keep `swift run` as a headless service path for development and automation.

2. [x] Reinstall once with stable local signing.
   - Use `Codex++ Local Signing` or a configured `SPOTLIGHT_INDEX_CODESIGN_IDENTITY`.
   - Toggle Full Disk Access once after switching from ad-hoc signing to the stable identity.
   - Verify future rebuilds retain TCC permissions.

3. [x] Add an acceptance test runner with pass/fail assertions.
   - Fail when required finish-point searches return zero results.
   - Fail when required providers are unavailable.
   - Keep a human-readable summary for debugging.

4. [x] Redact sensitive fields in probe output.
   - Hide emails, phone numbers, and private URLs in default probe summaries.
   - Keep raw API capability available for trusted local clients.

5. [x] Improve Mail result quality.
   - [x] Resolve message file paths or stable Mail URLs where possible.
   - [x] Add mailbox/account, flags, and richer message identifiers.
   - [x] Add dates, recipients, and snippets where available.
   - [x] Normalize string `"null"` values into JSON `null`.

6. [x] Improve Safari recency and ranking.
   - [x] Sort by latest visit time.
   - [x] Expose `visitedAt` and `visitCount`.
   - [x] Dedupe repeated URLs or related query pages when useful.

7. [x] Add a Photos thumbnail endpoint.
   - Serve safe local thumbnails by asset id.
   - Avoid requiring clients to read inside the Photos library directly.
   - Distinguish still images, screenshots, Live Photos, and videos.

8. [x] Add provider-specific schemas.
   - Extend `/v1/schema` beyond normalized file metadata.
   - Document per-source fields for Photos, Mail, Contacts, Calendar, Notes, Safari, and Reminders.

9. [x] Add permission bootstrap actions.
   - Provide commands or endpoints that intentionally trigger Contacts, Calendar, and Reminders prompts.
   - Explain current Full Disk Access status and the exact app that needs approval.

10. [x] Improve Notes extraction.
    - Decode more Apple Notes body formats.
    - Preserve useful note metadata without exposing full note bodies by default.
    - Add better ranking for title versus body matches.

11. [x] Finish Reminders support.
    - Add modern Reminders store discovery.
    - Add a proper EventKit reminder access request path.
    - Keep clear readiness reporting when no local reminders store exists.

12. [x] Validate file search by name and content.
    - Add acceptance checks that distinguish filename matches from content matches.
    - Reduce noisy default paths such as build folders, browser caches, and `node_modules`.

13. [x] Add a source capability matrix.
    - Generate Markdown or JSON showing source, permission requirement, live status, supported fields, and known limitations.

14. [x] Add an optional HTTP auth guard.
    - Keep loopback binding by default.
    - Add optional bearer-token or Unix-domain socket mode for safer integrations.

15. [x] Add persistent local signing setup.
    - Create or import `Codex++ Local Signing` when missing.
    - Warn loudly before falling back to ad-hoc signing.

16. [x] Add a client SDK.
    - Provide a small TypeScript or Python client for `/v1/search`, `/v1/item`, and `/v1/providers`.
    - Include typed records per source.

## Progress

- Item 1 first pass complete: app-bundle launches now run as a menu bar app with service status, provider readiness, recent searches, 30-second provider refreshes, a permissions window, and privacy shortcuts.
- Item 2 complete: app installs use `Codex++ Local Signing`; the stable-signed app is installed, running, and has retained the macOS privacy grants needed for protected providers.
- Item 2 verification gate complete: `scripts/verify-todo-complete.sh` checks stable signing, protected provider readiness, the acceptance matrix, file matching, and Photos thumbnail serving.
- Item 3 first pass complete: `scripts/probe-acceptance.sh` now exits non-zero when required providers are unavailable or return zero results.
- Item 4 first pass complete: the acceptance probe redacts sensitive-looking emails and phone numbers by default; set `SPOTLIGHT_INDEX_RAW_PROBE=1` for raw output.
- Item 5 complete: Mail metadata maps SQLite nulls to JSON `null`, exposes message ids, message URLs, paths, mailbox labels, flags, dates, recipients, and snippets when available.
- Item 6 complete: Safari results expose `visitedAt` and `visitCount`, prefer latest visit titles, and dedupe tracking-query variants.
- Item 7 complete: `/v1/photos/thumbnail?id=...` serves safe local Photos derivatives, and Photos records include `mediaKind`.
- Item 8 complete: `/v1/schema` includes provider-specific entity types, fields, and metadata fields.
- Item 9 complete: `POST /v1/permissions/request` triggers Contacts, Calendar, and Reminders prompts where macOS allows it and returns Full Disk Access setup hints for protected stores.
- Item 10 complete: Notes supports linked note data/blob decoding, trimmed snippets, title/body match reasons, and title-first ranking.
- Item 11 complete: Reminders uses EventKit when permission is available, requests Reminders access when needed, and discovers private-store candidates as fallback.
- Item 12 complete: `scripts/probe-files.sh` validates filename/content matching, and scoped file searches fall back to bounded filesystem scanning when Spotlight has not indexed fresh files.
- Item 13 complete: `/v1/capabilities` and `scripts/generate-capability-matrix.sh` generate [docs/CAPABILITY_MATRIX.md](docs/CAPABILITY_MATRIX.md).
- Item 14 complete: `SPOTLIGHT_INDEX_AUTH_TOKEN` / `--auth-token` enables bearer-token protection for all endpoints except `/health`.
- Item 15 complete: `scripts/ensure-local-signing-identity.sh` creates `Codex++ Local Signing` when missing, and the installer warns before ad-hoc fallback.
- Item 16 complete: `clients/python/spotlight_index_client.py` provides a dependency-free Python client.
