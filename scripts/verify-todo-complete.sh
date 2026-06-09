#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${SPOTLIGHT_INDEX_URL:-http://127.0.0.1:8765}"
APP_PATH="${SPOTLIGHT_INDEX_APP_DIR:-$HOME/Applications/Limelight.app}"

curl_args=(-sS -H 'X-Origin: verify-todo-complete')

echo "== app identity =="
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | sed -n '1,22p'

echo
echo "== provider readiness =="
providers="$(curl "${curl_args[@]}" "$BASE_URL/v1/providers")"
jq '{providers: [.providers[] | {source,status,summary,setupHint}]}' <<<"$providers"

missing_protected="$(
  jq -r '
    [.providers[] | select((.source == "mail" or .source == "messages" or .source == "notes" or .source == "safari") and .status != "ready") | .source]
    | join(",")
  ' <<<"$providers"
)"

if [[ -n "$missing_protected" ]]; then
  echo
  echo "Full Disk Access is still required for: $missing_protected" >&2
  echo "Grant Full Disk Access to: $APP_PATH" >&2
  echo "Then restart the app and rerun: scripts/verify-todo-complete.sh" >&2
  exit 1
fi

echo
echo "== acceptance matrix =="
scripts/probe-acceptance.sh

echo
echo "== file matching =="
scripts/probe-files.sh

echo
echo "== photos thumbnail =="
uuid="$(
  curl "${curl_args[@]}" -sS -X POST "$BASE_URL/v1/search" \
    -H 'Content-Type: application/json' \
    -d '{"query":"passport","sources":["photos"],"types":["image"],"limit":1}' |
    jq -r '.results[0].metadata.uuid // empty'
)"

if [[ -z "$uuid" ]]; then
  echo "No Photos UUID resolved for passport." >&2
  exit 1
fi

headers="$(mktemp)"
body="$(mktemp)"
cleanup() {
  rm -f "$headers" "$body"
}
trap cleanup EXIT

curl "${curl_args[@]}" -sS -D "$headers" -o "$body" "$BASE_URL/v1/photos/thumbnail?id=$uuid"
if ! grep -q '^HTTP/1.1 200 OK' "$headers"; then
  cat "$headers" >&2
  exit 1
fi
if [[ "$(wc -c < "$body")" -le 0 ]]; then
  echo "Thumbnail response body is empty." >&2
  exit 1
fi
head -5 "$headers"
wc -c "$body"

echo
echo "All TODO completion checks passed."
