#!/bin/bash
set -eu

godot_bin="${GODOT_BIN:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
logs="$(mktemp -d /tmp/flowstate-vr-replication.XXXXXX)"
pids=()

cleanup() {
    for pid in "${pids[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
}
trap cleanup EXIT

launch() {
    "$godot_bin" --headless --xr-mode off --path "$project_dir" --log-file "$logs/$1.godot.log" \
        res://tests/vr_replication.tscn -- "--test=$1" >"$logs/$1.log" 2>&1 &
    pids+=("$!")
}

wait_for() {
    for ((attempt = 0; attempt < 450; attempt++)); do
        if rg -q "$1" "$logs/host.log"; then
            return
        fi
        if ! kill -0 "${pids[0]}" 2>/dev/null; then
            cat "$logs/host.log"
            return 1
        fi
        sleep 0.1
    done
    cat "$logs/host.log"
    return 1
}

launch host
wait_for 'hosting on port'
launch client
wait_for READY_FOR_SPECTATOR
launch spectator
result=0
for pid in "${pids[@]}"; do
    wait "$pid" || result=1
done
for role in host client spectator; do
    rg 'PASS|FAIL|SCRIPT ERROR' "$logs/$role.log" || true
    if ! rg -q "PASS vr replication $role" "$logs/$role.log" || rg -q 'FAIL|SCRIPT ERROR' "$logs/$role.log"; then
        result=1
    fi
done
printf 'logs: %s\n' "$logs"
exit "$result"
