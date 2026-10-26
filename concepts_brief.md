# LidBlur

* **Author:** Pallav Rai
* **Date:** 2026-10-26

## Overview

LidBlur is a free macOS menu-bar app. As the MacBook lid closes, it progressively blurs and dims the built-in display. It is a visual flourish, not a privacy tool. It reads the hinge angle sensor and draws a click-through overlay window on the built-in display only, never on external monitors. It ships as a notarized DMG on GitHub Releases plus a Homebrew tap.

**Verdict from review: conditional GO for a one-day experiment only. NO-GO on building the app until that experiment passes.** No reviewer found a hard platform blocker. But nobody has yet shown that the effect is visible and looks good in a real lid close.

## Analysis

Six reviewers ran: design, codebase details, zoom-out, comprehension, implementation readiness and structure. No reviewer had hardware or web access, so model support, permission-prompt behavior, HID constants and Homebrew rules are unverified.

### Blockers

1. **The blur can land on an external monitor.** When the lid closes with an external monitor attached (clamshell mode), the built-in display disappears from the screen list. macOS then moves its windows to the remaining screen, so the overlay ends up there. Mirroring copies the overlay too. Fix:
   - Find the built-in display with `CGDisplayIsBuiltin`, never by screen order.
   - Hide the window (`orderOut`) when a display reconfiguration begins (`CGDisplayRegisterReconfigurationCallback`), then rebuild it.
   - Turn the effect off while the built-in display is mirrored.
2. **Nothing guarantees the blur clears, and the off switch sits under it.** Stale readings after wake, a failed read or a stalled main thread could leave the screen blurred with the lid open. The rule must be: when in doubt, show no blur.
   - Clear and hide if no valid reading arrives within about 200–500 ms, or if a value is out of range.
   - On sleep, go clear. On wake, stay clear until a fresh reading arrives.
   - Add a panic hotkey, and turn the effect off if the screen stays nearly fully blurred for more than 10 s while the Mac is awake.
   - Never dim the real backlight.
3. **Mapping blur directly to angle breaks people who work at low angles** (plane trays, beds). Fix: tie the effect to motion.
   - Add blur only while the lid is closing.
   - Clear if the lid holds still above about 25° for 0.5–1 s.
   - Optionally cancel the blur after recent keyboard or trackpad input.
4. **The effect is barely visible.**
   - A normal close crosses 60°→15° in roughly 150–250 ms, while the panel is turning away from you.
   - Opening shows the lock screen first, and app windows cannot draw over it, so the opening half is invisible.
   - Fix: ship the closing effect only, and clear fast when the lid moves up. Add a "Preview effect" menu item and a live status line.
5. **"Stop polling when fully open" cannot work.** Every close starts from fully open. Fix: use push reports if the sensor sends them. Otherwise poll slowly when idle (2–10 Hz), then once per display frame inside the effect band. Stop only while asleep, locked or disabled.
6. **The sensor is unmeasured.** Its update rate, noise, lag and model coverage are unknown. Sleep is triggered by a magnet sensor, not an angle, so the point where the panel goes dark varies by model. Fix:
   - Detect the sensor at runtime, not from a list of models.
   - Calibrate the full-effect angle from the last angle seen before the display turns off.
   - Start full blur nearer 20° than 15°.
7. **Too many open decisions.** Fix: one pure, unit-tested function maps the inputs (enabled, fresh sensor, angle, closing motion, built-in display present and awake, not mirrored, Reduce Transparency) to a target alpha. Small app states: Disabled, Unsupported, Idle, Active, Suspended.

### Major

- **Battery:** a transparent full-screen window costs compositing on every frame, up to 120 Hz on ProMotion screens. Show it only while alpha is above zero. Check App Nap's effect on idle timers. Target: zero Energy Impact when idle.
- **Fading an NSVisualEffectView gives a crossfade, not stronger blur.** At half alpha you see a sharp image with a blurred ghost over it. Options, cheapest first:
  1. blur plus a black dim layer that rises faster, to hide the ghost
  2. dim only
  3. the private blur-radius call, only if 1 and 2 fail

  ScreenCaptureKit is rejected because it needs the Screen Recording permission.
- **Permissions and distribution:**
  - Match the HID device exactly (vendor 0x05AC, product 0x8104, usage page 0x20, usage 0x8A). Broad matching may trigger the Input Monitoring prompt.
  - Hardened runtime with no entitlements. Notarization will not reject this. The Mac App Store is out because of sandboxed device access, not private symbols.
  - Notarize and staple both the .app and the .dmg.
- **macOS lockdown risk:** keep the sensor code in one file behind a small interface, with a test fake. If Apple blocks the sensor, the app turns itself off and the project is archived.
- **Drop the slider and no-sensor fallback.** Without the sensor there is no feature. Show "This Mac has no lid-angle sensor LidBlur can read" and disable the toggle.
- **Settings:** hardcode the measured angles. The v1 menu is Enabled, Launch at Login, status line, Preview, Quit.
- **Accessibility:**
  - With Reduce Transparency on, show only the dim layer.
  - With Reduce Motion on, follow the lid without extra easing.
  - Never snap the effect on or off at a threshold.
  - Listen for these settings on `NSWorkspace.shared.notificationCenter`.
- **Screen sharing:** set `sharingType = .none`, and test whether ScreenCaptureKit respects it.
- **Window setup:**
  - borderless, click-through, and hidden from accessibility and Mission Control
  - joins all Spaces and works beside full-screen apps
  - `.screenSaver` window level
- **Reachability:** the app has no Dock icon and menu-bar items can hide behind the notch. Reopening the app shows a settings window.
- **Testing:** unit-test the alpha function against recorded angle traces. Add a "Copy Diagnostics" item and per-sample logging. Film closes at 240 fps.
- **"iPhone fold-blur" is undefined.** Attach a reference clip with frames at about 60°, 35° and 15°.

## Goals vs. Non-Goals

* **In-Scope Goals:**
  - Blur and dim the built-in display while the lid closes.
  - Fail clear in every error state.
  - Never block input.
  - Near-zero cost when idle.
  - Turn off for clamshell mode, mirroring and Macs without the sensor.
  - Notarized DMG plus a personal Homebrew tap.
* **Out-of-Scope Non-Goals:**
  - privacy protection
  - external displays
  - Macs without the sensor (no slider fallback)
  - Mac App Store
  - the lock screen
  - the opening animation
  - tunable numeric thresholds in v1
  - Sparkle auto-updates
  - private blur-radius APIs and ScreenCaptureKit

## Key Decisions & Staging for Next Steps

1. **Riskiest assumption:** in a normal-speed close, the sensor delivers readings fast and fresh enough, with no permission prompt, to reach a good-looking full effect before the panel goes dark.
2. **One-day experiment before any app work:**
   1. Sensor probe: a command-line tool that logs push reports and 120 Hz polling.
   2. Overlay on the built-in display, with three variants: blur only, blur plus dim, dim only.
   3. 20 filmed closes.
   4. Bonus checks: an external monitor, a sleep/wake cycle and idle CPU.
3. **Pass:**
   - no permission prompt
   - angle updates at 30 Hz or more, with under about 50 ms of lag
   - alpha reaches at least 0.95 before the panel goes dark in 18 of 20 closes
   - one variant looks good on video
   - idle CPU under 0.3%
4. **Kill if:**
   - a permission prompt appears
   - the sensor updates at 10 Hz or slower
   - the panel goes dark before the full effect
   - every variant ghosts or flashes
5. **Carry into the design:**
   - motion-gated mapping
   - fail-clear rules
   - built-in-only detection with reconfiguration handling
   - minimum macOS 13 (or 14 for `NSScreen.displayLink`), Apple Silicon first
   - fixed bundle ID and Team ID before the first release
