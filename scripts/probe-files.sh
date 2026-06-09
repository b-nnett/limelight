#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${SPOTLIGHT_INDEX_URL:-http://127.0.0.1:8765}"
AUTH_TOKEN="${SPOTLIGHT_INDEX_AUTH_TOKEN:-}"
AUTH_TOKEN_FILE="${SPOTLIGHT_INDEX_AUTH_TOKEN_FILE:-$HOME/Library/Application Support/Limelight/auth-token}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$ROOT_DIR/File Search Fixtures"

if [[ -z "$AUTH_TOKEN" && -r "$AUTH_TOKEN_FILE" ]]; then
  AUTH_TOKEN="$(tr -d '\r\n' < "$AUTH_TOKEN_FILE")"
fi

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

filename_token="filename-passport-$(uuidgen | tr '[:upper:]' '[:lower:]')"
content_token="content-passport-$(uuidgen | tr '[:upper:]' '[:lower:]')"
filename_file="$WORK_DIR/${filename_token}.txt"
content_file="$WORK_DIR/content-only.txt"

printf 'Filename match fixture.\n' > "$filename_file"
printf 'Body fixture containing %s only in content.\n' "$content_token" > "$content_file"

mdimport "$WORK_DIR" >/dev/null 2>&1 || true

search() {
  local query="$1"
  local curl_args=(-sS -X POST "$BASE_URL/v1/search" -H 'Content-Type: application/json')
  if [[ -n "$AUTH_TOKEN" ]]; then
    curl_args+=(-H "Authorization: Bearer $AUTH_TOKEN")
  fi
  curl "${curl_args[@]}" -d "{\"query\":\"$query\",\"sources\":[\"files\"],\"onlyIn\":[\"$WORK_DIR\"],\"limit\":5}"
}

wait_for_match() {
  local query="$1"
  local expected_path="$2"
  local expected_reason="$3"
  local response

  for _ in {1..12}; do
    response="$(search "$query")"
    if jq -e --arg path "$expected_path" --arg reason "$expected_reason" '
      .results[] | select(.path == $path and .metadata.matchReason == $reason)
    ' >/dev/null <<<"$response"; then
      jq '{count, results: [.results[] | {title, path, matchReason: .metadata.matchReason}]}' <<<"$response"
      return 0
    fi
    sleep 1
    mdimport "$WORK_DIR" >/dev/null 2>&1 || true
  done

  jq '{count, providers, results: [.results[] | {title, path, matchReason: .metadata.matchReason}]}' <<<"$response" >&2
  printf 'FAIL: expected %s with matchReason=%s for query %s\n' "$expected_path" "$expected_reason" "$query" >&2
  return 1
}

printf '== filename match ==\n'
wait_for_match "$filename_token" "$filename_file" "filename"

printf '\n== content match ==\n'
wait_for_match "$content_token" "$content_file" "content"

printf '\nFile search acceptance checks passed.\n'
