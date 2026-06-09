# Development

## Requirements

- macOS 14 or newer
- Swift 6 toolchain
- Python 3 for client tests run by release packaging
- Node.js 18+ and npm for the TypeScript client tests run by release packaging
- `jq` for the probe scripts

## Run Locally

Run the service directly:

```sh
swift run spotlight-index --host 127.0.0.1 --port 8765
```

Check that it is listening:

```sh
curl http://127.0.0.1:8765/health
```

Pass `--menu-bar` to force the AppKit UI or `--no-menu-bar` to force headless mode from an app bundle.

## Tests

Run the Swift test suite:

```sh
swift test
```

Run the client SDK tests:

```sh
python3 -m unittest discover -s clients/python/tests
cd clients/typescript && npm ci && npm test
```

## Validation Scripts

Run the acceptance matrix against a running local service:

```sh
scripts/probe-acceptance.sh
```

Validate file name and content matching:

```sh
scripts/probe-files.sh
```

Generate the provider capability matrix:

```sh
scripts/generate-capability-matrix.sh
```

This writes [docs/CAPABILITY_MATRIX.md](CAPABILITY_MATRIX.md) from `/v1/capabilities`.

Run the full completion gate:

```sh
scripts/verify-todo-complete.sh
```

This is a maintainer-local acceptance gate. It verifies stable signing, protected provider readiness, the acceptance matrix, file matching, and Photos thumbnail serving against the current user's data. It exits with a clear Full Disk Access message if Mail, Notes, or Safari are not readable.

When auth is enabled, set `SPOTLIGHT_INDEX_AUTH_TOKEN` for the probe and capability scripts. If the local app installer created `~/Library/Application Support/Limelight/auth-token`, the scripts read it automatically.

## Release DMG

Build a signed, notarized release DMG with:

```sh
LIMELIGHT_VERSION=0.1.0 \
LIMELIGHT_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APPLE_APP_PASSWORD="app-specific-password" \
scripts/package-release.sh
```

The release script runs the Swift, Python client, and TypeScript client tests, builds `Limelight.app`, signs it with the hardened runtime, creates a drag-to-Applications `.dmg`, signs the DMG, submits it to Apple notarization, staples the result, and writes artifacts to `dist/`.

You can also use a notarytool keychain profile:

```sh
xcrun notarytool store-credentials limelight-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"

LIMELIGHT_VERSION=0.1.0 \
LIMELIGHT_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
LIMELIGHT_NOTARY_KEYCHAIN_PROFILE=limelight-notary \
scripts/package-release.sh
```

Useful overrides:

```sh
LIMELIGHT_VERSION=0.1.0 LIMELIGHT_BUILD_NUMBER=12 scripts/package-release.sh
LIMELIGHT_BUNDLE_ID=com.example.Limelight scripts/package-release.sh
LIMELIGHT_SKIP_TESTS=1 scripts/package-release.sh
LIMELIGHT_UNSIGNED=1 LIMELIGHT_SKIP_TESTS=1 scripts/package-release.sh
```

Ad-hoc signing is only for local packaging verification. Public releases should use a `Developer ID Application` certificate and notarization; the script fails instead of silently producing a non-notarized public DMG unless `LIMELIGHT_SKIP_NOTARIZATION=1` or `LIMELIGHT_UNSIGNED=1` is set.

## Project Structure

```text
Sources/SpotlightIndexCore/   Core search providers, HTTP API, models, and permission helpers
Sources/spotlight-index/      CLI entry point and menu bar app shell
Tests/                        Swift tests for query building, normalization, providers, and integration behavior
scripts/                      Local install, signing, probes, and validation utilities
clients/python/               Small Python SDK for the local HTTP API
clients/typescript/           TypeScript SDK for Node 18+ and same-origin browser contexts
docs/                         Installation, API, provider, development, and capability docs
```
