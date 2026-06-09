#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="${1:-Codex++ Local Signing}"
KEYCHAIN="${SPOTLIGHT_INDEX_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$IDENTITY_NAME\"" >/dev/null; then
  echo "Code signing identity already exists: $IDENTITY_NAME"
  exit 0
fi

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

cat > "$tmpdir/openssl.cnf" <<CONF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = codesign_ext

[ dn ]
CN = $IDENTITY_NAME

[ codesign_ext ]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = critical, CA:false
CONF

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$tmpdir/signing.key" \
  -out "$tmpdir/signing.crt" \
  -days 3650 \
  -config "$tmpdir/openssl.cnf" >/dev/null 2>&1

openssl pkcs12 -export \
  -inkey "$tmpdir/signing.key" \
  -in "$tmpdir/signing.crt" \
  -out "$tmpdir/signing.p12" \
  -passout pass: >/dev/null 2>&1

security import "$tmpdir/signing.p12" \
  -k "$KEYCHAIN" \
  -P "" \
  -T /usr/bin/codesign >/dev/null

security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "" \
  "$KEYCHAIN" >/dev/null 2>&1 || true

if security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$IDENTITY_NAME\"" >/dev/null; then
  echo "Created code signing identity: $IDENTITY_NAME"
else
  echo "warning: imported $IDENTITY_NAME, but it is not listed as a valid code signing identity yet" >&2
  exit 1
fi
