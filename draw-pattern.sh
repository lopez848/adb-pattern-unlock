#!/usr/bin/env bash
# Draw an unlock pattern on the Android lock screen via ADB.
#
# Usage: ./draw-pattern.sh <digits> [left top right bottom]
#   <digits>          Pattern digits in phone-keypad orientation:
#                     1 2 3
#                     4 5 6
#                     7 8 9
#                     (9 = bottom-right, 1 = top-left). For "123456" pass 123456.
#   left top right bottom  Optional grid bounds; auto-detected when omitted.
#
# Requirements: adb connected, pattern prompt (bouncer) visible on screen.
set -euo pipefail

DIGITS="${1:?Usage: draw-pattern.sh <digits> [left top right bottom]}"
L=${2:-}
T=${3:-}
R=${4:-}
B=${5:-}

if [[ -z "$L" || -z "$T" || -z "$R" || -z "$B" ]]; then
  read -r L T R B < <("$(dirname "$0")/detect-pattern-grid.sh")
fi

CX=$(( (L + R) / 2 ))
CY=$(( (T + B) / 2 ))
CELL=$(( R - L ))
if (( CELL > B - T )); then CELL=$(( B - T )); fi
CELL=$(( CELL / 2 ))

# Column/row centers for each digit (phone keypad orientation).
col_of() { case $1 in 1|4|7) echo $(( CX - CELL ));; 2|5|8) echo $CX;; 3|6|9) echo $(( CX + CELL ));; esac; }
row_of() { case $1 in 1|2|3) echo $(( CY - CELL ));; 4|5|6) echo $CY;; 7|8|9) echo $(( CY + CELL ));; esac; }

# Validate digits.
if ! echo "$DIGITS" | grep -qE '^[1-9]+$'; then
  echo "ERROR: digits must be 1-9" >&2
  exit 1
fi
if echo "$DIGITS" | grep -qE '(.)\1'; then
  echo "ERROR: pattern cannot repeat the same dot consecutively" >&2
  exit 1
fi

# Build the point sequence, including intermediate dots skipped in a straight line
# (Android registers every dot the path passes through).
POINTS=()
PREV=""
for D in $(echo "$DIGITS" | grep -o .); do
  PX=$(col_of "$D"); PY=$(row_of "$D")
  if [[ -n "$PREV" ]]; then
    PVX=$(col_of "$PREV"); PVY=$(row_of "$PREV")
    DX=$(( PX - PVX )); DY=$(( PY - PVY ))
    GCD=$(( $(echo "$DX" | sed 's/-//') ))
    G2=$(( $(echo "$DY" | sed 's/-//') ))
    while (( G2 )); do G=$G2; G2=$(( G % G2 )); G2=$G; done 2>/dev/null || G=1
    GCD=$(( G ? G : 1 ))
    STEPS=$(( GCD ? GCD : 1 ))
    for (( S=1; S<STEPS; S++ )); do
      MX=$(( PVX + DX * S / STEPS ))
      MY=$(( PVY + DY * S / STEPS ))
      POINTS+=("$MX $MY")
    done
  fi
  POINTS+=("$PX $PY")
  PREV=$D
done

# Wake the screen first.
adb shell input keyevent KEYCODE_WAKEUP
sleep 0.5

FIRST=1
for P in "${POINTS[@]}"; do
  X=${P% *}; Y=${P#* }
  if (( FIRST )); then
    adb shell input motionevent DOWN "$X" "$Y"
    for i in 1 2 3 4; do adb shell input motionevent MOVE "$X" "$Y"; done
    FIRST=0
  else
    for i in 1 2 3; do adb shell input motionevent MOVE "$X" "$Y"; done
  fi
  sleep 0.15
done
LAST=${POINTS[-1]}
adb shell input motionevent UP "${LAST% *}" "${LAST#* }"

echo "Pattern drawn: $DIGITS"
