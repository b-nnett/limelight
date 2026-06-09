# Installation

## Pre-Built App

Download the latest pre-built `.dmg` from [GitHub Releases](https://github.com/b-nnett/limelight/releases), open it, and drag Limelight into your Applications folder.

After installing:

1. Launch Limelight.
2. Grant the macOS permissions it asks for.
3. Grant Full Disk Access to Limelight in System Settings for protected sources such as Mail, Messages, Notes, Safari, and some Calendar/Reminders stores.

Once running, Limelight listens on `127.0.0.1:8765` by default.

## Local Development Install

For protected app stores, macOS permissions are tied to a stable app identity. The repo includes an installer that builds and signs a local menu bar app with bundle id `com.bennett.spotlight-index.local`:

```sh
scripts/install-local-app.sh --reset-tcc --open-privacy-settings
```

The app is installed to:

```text
~/Applications/Limelight.app
```

Grant Full Disk Access to that app, then launch it:

```sh
open -gj "$HOME/Applications/Limelight.app" --args --host 127.0.0.1 --port 8765
```

When launched from the app bundle, Limelight runs as a menu bar app. The menu shows service status, provider readiness, recent searches, and permission shortcuts.

## Signing

The installer prefers the local signing identity `Codex++ Local Signing`. If it is missing, the installer attempts to create it with [scripts/ensure-local-signing-identity.sh](../scripts/ensure-local-signing-identity.sh).

Override the identity with:

```sh
SPOTLIGHT_INDEX_CODESIGN_IDENTITY="Your Local Identity" scripts/install-local-app.sh
```

If the signing identity changes, toggle Full Disk Access again for `~/Applications/Limelight.app`. Normal rebuilds should retain approval when the same signing identity is used.

## Launch At Login

To start the app at login:

```sh
scripts/install-local-app.sh --launch-agent
```

## Authentication

By default, the service binds to `127.0.0.1` without authentication. Add an optional bearer token for local integrations:

```sh
SPOTLIGHT_INDEX_AUTH_TOKEN="local-token" swift run spotlight-index --host 127.0.0.1 --port 8765
```

Then call protected endpoints with:

```sh
curl -H "Authorization: Bearer local-token" http://127.0.0.1:8765/v1/providers
```

When installing a LaunchAgent, set `SPOTLIGHT_INDEX_AUTH_TOKEN` during install to persist the token in the LaunchAgent arguments.
