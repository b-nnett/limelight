# Development

## Requirements

- macOS 14 or newer
- Swift 6 toolchain
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

This verifies stable signing, protected provider readiness, the acceptance matrix, file matching, and Photos thumbnail serving. It exits with a clear Full Disk Access message if Mail, Notes, or Safari are not readable.

When auth is enabled, set `SPOTLIGHT_INDEX_AUTH_TOKEN` for the probe and capability scripts.

## Project Structure

```text
Sources/SpotlightIndexCore/   Core search providers, HTTP API, models, and permission helpers
Sources/spotlight-index/      CLI entry point and menu bar app shell
Tests/                        Swift tests for query building, normalization, providers, and integration behavior
scripts/                      Local install, signing, probes, and validation utilities
clients/python/               Small Python SDK for the local HTTP API
clients/typescript/           TypeScript SDK for Node 18+ and browsers
docs/                         Installation, API, provider, development, and capability docs
```
