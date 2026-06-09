#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${SPOTLIGHT_INDEX_URL:-http://127.0.0.1:8765}"
OUTPUT="${SPOTLIGHT_INDEX_CAPABILITY_OUTPUT:-docs/CAPABILITY_MATRIX.md}"

mkdir -p "$(dirname "$OUTPUT")"

curl_args=(-sS -H 'X-Origin: generate-capability-matrix' "$BASE_URL/v1/capabilities")

response="$(curl "${curl_args[@]}")"
if ! jq -e '.sources | type == "array"' >/dev/null <<<"$response"; then
  printf 'error: %s/v1/capabilities did not return a capability response\n' "$BASE_URL" >&2
  exit 1
fi

{
  printf '# Limelight Capability Matrix\n\n'
  printf 'Generated from `%s/v1/capabilities` for the currently running local service.\n\n' "$BASE_URL"
  printf 'Readiness is runtime-dependent: `ready`, `partial`, `needs_permission`, and `missing` reflect this machine, user account, app permissions, local data stores, and signing/entitlement state. They are not universal product-readiness claims.\n\n'
  printf '| Source | Local Runtime Status | Permission | Entity Types | Supported Fields | Limitations |\n'
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
