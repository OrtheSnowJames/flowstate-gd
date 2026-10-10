#!/bin/bash
set -eu

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
python_bin="${PYTHON_BIN:-/tmp/flowstate-matchmaking-venv/bin/python}"
log_file="$(mktemp /tmp/flowstate-rtc-directory.XXXXXX)"
export FLOWSTATE_MATCHMAKING_URL=http://127.0.0.1:18765
export FLOWSTATE_TEST_WEBRTC=1
"$python_bin" -m matchmaking.local_server >"$log_file" 2>&1 &
directory_pid=$!
trap 'kill "$directory_pid" 2>/dev/null || true; wait "$directory_pid" 2>/dev/null || true' EXIT
for ((attempt = 0; attempt < 100; attempt++)); do
    if rg -q 'local matchmaking at' "$log_file"; then
        bash tests/run_match_replication.sh
        exit $?
    fi
    if ! kill -0 "$directory_pid" 2>/dev/null; then
        cat "$log_file"
        exit 1
    fi
    sleep 0.1
done
cat "$log_file"
exit 1
