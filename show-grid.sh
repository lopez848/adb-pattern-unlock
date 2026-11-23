#!/usr/bin/env bash
# Show the LockPatternView grid WITHOUT touching the screen.
#
# Usage: ./show-grid.sh [--serial <adb-serial>] [--digits 123456]
#
# Read-only: it never sends input events, so it cannot interfere while you
# draw the pattern by hand (mouse in scrcpy, or finger).
#
# It prints, for the on-screen pattern prompt:
#   - the raw LockPatternView bounds (the view includes padding);
#   - the nine dot centers (at 1/6, 3/6, 5/6 of the view);
#   - a phone-keypad diagram mapping digits to pixel coordinates;
#   - with --digits, the exact stroke waypoints for your pattern.
#
# Requirements: the pattern prompt (bouncer) must be visible.
# Note: screenshots of the bouncer come out black (FLAG_SECURE surface);
# coordinates come from the accessibility tree instead.
set -uo pipefail

SERIAL=""
DIGITS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial) SERIAL="$2"; shift 2;;
    --digits) DIGITS="$2"; shift 2;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

ADB=(adb)
[[ -n "$SERIAL" ]] && ADB+=( -s "$SERIAL" )

DUMP=/sdcard/pattern_ui_preview.xml
"${ADB[@]}" shell "uiautomator dump $DUMP >/dev/null 2>&1"
DATA=$("${ADB[@]}" shell cat "$DUMP" 2>/dev/null)
"${ADB[@]}" shell "rm -f $DUMP" >/dev/null 2>&1

BOUNDS=$(echo "$DATA" | grep -o 'resource-id="com.android.systemui:id/lockPatternView"[^>]*' | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1)

if [[ -z "$BOUNDS" ]]; then
  echo "ERROR: lockPatternView not found." >&2
  echo "Open the pattern prompt first (unlock the bouncer or tap a lock-screen notification)." >&2
  exit 1
fi

L=$(echo "$BOUNDS" | sed -E 's/bounds="\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]"/\1/')
T=$(echo "$BOUNDS" | sed -E 's/bounds="\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]"/\2/')
R=$(echo "$BOUNDS" | sed -E 's/bounds="\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]"/\3/')
B=$(echo "$BOUNDS" | sed -E 's/bounds="\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]"/\4/')

# Dot centers sit at 1/6, 3/6, 5/6 of the view (spacing = dimension/3).
OW=$(( (R - L) / 6 ))
OH=$(( (B - T) / 6 ))
CX=$(( (L + R) / 2 ))
COLL=$(( L + OW )); COLR=$(( R - OW ))
ROWT=$(( T + OH ))
ROWB=$(( B - OH ))
CY=$(( (T + B) / 2 ))

echo "LockPatternView bounds: left=$L top=$T right=$R bottom=$B"
echo
echo "Dot centers (phone keypad orientation: 1 top-left, 9 bottom-right):"
printf '  1: %-12s 2: %-12s 3: %-12s\n' "$COLL,$ROWT" "$CX,$ROWT" "$COLR,$ROWT"
printf '  4: %-12s 5: %-12s 6: %-12s\n' "$COLL,$CY"   "$CX,$CY"   "$COLR,$CY"
printf '  7: %-12s 8: %-12s 9: %-12s\n' "$COLL,$ROWB" "$CX,$ROWB" "$COLR,$ROWB"
echo

if [[ -n "$DIGITS" ]]; then
  if ! echo "$DIGITS" | grep -qE '^[1-9]+$'; then
    echo "ERROR: --digits must be digits 1-9" >&2
    exit 1
  fi
  col_of() { case $1 in 1|4|7) echo $COLL;; 2|5|8) echo $CX;; 3|6|9) echo $COLR;; esac; }
  row_of() { case $1 in 1|2|3) echo $ROWT;; 4|5|6) echo $CY;; 7|8|9) echo $ROWB;; esac; }

  echo "Stroke for pattern $DIGITS (waypoints, in order):"
  PREV=""
  FIRST=1
  I=0
  while read -r -n1 D; do
    [[ -z "$D" ]] && continue
    PX=$(col_of "$D"); PY=$(row_of "$D")
    if (( FIRST )); then
      printf '  %-3s DOWN  %s %s   (digit %s)\n' "[$I]" "$PX" "$PY" "$D"
      FIRST=0
    else
      PVX=$(col_of "$PREV"); PVY=$(row_of "$PREV")
      DX=$(( PX - PVX )); DY=$(( PY - PVY ))
      case "$DX,$DY" in
        0,*|*,0) STEP=3;;
        *,*)     STEP=2;;
      esac
      S=1
      while (( S < STEP )); do
        MX=$(( PVX + DX * S / STEP )); MY=$(( PVY + DY * S / STEP ))
        I=$(( I + 1 ))
        printf '  %-3s MOVE  %s %s\n' "[$I]" "$MX" "$MY"
        S=$(( S + 1 ))
      done
      I=$(( I + 1 ))
      printf '  %-3s MOVE  %s %s   (digit %s)\n' "[$I]" "$PX" "$PY" "$D"
    fi
    PREV=$D
    I=$(( I + 1 ))
  done < <(echo "$DIGITS" | grep -o .)
  printf '  %-3s UP    %s %s\n' "[$(( I ))]" "$(col_of "$PREV")" "$(row_of "$PREV")"
fi

echo
echo "No input was sent. The screen was only read via uiautomator dump."
