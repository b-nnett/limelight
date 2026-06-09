# Installation

## Pre-Built App

Download the latest pre-built `.dmg` from [GitHub Releases](https://github.com/b-nnett/limelight/releases), open it, and drag Limelight into your Applications folder.

After installing:

1. Launch Limelight.
2. Grant the macOS permissions it asks for.
3. Grant Full Disk Access to Limelight in System Settings for protected sources such as Mail, Messages, Notes, Safari, and some Calendar/Reminders stores.

Once running, Limelight listens on `127.0.0.1:8765` by default.

Release DMGs are produced with [scripts/package-release.sh](../scripts/package-release.sh).

## Local Development Install

For protected app stores, macOS permissions are tied to a stable app identity. The repo includes an installer that builds and signs a local menu bar app:

```sh
scripts/install-local-app.sh --reset-tcc --open-privacy-settings
```

The app is installed to:

```text
~/Applications/Limelight.app
```

Grant Full Disk Access to that app, then launch it:

```sh
"$HOME/Applications/Limelight.app/Contents/MacOS/Limelight" --host 127.0.0.1 --port 8765
```

When launched from the app bundle, Limelight runs as a menu bar app. The menu shows service status, provider readiness, recent searches, and permission shortcuts.

## Signing

The installer prefers a stable local signing identity. If it is missing, the installer attempts to create it with [scripts/ensure-local-signing-identity.sh](../scripts/ensure-local-signing-identity.sh).

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

## Local HTTP Access

Limelight refuses non-loopback hosts and does not use bearer tokens. Keep it
bound to `127.0.0.1` or `localhost`. Clients can send `X-Origin` to identify
themselves in the recent-search UI:

```sh
curl -H 'X-Origin: Codex' http://127.0.0.1:8765/v1/providers
```
