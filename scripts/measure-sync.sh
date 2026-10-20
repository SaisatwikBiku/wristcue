#!/bin/bash
# Runs the M5 sync measurements in both modes, unattended, and saves the raw
# output to docs/measurements/.
#
# Usage, from the repository root, with a paired iPhone and Watch Simulator
# booted and Debug builds of both apps installed:
#
#   scripts/measure-sync.sh
#
# Optional: PHONE=<udid> WATCH=<udid> scripts/measure-sync.sh
#
# Per mode, about 2 to 2.5 minutes: the iPhone app starts Glance by itself, the
# Watch app measures 60 s of steady playback (with Watch CPU measured by
# cpu-seconds.sh over 55 s of that window), a scripted crown turn and 40 command
# round trips, then both apps are stopped.
set -euo pipefail

PHONE=${PHONE:-$(xcrun simctl list devices booted | grep -m1 "iPhone" | grep -oE '[0-9A-F-]{36}' || true)}
WATCH=${WATCH:-$(xcrun simctl list devices booted | grep -m1 "Apple Watch" | grep -oE '[0-9A-F-]{36}' || true)}
[ -n "$PHONE" ] || { echo "No booted iPhone Simulator" >&2; exit 1; }
[ -n "$WATCH" ] || { echo "No booted Apple Watch Simulator" >&2; exit 1; }

PHONE_APP=info.satwik.wristcue
WATCH_APP=info.satwik.wristcue.watchkitapp
OUT=docs/measurements
mkdir -p "$OUT"

# Waits up to $3 seconds for $2 to appear in file $1.
wait_for() {
    local file=$1 pattern=$2 limit=$3 waited=0
    until grep -q "$pattern" "$file" 2>/dev/null; do
        if [ "$waited" -ge "$limit" ]; then
            echo "Timed out after ${limit}s waiting for $pattern in $file" >&2
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
}

stop_apps() {
    xcrun simctl terminate "$PHONE" "$PHONE_APP" 2>/dev/null || true
    xcrun simctl terminate "$WATCH" "$WATCH_APP" 2>/dev/null || true
    # The console sessions normally end with their app; this catches stragglers.
    pkill -f "simctl launch --console $PHONE" 2>/dev/null || true
    pkill -f "simctl launch --console $WATCH" 2>/dev/null || true
}
trap stop_apps EXIT

for MODE in optimized naive; do
    PHONE_LOG="$OUT/sync-$MODE-iphone.log"
    WATCH_LOG="$OUT/sync-$MODE-watch.log"
    CPU_LOG="$OUT/sync-$MODE-cpu.log"
    : > "$PHONE_LOG"; : > "$WATCH_LOG"; : > "$CPU_LOG"

    echo "== $MODE: starting"
    stop_apps
    sleep 2

    xcrun simctl launch --console "$PHONE" "$PHONE_APP" \
        -WristCueSyncMode "$MODE" -WristCueAutoplay glance -WristCueAutoMeasure YES \
        2>/dev/null | grep --line-buffered WRISTCUE > "$PHONE_LOG" &
    PHONE_CONSOLE=$!
    sleep 3
    xcrun simctl launch --console "$WATCH" "$WATCH_APP" \
        -WristCueSyncMode "$MODE" -WristCueAutoMeasure YES \
        2>/dev/null | grep --line-buffered WRISTCUE > "$WATCH_LOG" &
    WATCH_CONSOLE=$!

    wait_for "$WATCH_LOG" "WRISTCUE_STEADY_BEGIN" 90
    echo "== $MODE: steady playback, measuring Watch CPU"
    scripts/cpu-seconds.sh WristCueWatch 55 | tee "$CPU_LOG"

    echo "== $MODE: crown turn and round trips"
    wait_for "$WATCH_LOG" "WRISTCUE_DONE" 240

    stop_apps
    wait "$PHONE_CONSOLE" "$WATCH_CONSOLE" 2>/dev/null || true

    echo "== $MODE: results"
    grep -hE "WRISTCUE_(STEADY |CROWN|RTT_END|RTT_TRAFFIC|ERROR)" "$PHONE_LOG" "$WATCH_LOG" || true
    cat "$CPU_LOG"
done

echo "Raw logs: $OUT/sync-*.log"
