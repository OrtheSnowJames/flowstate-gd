#!/bin/bash
set -euo pipefail

if [[ "${1:-}" == "--help" || "$#" -gt 1 ]]; then
    printf 'Usage: bash matchmaking/test_requests.sh [URL]\n'
    printf 'Defaults to FLOWSTATE_MATCHMAKING_URL or connect_to_url.txt\n'
    printf 'Requires curl and jq and creates one temporary in-game room\n'
    exit 0
fi

for tool in curl jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Missing dependency: %s\n' "$tool" >&2
        exit 1
    fi
done

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
url="${1:-${FLOWSTATE_MATCHMAKING_URL:-}}"
if [[ -z "$url" ]]; then
    if [[ ! -f "$project_dir/connect_to_url.txt" ]]; then
        printf 'Provide a URL or create connect_to_url.txt\n' >&2
        exit 1
    fi
    url="$(<"$project_dir/connect_to_url.txt")"
fi
url="$(printf '%s' "$url" | jq -Rrs 'gsub("^\\s+|\\s+$"; "") | sub("/+$"; "")')"
case "$url" in
    https://*|http://127.0.0.1:*|http://localhost:*) ;;
    *) printf 'Use HTTPS or a localhost HTTP URL\n' >&2; exit 1 ;;
esac

umask 077
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/flowstate-lambda-test.XXXXXX")"
body_file="$tmp_dir/body.json"
room_code=""
host_token=""
http_status=""

cleanup() {
    local exit_status=$?
    if [[ -n "$room_code" && -n "$host_token" ]]; then
        local cleanup_status
        cleanup_status="$(curl --silent --show-error --connect-timeout 5 --max-time 10 \
            --request DELETE --header "Authorization: Bearer $host_token" \
            --output /dev/null --write-out '%{http_code}' "$url/rooms/$room_code")" || cleanup_status=000
        if [[ "$cleanup_status" != 200 && "$cleanup_status" != 404 ]]; then
            printf 'Warning: cleanup returned HTTP %s for room %s\n' "$cleanup_status" "$room_code" >&2
            exit_status=1
        fi
    fi
    rm -rf "$tmp_dir"
    exit "$exit_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

request() {
    local method="$1" path="$2" data="${3:-}" token="${4:-}"
    local args=(--silent --show-error --connect-timeout 5 --max-time 15
        --request "$method" --header 'Content-Type: application/json'
        --output "$body_file" --write-out '%{http_code}')
    [[ -z "$data" ]] || args+=(--data "$data")
    [[ -z "$token" ]] || args+=(--header "Authorization: Bearer $token")
    printf '\n%s %s\n' "$method" "$path"
    http_status="$(curl "${args[@]}" "$url$path")"
    printf 'HTTP %s\n' "$http_status"
    if ! jq -e 'type == "object"' "$body_file" >/dev/null 2>&1; then
        printf 'FAIL expected a JSON object from Lambda\n' >&2
        head -c 2000 "$body_file" >&2
        printf '\nCheck the Lambda handler and CloudWatch logs\n' >&2
        exit 1
    fi
    jq 'del(.host_token)' "$body_file"
}

expect() {
    local status="$1" assertion="$2" label="$3"
    if [[ "$http_status" != "$status" ]] || ! jq -e "$assertion" "$body_file" >/dev/null; then
        printf 'FAIL %s (expected HTTP %s)\n' "$label" "$status" >&2
        exit 1
    fi
    printf 'PASS %s\n' "$label"
}

printf 'Testing %s\n' "$url"
request POST /rooms '{"port":0}'
expect 400 '.error | type == "string"' 'invalid port rejected'

# keep the test room out of quick play
request POST /rooms '{"port":7654,"players":1,"state":"in_game","protocol":1}'
room_code="$(jq -r '.room_code // empty' "$body_file")"
host_token="$(jq -r '.host_token // empty' "$body_file")"
expect 201 '.room_code | test("^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$")' 'room registered'
expect 201 '(.host_token | type == "string" and length > 0) and .max_players == 20' 'private host token returned'

request GET "/rooms/$room_code"
expect 200 '.state == "in_game" and .players == 1 and (has("host_token") | not)' 'code resolves without exposing token'

request POST "/rooms/$room_code/heartbeat" '{"players":2}' wrong-token
expect 401 '.error | type == "string"' 'unauthorized heartbeat rejected'
request DELETE "/rooms/$room_code" '' wrong-token
expect 401 '.error | type == "string"' 'unauthorized deletion rejected'

request POST "/rooms/$room_code/heartbeat" '{"players":2,"state":"in_game"}' "$host_token"
expect 200 '.ok == true' 'heartbeat accepted'
request GET "/rooms/$room_code"
expect 200 '.players == 2 and .state == "in_game"' 'occupancy updated'

request POST /matchmaking '{"protocol":1}'
if [[ "$http_status" == 404 ]]; then
    expect 404 '.error == "No joinable matches found"' 'matchmaking reports no available rooms'
else
    expect 200 '.state == "lobby" and .players < 20 and .protocol == 1 and (has("host_token") | not)' 'matchmaking returns an available lobby'
    if [[ "$(jq -r '.room_code' "$body_file")" == "$room_code" ]]; then
        printf 'FAIL matchmaking returned the in-game test room\n' >&2
        exit 1
    fi
fi

request POST "/rooms/$room_code/heartbeat" '{"players":20}' "$host_token"
expect 200 '.ok == true' 'full occupancy accepted'
request GET "/rooms/$room_code"
expect 409 '.error == "Room is full"' 'full room rejected'

request DELETE "/rooms/$room_code" '' "$host_token"
expect 200 '.ok == true' 'test room deleted'
host_token=""
request GET "/rooms/$room_code"
expect 404 '.error == "Room not found or expired"' 'deleted code no longer resolves'
printf '\nPASS all Lambda request tests\n'
