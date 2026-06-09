#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Limelight"
BUNDLE_ID="com.bennett.spotlight-index.local"
APP_DIR="${SPOTLIGHT_INDEX_APP_DIR:-$HOME/Applications/$APP_NAME.app}"
HOST="${SPOTLIGHT_INDEX_HOST:-127.0.0.1}"
PORT="${SPOTLIGHT_INDEX_PORT:-8765}"
AUTH_TOKEN="${SPOTLIGHT_INDEX_AUTH_TOKEN:-}"
DEFAULT_CODESIGN_IDENTITY="Codex++ Local Signing"
REQUESTED_CODESIGN_IDENTITY="${SPOTLIGHT_INDEX_CODESIGN_IDENTITY:-}"
AUTO_CREATE_SIGNING_IDENTITY="${SPOTLIGHT_INDEX_AUTO_CREATE_SIGNING_IDENTITY:-1}"
INSTALL_LAUNCH_AGENT=0
OPEN_PRIVACY_SETTINGS=0
RESET_TCC=0

usage() {
  cat <<'USAGE'
Usage: scripts/install-local-app.sh [--launch-agent] [--open-privacy-settings]

Builds spotlight-index and installs a stable local app bundle:
  ~/Applications/Limelight.app

Options:
  --launch-agent           Install and load a per-user LaunchAgent that starts the app at login.
  --open-privacy-settings  Open System Settings > Privacy & Security > Full Disk Access.
  --reset-tcc              Reset Contacts, Calendar, Reminders, and Full Disk Access TCC entries for this bundle id.

Environment:
  SPOTLIGHT_INDEX_APP_DIR  Override install path for the .app bundle.
  SPOTLIGHT_INDEX_HOST     Host passed to the service, default 127.0.0.1.
  SPOTLIGHT_INDEX_PORT     Port passed to the service, default 8765.
  SPOTLIGHT_INDEX_AUTH_TOKEN
                         Optional bearer token required by all endpoints except /health.
  SPOTLIGHT_INDEX_CODESIGN_IDENTITY
                         Code signing identity to use. Defaults to "Codex++ Local Signing"
                         when present, then the first valid local code signing identity,
                         then ad-hoc signing as a last resort.
  SPOTLIGHT_INDEX_AUTO_CREATE_SIGNING_IDENTITY
                         Set to 0 to disable automatic creation of the default local
                         signing identity when it is missing.
USAGE
}

resolve_codesign_identity() {
  if [[ -n "$REQUESTED_CODESIGN_IDENTITY" ]]; then
    printf '%s\n' "$REQUESTED_CODESIGN_IDENTITY"
    return
  fi

  if security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$DEFAULT_CODESIGN_IDENTITY\"" >/dev/null; then
    printf '%s\n' "$DEFAULT_CODESIGN_IDENTITY"
    return
  fi

  if [[ "$AUTO_CREATE_SIGNING_IDENTITY" != "0" && -x "$ROOT_DIR/scripts/ensure-local-signing-identity.sh" ]]; then
    "$ROOT_DIR/scripts/ensure-local-signing-identity.sh" "$DEFAULT_CODESIGN_IDENTITY" >&2 || true
    if security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$DEFAULT_CODESIGN_IDENTITY\"" >/dev/null; then
      printf '%s\n' "$DEFAULT_CODESIGN_IDENTITY"
      return
    fi
  fi

  local first_identity
  first_identity="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/^[[:space:]]*[0-9]+\\)/ { print $2; exit }')"
  if [[ -n "$first_identity" ]]; then
    printf '%s\n' "$first_identity"
    return
  fi

  echo "warning: no valid local code-signing identity found; falling back to ad-hoc signing, which can invalidate TCC permissions on rebuild" >&2
  printf '%s\n' "-"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --launch-agent)
      INSTALL_LAUNCH_AGENT=1
      ;;
    --open-privacy-settings)
      OPEN_PRIVACY_SETTINGS=1
      ;;
    --reset-tcc)
      RESET_TCC=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

cd "$ROOT_DIR"
swift build -c release --product spotlight-index

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$ROOT_DIR/.build/release/spotlight-index" "$APP_DIR/Contents/MacOS/spotlight-index"
cp "$ROOT_DIR/Sources/spotlight-index/Resources/limelight.png" "$APP_DIR/Contents/Resources/limelight.png"
cp "$ROOT_DIR/Sources/spotlight-index/Resources/limelight-menu.png" "$APP_DIR/Contents/Resources/limelight-menu.png"
cp "$ROOT_DIR/Sources/spotlight-index/Resources/limelight-menu-template.png" "$APP_DIR/Contents/Resources/limelight-menu-template.png"

ICON_TMP_DIR="$(mktemp -d)"
ICONSET_DIR="$ICON_TMP_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ROOT_DIR/Sources/spotlight-index/Resources/limelight.png" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ROOT_DIR/Sources/spotlight-index/Resources/limelight.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ROOT_DIR/Sources/spotlight-index/Resources/limelight.png" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ROOT_DIR/Sources/spotlight-index/Resources/limelight.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ROOT_DIR/Sources/spotlight-index/Resources/limelight.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ROOT_DIR/Sources/spotlight-index/Resources/limelight.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ROOT_DIR/Sources/spotlight-index/Resources/limelight.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ROOT_DIR/Sources/spotlight-index/Resources/limelight.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ROOT_DIR/Sources/spotlight-index/Resources/limelight.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ROOT_DIR/Sources/spotlight-index/Resources/limelight.png" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -rf "$ICON_TMP_DIR"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>spotlight-index</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_NAME</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSCalendarsFullAccessUsageDescription</key>
	<string>Limelight reads local Calendar metadata to return matching local search results.</string>
	<key>NSCalendarsUsageDescription</key>
	<string>Limelight reads local Calendar metadata to return matching local search results.</string>
	<key>NSContactsUsageDescription</key>
	<string>Limelight reads local Contacts metadata to return matching local search results and birthday fallback records.</string>
	<key>NSRemindersUsageDescription</key>
	<string>Limelight reads local Reminders metadata to return matching local search results.</string>
</dict>
</plist>
PLIST

CODESIGN_IDENTITY="$(resolve_codesign_identity)"
codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_DIR"

if [[ "$RESET_TCC" -eq 1 ]]; then
  for service in AddressBook Calendar Reminders SystemPolicyAllFiles; do
    tccutil reset "$service" "$BUNDLE_ID" >/dev/null 2>&1 || true
  done
fi

if [[ "$INSTALL_LAUNCH_AGENT" -eq 1 ]]; then
  AGENT_DIR="$HOME/Library/LaunchAgents"
  AGENT_PLIST="$AGENT_DIR/$BUNDLE_ID.plist"
  mkdir -p "$AGENT_DIR"
  cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$BUNDLE_ID</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>-gj</string>
		<string>$APP_DIR</string>
		<string>--args</string>
		<string>--host</string>
		<string>$HOST</string>
		<string>--port</string>
		<string>$PORT</string>
PLIST
  if [[ -n "$AUTH_TOKEN" ]]; then
    cat >> "$AGENT_PLIST" <<PLIST
		<string>--auth-token</string>
		<string>$AUTH_TOKEN</string>
PLIST
  fi
  cat >> "$AGENT_PLIST" <<PLIST
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<false/>
	<key>StandardOutPath</key>
	<string>$HOME/Library/Logs/spotlight-index.out.log</string>
	<key>StandardErrorPath</key>
	<string>$HOME/Library/Logs/spotlight-index.err.log</string>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$(id -u)" "$AGENT_PLIST" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"
fi

if [[ "$OPEN_PRIVACY_SETTINGS" -eq 1 ]]; then
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
fi

echo "Installed $APP_DIR"
echo "Bundle identifier: $BUNDLE_ID"
echo "Code signing identity: $CODESIGN_IDENTITY"
if [[ -n "$AUTH_TOKEN" ]]; then
  echo "HTTP auth: enabled"
else
  echo "HTTP auth: disabled"
fi
echo "Grant Full Disk Access to this app bundle, then launch it with:"
if [[ -n "$AUTH_TOKEN" ]]; then
  echo "  open -gj \"$APP_DIR\" --args --host \"$HOST\" --port \"$PORT\" --auth-token \"<token>\""
else
  echo "  open -gj \"$APP_DIR\" --args --host \"$HOST\" --port \"$PORT\""
fi
