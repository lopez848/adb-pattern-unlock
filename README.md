# adb-pattern-unlock

Unlock your own Android phone from a computer using ADB when the pattern prompt
is hard to reach: the pattern surface blocks screenshots, a screen timeout of a
few seconds kills every attempt, and a swipe from the lock clock sometimes opens
the wallet instead of the pattern.

This project automates the whole flow with plain `adb shell` commands. You must
already know your pattern; nothing here bypasses the lock.

## What it does

1. Wakes the screen and opens the notification shade (`cmd statusbar
   expand-notifications`).
2. Taps a lock-screen notification, which forces Android to show the pattern
   prompt (the "bouncer"). This is the reliable way in when swipes get swallowed.
3. Reads the exact `LockPatternView` bounds from the accessibility tree
   (`uiautomator dump`) because screenshots of the prompt come out black.
4. Draws the pattern as one continuous stroke with `input motionevent
   DOWN/MOVE/UP`, pausing on every dot so the system registers each cell,
   including dots a straight line passes through.
5. Verifies the lock state and retries if the device was locked again by the
   screen timeout.

## Requirements

- `adb` on the computer, phone connected and authorized
  (`adb devices` lists the phone as `device`).
- USB debugging enabled on the phone.
- Your pattern digits.

## Usage

```bash
# One-shot unlock (pattern digits use phone keypad orientation):
PATTERN=123456 ./unlock-phone.sh

# Detect the pattern grid coordinates (pattern prompt must be on screen):
./detect-pattern-grid.sh

# Draw a pattern when the prompt is already visible:
./draw-pattern.sh 123456
```

### Digit orientation

Digits follow the **phone keypad** orientation, not the calculator:

```
1 2 3      top-left    top    top-right
4 5 6      mid-left    center mid-right
7 8 9      bottom-left bottom bottom-right
```

So the pattern `123456` draws as: top-left → top → top-right → mid-left
(the stroke passes through the center, which auto-registers) → center →
mid-right. If your pattern was recorded the other way, map your digits to
this grid accordingly.

## Why the screen keeps re-locking

Samsung (and other vendors) can enforce a ~5 s user-activity timeout when the
device is dozing on battery. Everything that matters (open prompt, draw) runs in
one ADB session for that reason. If the phone locks between steps, just rerun
`unlock-phone.sh`; it reopens the prompt and redraws.

If too many wrong patterns are entered, Android enforces a cooldown
("Demasiados intentos... Inténtelo de nuevo dentro de N segundos"). The script
waits it out between attempts.

## Tips that saved a real case

- **Verify the pattern without spending attempts**: `adb shell locksettings
  verify --old 123456` returns "Lock credential verified successfully" without
  touching the screen. Use it to confirm the digits before drawing.
- **Never reuse grid coordinates from another device**: two identical S25
  units had LockPatternView bounds of `[242,1699][1198,2655]` and
  `[62,499][1018,1455]`. The script now always detects the grid and fails hard
  if the prompt is not visible.
- **Dot centers sit at 1/6, 3/6 and 5/6** of the view, not at half its size —
  using half the width as spacing draws a shrunk pattern that never matches.
- After a reboot the user can stay in `RUNNING_LOCKED` even when the keyguard
  accepts the PIN; only a correct on-screen pattern (or the right credential
  prompt) flips it to `RUNNING_UNLOCKED`. Check with
  `adb shell dumpsys user | grep 'Started users state'`.
- Dumps to `/data/local/tmp/`, not `/sdcard/`: some devices restrict writes to
  the shared storage while locked.

## Notes and limits

- The notification tap coordinates (`638 637` in `unlock-phone.sh`) fit a
  1440x3120 screen with the first notification row at the top. Adjust for other
  resolutions, or rely on the auto-retry which re-checks the focus each pass.
- Devices without lock-screen notifications: open the bouncer manually (swipe
  up), then run `./draw-pattern.sh <digits>`.
- The bouncer is rendered with `FLAG_SECURE`: screencasts and screencaps show it
  black. That is why coordinates come from `uiautomator dump`, not from images.
- Works on the lock screen only; it does not defeat biometrics, remote lock,
  factory-reset protection, or anything you do not already know.

## Ethical use

Use this only on devices you own or are explicitly authorized to unlock. The
scripts require your pattern as input; they are an accessibility/automation aid,
not a lock-breaking tool.

## License

MIT
