# Release Concerns Sweep

Date: 2026-06-09

This sweep used five independent review slices: Swift core search, local providers/privacy, HTTP runtime, release packaging/docs, and client SDK/API surface. The list below keeps only concerns with concrete release impact.

## Consensus Release Blockers

1. Crashable HTTP request parsing and unbounded buffering
   - `SpotlightHTTPServer` can crash on malformed `Content-Length` or duplicate query keys before auth is checked.
   - The server also buffers request data without an explicit cap.
   - Release impact: any local process can kill or pressure the menu-bar service.

2. CLI can expose an unauthenticated API on non-loopback hosts
   - App-bundle launches generate a token, but headless CLI launches remain unauthenticated unless `SPOTLIGHT_INDEX_AUTH_TOKEN` or `--auth-token` is set.
   - Release impact: `--host 0.0.0.0` exposes search, OCR, extract, item lookup, and open endpoints.

3. Spotlight file search misses common case/diacritic variants
   - Text predicates are emitted without Spotlight `cd` modifiers.
   - Release impact: simple searches such as lowercase app/file names can miss obvious results.

4. Scoped Spotlight file searches execute globally before filtering
   - `onlyIn` scopes are validated, but `MDQuery` executes across the available index and filters paths afterward.
   - Release impact: scoped searches can be slow or hang on broad queries, then only later apply the requested scope.

5. Calendar/Reminders framework fallbacks can report false failures
   - Calendar and Reminders fall through to private SQLite stores when EventKit access is available but returns zero matches.
   - Calendar also treats macOS 14+ `.writeOnly` as readable.
   - Release impact: users with normal framework permissions can see Full Disk Access errors or incorrect readiness.

6. Photos permission onboarding is inconsistent with implementation
   - Permission bootstrap omits Photos by default and reports explicit Photos as `not_required`, while the provider reads protected Photos library data.
   - Release impact: onboarding can say no action is needed while Photos search fails.

7. Public examples conflict with auth-required app installs
   - The main README/API examples call protected endpoints without the generated bearer token.
   - Release impact: the first installed-app curl flow returns `401`.

8. TypeScript browser positioning is inaccurate
   - The TypeScript client says it works in browsers, but the local server has no CORS/preflight support.
   - Release impact: browser consumers fail before SDK code runs.

9. TypeScript item type omits server fields
   - `ItemResponse.item` lacks `startAt` and `endAt`, which the Swift `ItemRecord` can return.
   - Release impact: calendar/reminder item lookups are incorrectly typed.

## High-Risk Follow-Ups

These are real concerns, but they need broader design or data validation than is appropriate for this sweep:

- Self-update should verify bundle identifier, Team ID, signature, and Gatekeeper assessment before replacing the app.
- OCR should preflight image size/dimensions and downsample before Vision to avoid memory spikes on huge images.
- Photos asset path resolution should prefer real Photos resource tables or PhotoKit export over filename-derived guesses.
- Messages search should add a bounded decoded `attributedBody` fallback for modern messages where `text` is null.
- Release validation docs should distinguish portable smoke checks from maintainer-local, user-data-specific acceptance checks.
- Capability matrix docs should make clear that live readiness is generated from one machine, not universal product readiness.
