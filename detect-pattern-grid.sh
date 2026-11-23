#!/usr/bin/env bash
# Detect the LockPatternView bounds on the Android lock screen (bouncer).
# Requires: adb, USB debugging enabled, bouncer (pattern prompt) visible.
set -euo pipefail

DUMP=${1:-/sdcard/pattern_ui.xml}

adb shell uiautomator dump "$DUMP" >/dev/null 2>&1
BOUNDS=$(adb shell cat "$DUMP" | grep -o 'resource-id="com.android.systemui:id/lockPatternView"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1)

if [[ -z "$BOUNDS" ]]; then
  echo "ERROR: lockPatternView not found. Is the pattern prompt (bouncer) on screen?" >&2
  exit 1
fi

echo "$BOUNDS" | sed -E 's/bounds="\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]"/\1 \2 \3 \4/'
