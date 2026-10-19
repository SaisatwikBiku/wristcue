#!/bin/bash
# Measures how much CPU time one process uses over a window.
#
# Usage: scripts/cpu-seconds.sh <process name> [seconds, default 60]
# Example: scripts/cpu-seconds.sh WristCueWatch 60
#
# Simulator apps run as ordinary macOS processes, so `ps` sees them. The result
# is Mac CPU time, which says how the two sync modes compare with each other,
# not what a real Apple Watch would spend.
set -euo pipefail

name=${1:?usage: scripts/cpu-seconds.sh <process name> [seconds]}
window=${2:-60}

pid=$(pgrep -n -x "$name") || { echo "No running process named $name" >&2; exit 1; }

# `ps -o time=` prints cumulative CPU time as [hours:]minutes:seconds.
cpu_seconds() {
    ps -o time= -p "$pid" | awk -F: '{ if (NF == 3) print $1 * 3600 + $2 * 60 + $3; else print $1 * 60 + $2 }'
}

start=$(cpu_seconds)
sleep "$window"
end=$(cpu_seconds)

awk -v name="$name" -v pid="$pid" -v s="$start" -v e="$end" -v w="$window" 'BEGIN {
    used = e - s
    printf "%s (pid %s): %.2f CPU seconds in %d s, %.2f%% of one core\n", name, pid, used, w, used / w * 100
}'
