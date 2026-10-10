#!/bin/bash
set -eu

godot_bin="${GODOT_BIN:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
python_bin="${PYTHON_BIN:-/tmp/flowstate-matchmaking-venv/bin/python}"
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
log_dir="$(mktemp -d /tmp/flowstate-black-timeout.XXXXXX)"
pids=()
cleanup() {
    for pid in "${pids[@]}"; do
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
}
trap cleanup EXIT
cd "$project_dir"
export FLOWSTATE_MATCHMAKING_URL=http://127.0.0.1:18765
"$python_bin" -m matchmaking.local_server >"$log_dir/directory.log" 2>&1 &
pids+=("$!")

wait_for() {
    for ((attempt = 0; attempt < 300; attempt++)); do
        if rg -q "$1" "$log_dir/$2.log"; then return; fi
        if ! kill -0 "$3" 2>/dev/null; then
            cat "$log_dir/$2.log"
            return 1
        fi
        sleep 0.1
    done
    cat "$log_dir/$2.log"
    return 1
}

launch() {
    "$godot_bin" --headless --path "$project_dir" res://tests/black_screen_timeout.tscn \
        -- "--timeout-role=$1" >"$log_dir/$1.log" 2>&1 &
    pids+=("$!")
}

wait_for 'local matchmaking at' directory "${pids[0]}"
launch host
wait_for TIMEOUT_HOST_READY host "${pids[1]}"
export FLOWSTATE_TEST_CODE="$(sed -n 's/^TIMEOUT_HOST_READY //p' "$log_dir/host.log" | head -1)"
launch stalled
launch observer
result=0
for pid in "${pids[@]:1}"; do
    wait "$pid" || result=1
done
for role in host stalled observer; do
    rg 'PASS|FAIL|SCRIPT ERROR|ERROR:' "$log_dir/$role.log" || true
    if rg 'SCRIPT ERROR|ERROR:' "$log_dir/$role.log" | rg -v 'Tree3D'; then result=1; fi
done
printf 'logs: %s\n' "$log_dir"
exit "$result"
