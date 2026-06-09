#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${LIMELIGHT_APP_NAME:-Limelight}"
PRODUCT_NAME="spotlight-index"
BUNDLE_ID="${LIMELIGHT_BUNDLE_ID:-com.bennett.limelight}"
VERSION="${LIMELIGHT_VERSION:-}"
BUILD_NUMBER="${LIMELIGHT_BUILD_NUMBER:-}"
CODESIGN_IDENTITY="${LIMELIGHT_CODESIGN_IDENTITY:-}"
DIST_DIR="${LIMELIGHT_DIST_DIR:-$ROOT_DIR/dist}"
SKIP_TESTS="${LIMELIGHT_SKIP_TESTS:-0}"
SKIP_NOTARIZATION="${LIMELIGHT_SKIP_NOTARIZATION:-0}"
UNSIGNED="${LIMELIGHT_UNSIGNED:-0}"
NOTARY_PROFILE="${LIMELIGHT_NOTARY_KEYCHAIN_PROFILE:-}"

usage() {
  cat <<'USAGE'
Usage: scripts/package-release.sh

Builds a production release app bundle and drag-to-Applications DMG.

Environment:
  LIMELIGHT_VERSION                 Release version. Defaults to latest git tag, then 0.1.0.
  LIMELIGHT_BUILD_NUMBER            Build number. Defaults to git commit count.
  LIMELIGHT_BUNDLE_ID               Bundle identifier. Defaults to com.bennett.limelight.
  LIMELIGHT_CODESIGN_IDENTITY       Developer ID Application signing identity.
  LIMELIGHT_DIST_DIR                Artifact directory. Defaults to dist/.
  LIMELIGHT_NOTARY_KEYCHAIN_PROFILE notarytool keychain profile.
  APPLE_ID
  APPLE_TEAM_ID
  APPLE_APP_PASSWORD                App-specific password notarization credentials.
  LIMELIGHT_SKIP_TESTS=1            Skip Swift, Python, and TypeScript tests.
  LIMELIGHT_SKIP_NOTARIZATION=1     Build a signed but unnotarized DMG.
  LIMELIGHT_UNSIGNED=1              Build an ad-hoc signed local DMG for verification only.

Production releases require a Developer ID Application certificate and notarization.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

default_version() {
  local tag
  tag="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || true)"
  if [[ -n "$tag" ]]; then
    printf '%s\n' "${tag#v}"
  else
    printf '0.1.0\n'
  fi
}

default_build_number() {
  local count
  count="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || true)"
  if [[ -n "$count" && "$count" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$count"
  else
    date -u +%Y%m%d%H%M
  fi
}

resolve_developer_id_identity() {
  if [[ -n "$CODESIGN_IDENTITY" ]]; then
    printf '%s\n' "$CODESIGN_IDENTITY"
    return
  fi

  local identity
  identity="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Developer ID Application/ { print $2; exit }')"
  if [[ -n "$identity" ]]; then
    printf '%s\n' "$identity"
    return
  fi

  die "no Developer ID Application signing identity found. Set LIMELIGHT_CODESIGN_IDENTITY, or use LIMELIGHT_UNSIGNED=1 for local packaging verification."
}

create_icon() {
  local source_png="$1"
  local output_icns="$2"
  local tmpdir iconset
  tmpdir="$(mktemp -d)"
  iconset="$tmpdir/AppIcon.iconset"
  mkdir -p "$iconset"

  sips -z 16 16 "$source_png" --out "$iconset/icon_16x16.png" >/dev/null
  sips -z 32 32 "$source_png" --out "$iconset/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$source_png" --out "$iconset/icon_32x32.png" >/dev/null
  sips -z 64 64 "$source_png" --out "$iconset/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$source_png" --out "$iconset/icon_128x128.png" >/dev/null
  sips -z 256 256 "$source_png" --out "$iconset/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$source_png" --out "$iconset/icon_256x256.png" >/dev/null
  sips -z 512 512 "$source_png" --out "$iconset/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$source_png" --out "$iconset/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$source_png" --out "$iconset/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$iconset" -o "$output_icns"
  rm -rf "$tmpdir"
}

write_info_plist() {
  local plist_path="$1"
  cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$PRODUCT_NAME</string>
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
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD_NUMBER</string>
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
}

run_tests() {
  require_command python3
  require_command npm
  swift test
  python3 -m unittest discover -s clients/python/tests
  (cd clients/typescript && npm ci && npm test)
}

notary_args=()
configure_notarization() {
  if [[ "$UNSIGNED" == "1" ]]; then
    SKIP_NOTARIZATION=1
    return
  fi

  if [[ "$SKIP_NOTARIZATION" == "1" ]]; then
    return
  fi

  require_command xcrun
  if [[ -n "$NOTARY_PROFILE" ]]; then
    notary_args=(--keychain-profile "$NOTARY_PROFILE")
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    notary_args=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
  else
    die "notarization credentials are required. Set LIMELIGHT_NOTARY_KEYCHAIN_PROFILE or APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD. Use LIMELIGHT_SKIP_NOTARIZATION=1 only for non-public builds."
  fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

VERSION="${VERSION:-$(default_version)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(default_build_number)}"
case "$DIST_DIR" in
  /*) ;;
  *) DIST_DIR="$ROOT_DIR/$DIST_DIR" ;;
esac
WORK_DIR="$DIST_DIR/package-work"
APP_DIR="$WORK_DIR/$APP_NAME.app"
STAGING_DIR="$WORK_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
RW_DMG_PATH="$WORK_DIR/$APP_NAME-$VERSION.rw.dmg"

require_command swift
require_command sips
require_command iconutil
require_command hdiutil
require_command codesign

configure_notarization

cd "$ROOT_DIR"

if [[ "$SKIP_TESTS" != "1" ]]; then
  run_tests
fi

swift build -c release --product "$PRODUCT_NAME"

rm -rf "$WORK_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$DIST_DIR"

cp "$ROOT_DIR/.build/release/$PRODUCT_NAME" "$APP_DIR/Contents/MacOS/$PRODUCT_NAME"
cp "$ROOT_DIR/Sources/spotlight-index/Resources/limelight.png" "$APP_DIR/Contents/Resources/limelight.png"
cp "$ROOT_DIR/Sources/spotlight-index/Resources/limelight-menu.png" "$APP_DIR/Contents/Resources/limelight-menu.png"
cp "$ROOT_DIR/Sources/spotlight-index/Resources/limelight-menu-template.png" "$APP_DIR/Contents/Resources/limelight-menu-template.png"
create_icon "$ROOT_DIR/Sources/spotlight-index/Resources/limelight.png" "$APP_DIR/Contents/Resources/AppIcon.icns"
write_info_plist "$APP_DIR/Contents/Info.plist"

if [[ "$UNSIGNED" == "1" ]]; then
  codesign --force --deep --sign - "$APP_DIR"
else
  CODESIGN_IDENTITY="$(resolve_developer_id_identity)"
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$RW_DMG_PATH" "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -fs HFS+ -format UDRW "$RW_DMG_PATH" >/dev/null
hdiutil convert "$RW_DMG_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null

if [[ "$UNSIGNED" != "1" ]]; then
  codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --strict --verbose=2 "$DMG_PATH"
fi

if [[ "$SKIP_NOTARIZATION" != "1" ]]; then
  xcrun notarytool submit "$DMG_PATH" "${notary_args[@]}" --wait
  xcrun stapler staple "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
fi

echo "Created $DMG_PATH"
echo "Version: $VERSION ($BUILD_NUMBER)"
echo "Bundle identifier: $BUNDLE_ID"
if [[ "$UNSIGNED" == "1" ]]; then
  echo "Signing: ad-hoc (local verification only)"
else
  echo "Signing identity: $CODESIGN_IDENTITY"
fi
