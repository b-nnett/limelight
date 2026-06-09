#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${SPOTLIGHT_INDEX_URL:-http://127.0.0.1:8765}"
OUTPUT="${SPOTLIGHT_INDEX_CAPABILITY_OUTPUT:-docs/CAPABILITY_MATRIX.md}"
AUTH_TOKEN="${SPOTLIGHT_INDEX_AUTH_TOKEN:-}"
AUTH_TOKEN_FILE="${SPOTLIGHT_INDEX_AUTH_TOKEN_FILE:-$HOME/Library/Application Support/Limelight/auth-token}"

if [[ -z "$AUTH_TOKEN" && -r "$AUTH_TOKEN_FILE" ]]; then
  AUTH_TOKEN="$(tr -d '\r\n' < "$AUTH_TOKEN_FILE")"
fi

mkdir -p "$(dirname "$OUTPUT")"

curl_args=(-sS "$BASE_URL/v1/capabilities")
if [[ -n "$AUTH_TOKEN" ]]; then
  curl_args=(-sS -H "Authorization: Bearer $AUTH_TOKEN" "$BASE_URL/v1/capabilities")
fi

response="$(curl "${curl_args[@]}")"
if ! jq -e '.sources | type == "array"' >/dev/null <<<"$response"; then
  printf 'error: %s/v1/capabilities did not return a capability response\n' "$BASE_URL" >&2
  exit 1
fi

{
  printf '# Limelight Capability Matrix\n\n'
  printf 'Generated from `%s/v1/capabilities`.\n\n' "$BASE_URL"
  printf '| Source | Live Status | Permission | Entity Types | Supported Fields | Limitations |\n'
  printf '| --- | --- | --- | --- | --- | --- |\n'
  jq -r '
    .sources[]
    | [
        .source,
        .liveStatus,
        .permissionRequired,
        (.entityTypes | join(", ")),
        (.supportedFields | join(", ")),
        (.limitations | join("; "))
      ]
    | @tsv
  ' <<<"$response" | while IFS=$'\t' read -r source status permission entities fields limitations; do
    printf '| %s | %s | %s | %s | %s | %s |\n' \
      "$source" "$status" "$permission" "$entities" "$fields" "$limitations"
  done
} > "$OUTPUT"

printf 'Wrote %s\n' "$OUTPUT"
