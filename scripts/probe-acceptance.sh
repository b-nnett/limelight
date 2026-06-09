#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${SPOTLIGHT_INDEX_URL:-http://127.0.0.1:8765}"
RAW_OUTPUT="${SPOTLIGHT_INDEX_RAW_PROBE:-0}"
AUTH_TOKEN="${SPOTLIGHT_INDEX_AUTH_TOKEN:-}"
FAILURES=0

redacted_summary_filter='
  def redact:
    if type == "string" then
      gsub("[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}"; "[redacted-email]"; "i")
      | gsub("\\+?[0-9][0-9 .()/-]{6,}[0-9]"; "[redacted-number]")
    else
      .
    end;
  {
    count,
    providers,
    results: [
      .results[] | {
        source,
        entityType,
        title: (.title | redact),
        subtitle: (.subtitle | redact),
        startAt,
        matchReason: .metadata.matchReason
      }
    ]
  }
'

search() {
  local label="$1"
  local query="$2"
  local source="$3"
  local response provider_status count

  printf '\n== %s ==\n' "$label"
  local curl_args=(-sS -X POST "$BASE_URL/v1/search" -H 'Content-Type: application/json')
  if [[ -n "$AUTH_TOKEN" ]]; then
    curl_args+=(-H "Authorization: Bearer $AUTH_TOKEN")
  fi
  response="$(curl "${curl_args[@]}" -d "{\"query\":\"$query\",\"sources\":[\"$source\"],\"limit\":3}")"

  provider_status="$(jq -r --arg source "$source" '.providers[] | select(.source == $source) | .status // "missing"' <<<"$response")"
  count="$(jq -r '.count // 0' <<<"$response")"

  if [[ "$RAW_OUTPUT" == "1" ]]; then
    jq '{count, providers, results: [.results[] | {source, entityType, title, subtitle, path, url, startAt, metadata}]}' <<<"$response"
  else
    jq "$redacted_summary_filter" <<<"$response"
  fi

  if [[ "$provider_status" != "ok" || "$count" -lt 1 ]]; then
    printf 'FAIL: %s provider=%s count=%s\n' "$label" "$provider_status" "$count" >&2
    FAILURES=$((FAILURES + 1))
  else
    printf 'PASS: %s\n' "$label"
  fi
}

provider_curl_args=(-sS "$BASE_URL/v1/providers")
if [[ -n "$AUTH_TOKEN" ]]; then
  provider_curl_args=(-sS -H "Authorization: Bearer $AUTH_TOKEN" "$BASE_URL/v1/providers")
fi

curl "${provider_curl_args[@]}" |
  jq '{providers: [.providers[] | {source, status, summary, setupHint, checks}]}'

search "passport should resolve photos" "passport" "photos"
search "bennett should resolve pictures" "bennett" "photos"
search "bennett should resolve mail" "bennett" "mail"
search "bennett should resolve messages" "bennett" "messages"
search "bennett should resolve contact card" "bennett" "contacts"
search "bennett should resolve birthday" "bennett" "calendar"
search "bennett should resolve notes" "bennett" "notes"
search "amazon should resolve safari history" "amazon" "safari"

if [[ "$FAILURES" -gt 0 ]]; then
  printf '\n%d acceptance check(s) failed.\n' "$FAILURES" >&2
  exit 1
fi

printf '\nAll acceptance checks passed.\n'
