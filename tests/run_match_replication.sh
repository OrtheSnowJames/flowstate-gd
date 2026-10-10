#!/bin/bash
set -eu

godot_bin="${GODOT_BIN:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
log_dir="$(mktemp -d /tmp/flowstate-replication.XXXXXX)"
pids=()

cleanup() {
    for pid in "${pids[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
}
trap cleanup EXIT

launch() {
    "$godot_bin" --headless --path "$project_dir" --log-file "$log_dir/$1.godot.log" \
        res://tests/match_replication.tscn -- "--test=$1" >"$log_dir/$1.log" 2>&1 &
    pids+=("$!")
}

wait_for() {
    for ((attempt = 0; attempt < 400; attempt++)); do
        if rg -q "$1" "$log_dir/host.log"; then
            return
        fi
        if ! kill -0 "${pids[0]}" 2>/dev/null; then
            cat "$log_dir/host.log"
            return 1
        fi
        sleep 0.1
    done
    cat "$log_dir/host.log"
    return 1
}

launch host
if [[ "${FLOWSTATE_TEST_WEBRTC:-0}" == 1 ]]; then
    wait_for RTC_HOST_READY
    export FLOWSTATE_TEST_CODE="$(sed -n 's/^RTC_HOST_READY //p' "$log_dir/host.log" | head -1)"
else
    wait_for 'hosting on port'
fi
launch first
launch second
wait_for READY_FOR_SPECTATOR
launch spectator

result=0
for pid in "${pids[@]}"; do
    wait "$pid" || result=1
done
for role in host first second spectator; do
    rg 'PASS|FAIL|SCRIPT ERROR|ERROR:' "$log_dir/$role.log" || true
    if rg 'SCRIPT ERROR|ERROR:' "$log_dir/$role.log" | rg -v 'Tree3D'; then
        result=1
    fi
done
printf 'logs: %s\n' "$log_dir"
exit "$result"
