#!/usr/bin/env bash
# Unlock your own Android phone over ADB.
#
# Usage:
#   ./unlock-phone.sh 123456
#   ./unlock-phone.sh 123456 --serial 192.168.1.55:5555
#
# Digits use phone keypad orientation (1 = top-left, 9 = bottom-right).
#
# What it does, in order:
#   1. If already unlocked, done.
#   2. Opens the pattern prompt (bouncer). The reliable route is tapping a
#      lock-screen notification; plain swipes often open the wallet or shade.
#   3. Detects the LockPatternView grid via uiautomator dump (the prompt is a
#      FLAG_SECURE surface: screenshots come out black, so no image helps).
#   4. Draws the pattern as one stroke with per-dot pauses, in one ADB shell
#      session so the ~5 s doze timeout cannot interrupt it.
#   5. Verifies the lock state and retries, waiting out Android cooldowns.
set -uo pipefail

PATTERN="${1:?Usage: unlock-phone.sh <digits> [--serial <adb-serial>]}"
shift || true
SERIAL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial) SERIAL="$2"; shift 2;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

ADB=(adb)
[[ -n "$SERIAL" ]] && ADB+=( -s "$SERIAL" )

# Validate pattern: digits 1-9, no consecutive repeats.
[[ "$PATTERN" =~ ^[1-9]+$ ]] || { echo "ERROR: pattern must be digits 1-9" >&2; exit 1; }
PREVD=''
while read -r -n1 D; do
  [[ "$D" == "$PREVD" ]] && { echo "ERROR: no consecutive repeated dots" >&2; exit 1; }
  PREVD=$D
done < <(echo "$PATTERN" | grep -o .)

is_locked() {
  local s
  s=$("${ADB[@]}" shell dumpsys window policy 2>/dev/null | grep -E '^      showing=' | head -1)
  [[ "$s" == *showing=true* ]]
}

focus() { "${ADB[@]}" shell dumpsys window 2>/dev/null | grep mCurrentFocus | tail -1; }

# One remote shell that opens the bouncer and draws the pattern.
# Everything runs inside a single adb shell invocation on purpose: Samsung
# enforces a ~5 s user-activity timeout while dozing on battery, and splitting
# the steps across invocations lets the screen sleep mid-flow.
open_and_draw() {
  "${ADB[@]}" shell sh -s <<REMOTE
# --- open the bouncer (up to 6 passes) -------------------------------
for i in 1 2 3 4 5 6; do
  input keyevent KEYCODE_WAKEUP
  cmd statusbar expand-notifications
  sleep 0.6
  F=\$(dumpsys window | grep mCurrentFocus | tail -1)
  if echo "\$F" | grep -q Bouncer; then break; fi
  # Tap the center of a real notification row (NOT the header chips):
  # layout changes over time, so never hardcode a fixed coordinate.
  uiautomator dump /data/local/tmp/nb.xml >/dev/null 2>&1
  ROW=\$(grep -o 'class="com.android.systemui.approw.row.ExpandableNotificationRow\|com.android.systemui.statusbar.ExpandableNotificationRow"[^>]*' /data/local/tmp/nb.xml | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1)
  if [ -n "\$ROW" ]; then
    RX=\$(echo "\$ROW" | sed -E 's/.*\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\].*/\1/')
    RY=\$(echo "\$ROW" | sed -E 's/.*\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\].*/\2/')
    RX2=\$(echo "\$ROW" | sed -E 's/.*\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\].*/\3/')
    RY2=\$(echo "\$ROW" | sed -E 's/.*\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\].*/\4/')
    TCX=\$(( (RX + RX2) / 2 )); TCY=\$(( (RY + RY2) / 2 ))
  else
    TCX=638; TCY=637            # fallback: first notification row, 1440x3120
  fi
  input tap \$TCX \$TCY
  sleep 0.8
  input keyevent KEYCODE_WAKEUP
  F=\$(dumpsys window | grep mCurrentFocus | tail -1)
  if echo "\$F" | grep -q Bouncer; then break; fi
done

# --- detect the pattern grid (mandatory; no fixed fallback) ------------
# Grid coordinates differ between devices and orientations; reusing another
# phone's numbers silently draws the wrong pattern and burns attempts.
D=\$(uiautomator dump /data/local/tmp/pui.xml >/dev/null 2>&1; cat /data/local/tmp/pui.xml 2>/dev/null)
B=\$(echo "\$D" | grep -o 'resource-id="com.android.systemui:id/lockPatternView"[^>]*' | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1)
if [ -z "\$B" ]; then
  echo "ERROR: lockPatternView not found; the pattern prompt is not open" >&2
  exit 3
fi
L=\$(echo "\$B" | sed -E 's/.*\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\].*/\1/')
T=\$(echo "\$B" | sed -E 's/.*\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\].*/\2/')
R=\$(echo "\$B" | sed -E 's/.*\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\].*/\3/')
BO=\$(echo "\$B" | sed -E 's/.*\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\].*/\4/')
CX=\$(( (L + R) / 2 )); CY=\$(( (T + BO) / 2 ))
# Dot centers sit at 1/6, 3/6 and 5/6 of the view (spacing = dimension/3).
OW=\$(( (R - L) / 6 )); OH=\$(( (BO - T) / 6 ))
COLL=\$(( L + OW )); COLR=\$(( R - OW ))
ROWT=\$(( T + OH )); ROWB=\$(( BO - OH ))

# --- draw the pattern (phone keypad orientation) ----------------------
col_of() { case \$1 in 1|4|7) echo \$COLL;; 2|5|8) echo \$CX;; 3|6|9) echo \$COLR;; esac; }
row_of() { case \$1 in 1|2|3) echo \$ROWT;; 4|5|6) echo \$CY;; 7|8|9) echo \$ROWB;; esac; }

POINTS=()
LAST=""
PREV=""
for D2 in \$(echo "$PATTERN" | grep -o .); do
  PX=\$(col_of \$D2); PY=\$(row_of \$D2)
  if [ -n "\$PREV" ]; then
    PVX=\$(col_of \$PREV); PVY=\$(row_of \$PREV)
    DX=\$(( PX - PVX )); DY=\$(( PY - PVY ))
    case "\$DX,\$DY" in
      0,*|*,0) STEP=3;;            # orthogonal: pass through middles
      *,*)    STEP=2;;             # diagonal
    esac
    S=1
    while [ \$S -lt \$STEP ]; do
      MX=\$(( PVX + DX * S / STEP )); MY=\$(( PVY + DY * S / STEP ))
      POINTS+=( "\$MX \$MY" )
      LAST="\$MX \$MY"
      S=\$(( S + 1 ))
    done
  fi
  POINTS+=( "\$PX \$PY" )
  LAST="\$PX \$PY"
  PREV=\$D2
done

input keyevent KEYCODE_WAKEUP
FIRST=1
for P in "\${POINTS[@]}"; do
  X=\${P% *}; Y=\${P#* }
  if [ \$FIRST -eq 1 ]; then
    input motionevent DOWN \$X \$Y
    for k in 1 2 3 4; do input motionevent MOVE \$X \$Y; done
    FIRST=0
  else
    for k in 1 2 3; do input motionevent MOVE \$X \$Y; done
  fi
  sleep 0.15
done
input motionevent UP \${LAST% *} \${LAST#* }
REMOTE
}

wait_cooldown() {
  # Android says: "Demasiados intentos... dentro de N segundos". Wait it out.
  local remaining
  remaining=$("${ADB[@]}" shell 'uiautomator dump /data/local/tmp/pc.xml >/dev/null 2>&1; grep -oE "dentro de [0-9]+ segundos" /data/local/tmp/pc.xml 2>/dev/null' | grep -oE '[0-9]+' | tail -1)
  if [[ -n "$remaining" ]]; then
    echo "Cooldown: waiting $((remaining + 5))s"
    sleep $(( remaining + 5 ))
  else
    sleep 30
  fi
}

UNLOCKED=0
if ! is_locked; then
  UNLOCKED=1
  echo "Already unlocked."
fi

for attempt in 1 2 3; do
  (( UNLOCKED )) && break
  echo "Attempt $attempt..."
  open_and_draw
  sleep 1.2
  if ! is_locked; then
    UNLOCKED=1
    echo "Unlocked."
  else
    wait_cooldown
  fi
done

if (( UNLOCKED )); then
  "${ADB[@]}" shell 'input keyevent KEYCODE_WAKEUP; sleep 0.5; input keyevent KEYCODE_HOME'
  echo "Done: device unlocked, back to launcher."
else
  echo "FAILED: still locked after 3 attempts. Check the pattern orientation (phone keypad, 1 top-left / 9 bottom-right) and any cooldown."
  exit 1
fi
