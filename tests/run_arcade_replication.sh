#!/bin/bash
set -eu
godot_bin="${GODOT_BIN:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
logs="$(mktemp -d /tmp/flowstate-arcade.XXXXXX)"
pids=()
trap 'for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done' EXIT
"$godot_bin" --headless --path "$project_dir" --log-file "$logs/host.godot.log" res://tests/arcade_replication.tscn >"$logs/host.log" 2>&1 &
pids+=("$!")
sleep 1
"$godot_bin" --headless --path "$project_dir" --log-file "$logs/client.godot.log" res://tests/arcade_replication.tscn -- --client >"$logs/client.log" 2>&1 &
pids+=("$!")
result=0
for pid in "${pids[@]}"; do wait "$pid" || result=1; done
for role in host client; do
    rg 'PASS|FAIL|SCRIPT ERROR' "$logs/$role.log" || true
    if ! rg -q "PASS arcade replication $role" "$logs/$role.log" || rg -q 'FAIL|SCRIPT ERROR' "$logs/$role.log"; then result=1; fi
done
printf 'logs: %s\n' "$logs"
exit "$result"
