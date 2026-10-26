# LidBlur

*   **Author:** Pallav Rai
*   **Status:** Draft
*   **Date:** 2026-10-26

--------------------------------------------------------------------------------

## Overview

LidBlur is a free macOS menu-bar app. As the MacBook lid closes, it blurs and dims the built-in display, and it stops the effect when the lid stops or opens.

- **How it works:**
  - It reads the lid angle from the hinge sensor through IOKit HID.
  - It draws one click-through overlay window on the built-in display only.
- **Purpose:** a visual flourish. It is not a privacy tool.
- **Distribution:** a notarized DMG on GitHub Releases plus a personal Homebrew tap.

This design covers the full app. Several values depend on a one-day hardware experiment that has not run yet (see `concepts_brief.md`). Each such value is a named Open Question below, with a provisional default. The design must not be built past the sensor and overlay layers until that experiment passes.

## The Problem

On a MacBook, closing the lid has no visual transition: the screen stays sharp until the panel goes dark. LidBlur adds a progressive blur-and-dim effect that follows the lid as it closes, similar to the blur foldable phones show as they fold.

**Why this is harder than it looks:**

- **The sensor is undocumented.**
  - Apple publishes no specification for the hinge sensor, its report format or which models have it.
  - Any macOS release could change or block it.
- **The visible window is short.**
  - A normal close passes 60° to 15° in roughly 150–250 ms, while the panel turns away from the user.
  - On opening, the lock screen appears first, and app windows cannot draw over it.
  - So only the closing effect is visible, and only while the Mac is awake.
- **A full-screen overlay is risky.** If it is wrong, the user can be left looking at a blurred screen with the lid open. The menu-bar off switch would be blurred too.
- **Displays change under the app.**
  - In clamshell mode (lid closed, external monitor attached), macOS removes the built-in display and moves its windows onto the external monitor.
  - Mirroring copies anything drawn on the built-in display.
- **People work at low angles,** on plane trays, in bed, or with a propped-up laptop. A blur that follows the angle alone would partly blur the screen while they work.

**Proposed solution in one paragraph:**

- The effect turns on only while the lid is moving downward, and only on a detected, awake, non-mirrored built-in display.
- It defaults to clear in every uncertain state: stale readings, sleep, wake, display changes, sensor silence.
- It costs nothing measurable while the lid is open and still.

## Goals

1.  **Closing effect:** while the lid moves downward through the effect band (provisional 60° to 20°), the built-in display blurs and dims in step with the angle. It reaches at least 95% of the full effect before the panel goes dark in at least 18 of 20 normal-speed closes on a supported Mac.
2.  **Fails clear:** the overlay is hidden (window ordered out, alpha 0) whenever:
    - the app is disabled
    - the sensor is missing, silent for more than 500 ms, or out of range
    - the display or system is asleep or just woke
    - the built-in display is absent or mirrored
    - a display reconfiguration is in progress
3.  **No stuck blur:** with the lid open and still, the screen is never more than 0% blurred for more than 1 s.
    - Two backstops: a panic hotkey clears and disables the effect, and a watchdog turns the effect off if the screen stays more than 90% blurred for over 10 s while the Mac is awake.
4.  **Never blocks input:** the overlay ignores all mouse events, never becomes the key window or main window, and is hidden from accessibility and Mission Control.
5.  **Built-in display only:** in 20 lid-close cycles with an external monitor attached, and in mirroring to a projector, no LidBlur window ever appears on a non-built-in display.
6.  **Near-zero idle cost:** with the lid open and still:
    - Activity Monitor Energy Impact is about 0
    - average CPU is under 0.3%
    - no overlay window is on screen
7.  **Low-angle use is safe:** if the lid holds still above about 25° for 0.5–1 s, the effect clears. It also clears after recent keyboard or trackpad input.
8.  **Accessibility:**
    - With Reduce Transparency on, the effect is dim only.
    - With Reduce Motion on, the effect follows the lid with no added easing.
    - The effect never snaps on or off at a threshold, and never flickers more than 3 times per second.
9.  **No permission prompts:** installing and running LidBlur triggers no Input Monitoring, Screen Recording or Accessibility prompt on a fresh user account.
10. **Installable:** a Developer ID-signed, hardened-runtime, notarized and stapled `.app` and `.dmg` pass `spctl -a -vv`, and the app installs via `brew install --cask` from a personal tap.

## Non-Goals

- **Privacy protection.** LidBlur says so in its first-launch window and in the README.
- **External displays.** They are never blurred.
- **Opening animation.** On opening the effect clears quickly; nothing animates on wake.
- **Lock screen and login window.** App windows cannot draw over them.
- **Macs without a readable hinge sensor.** No manual slider and no no-sensor mode. The app shows "This Mac has no lid-angle sensor LidBlur can read" and disables itself.
- **Mac App Store distribution.** Sandboxed apps cannot open this HID device.
- **Tunable numeric thresholds in v1.** Angles are constants set from measurement, with per-machine calibration.
- **Auto-updates (Sparkle) in v1.** Updates come through Homebrew and the Releases page.
- **Private window-server blur APIs and ScreenCaptureKit.**
- **Intel Macs in v1,** unless an Intel 16" MacBook Pro passes the experiment.

## Open Questions

Each of these is answered by the one-day experiment. The provisional default is used until then.

*   **Q1 – Sensor delivery:** *Partly answered on a Mac17,3 running macOS 27.0.1, with the lid held still at 99°.* Polled feature reports work at about 100 Hz. Push reports arrive only as a 1 Hz heartbeat while the lid is still. Whether pushes speed up while the lid moves is not yet measured. The app polls, with a 10 Hz idle rate (not 5 Hz) to shorten the delay in noticing a close.
*   **Q2 – Sensor rate and lag:** is it at least 30 Hz with under 50 ms of lag? If it is 10 Hz or slower, the project stops.
*   **Q3 – Full-effect angle:** at what angle does the panel go dark on each model? *Default: full effect at 20°, raised per machine to (last angle seen before display-off + 5°).*
*   **Q4 – Visual variant:** which one looks acceptable on video? *Default: B.*
    - A: blur only
    - B: blur plus a faster-rising black dim layer
    - C: dim only
*   **Q5 – Permission prompt:** does exact four-key HID matching avoid Input Monitoring on macOS 15 and 26? *Partly answered on macOS 27.0.1:* the device matched (pid 0x8104, page 0x20, usage 0x8A), and neither lidprobe (run from a terminal) nor the ad-hoc-signed app showed a prompt. Not yet tested on a fresh user account.
*   **Q6 – Screen sharing:** does ScreenCaptureKit respect `sharingType = .none` for the overlay? If not, this becomes a documented limitation.
*   **Q7 – Menu bar coverage:** should the overlay cover the menu bar? *Default: yes, relying on the fail-clear rules, panic hotkey and watchdog.*
*   **Q8 – Reference look:** "iPhone fold-blur" needs a reference clip with frames at about 60°, 35° and 20° to judge the result against.
*   **Q9 – Minimum macOS:** 13 (for `SMAppService`) or 14 (for `NSScreen.displayLink`)? *Default: 14.*

## Implementation Notes (as built)

The build differs from the Detailed Implementation Plan below in these ways. The plan is left as written for the record.

- **Project:** a SwiftPM package (`Package.swift`) instead of `LidBlur.xcodeproj`. It has the same two parts, the `LidBlur` app and the `LidBlurCore` engine, which is unit-tested. Xcode can open `Package.swift`, and `scripts/bundle.sh` assembles and signs `dist/LidBlur.app` from the SwiftPM binary using `App/Info.plist` and `App/LidBlur.entitlements`.
- **Test traces:** generated in code in `EffectEngineTests.swift` rather than stored as JSON fixtures.
- **Assets:** no asset catalog. The menu-bar icon is the SF Symbol `laptopcomputer`. There is no custom app icon yet.
- **Sensor polling:** no push-report path, because the sensor only pushes a 1 Hz heartbeat while still (Q1).
- **Hysteresis:** no separate +3° hysteresis band. The smoothstep curve starts at 0, so the effect is already invisible near 60°, and the wobble tests check that it does not flicker.
- **Bundle ID:** `com.pallavrai.lidblur`. The Releases URL assumes `github.com/pallavrai/LidBlur`.
- **Homebrew cask:** a template at `packaging/homebrew-lidblur/Casks/lidblur.rb`, to copy into the tap repository.
- **Changes from user testing (2026-10-26):**
  - **Adjustable start angle:** a "Blur starts at" slider (30°–110°) and a "Start Blur at Current Lid Angle" menu item are now in the menu. This reverses the "no tunable thresholds in v1" non-goal at the owner's request. The full-effect angle is kept at least 10° below the start angle.
  - **Slower fade-out:** `clearDuration` went from 0.15 s to 0.6 s, so the effect fades instead of snapping off. `stillTimeout` went from 0.75 s to 2 s, so a short pause no longer clears it.
  - **Quit hotkey:** ⌃⌥⌘B now force-quits the app instead of disabling the effect.
  - **Freeze safety net:** `FreezeGuard`, a background timer, quits the process if the main thread stops ticking for 2 s while the overlay is visible.
  - **Live angle readout:** the menu's angle readout now updates while the menu is open, and the sensor keeps being polled while the menu is open even if LidBlur is disabled. Before this fix, the readout only refreshed when the menu opened, and it stayed frozen whenever polling had stopped.
- **Second round of user testing (2026-10-26):**
  - **The blur popped in on a sudden tilt.** There were two causes:
    - The motion window (0.10 s) was no longer than the idle poll interval (0.1 s), so a fast tilt was often missed until the lid was deep in the band.
    - The overlay compared `window.screen`, which is nil while the window is hidden, so it rebuilt the blur view on every first frame.
  - **Fixes:**
    - `downMoveWindow` is now 0.15 s.
    - The overlay is keyed by display ID and built in advance as soon as the lid enters the band.
    - The level now eases toward its target (`riseTimeConstant` 0.03 s), and the sensor filter is lighter (`emaTimeConstant` 0.015 s).
    - Measured in simulation: a 0.4 s slam still reaches 95.6% before the screen goes dark, and a 0.6 s close reaches 98.5%.
  - **Default start angle** raised from 60° to 80°, because at 60° the screen is already hard to see.
- **Third round of user testing (2026-10-26): opening effect.**
  - **On opening,** the blur now recedes in step with the lid, following the same angle curve as the close. It can only decrease while opening.
  - **Pausing or typing** fades the blur out on an ease-out curve (`fadeTimeConstant` 0.15 s, about 1 s to invisible), replacing the linear `clearDuration` ramp.
  - **Both directions** use one exponential follow (`followTimeConstant` 0.03 s).
  - This reverses the design's "no opening animation" non-goal for the case where the Mac stays awake. After sleep, the lock screen still comes first.
- **Fourth round of user testing (2026-10-26): hold keeps the blur.**
  - **Holding the lid still** no longer clears the blur. `stillTimeout` and `holdAngle` are removed.
  - **Input dismisses it:** keyboard, cursor, scroll or click input fades the blur out (ease-out). It stays dismissed until the lid closes further.
  - **While held or opening,** the blur can stay or shrink but never grows without closing motion.
  - **Watchdog:** it now fades a near-full blur out after 120 s with no input, instead of disabling the app after 10 s. The unused disable path (`requestDisable`, `disable()`) is removed.
  - This reverses Goal 7's "clear after holding still" and replaces it with "clear on input". People working at a low angle dismiss the blur as soon as they type or move the cursor.
- **Measured idle cost:** about 0.5% CPU and about 5 wakeups/s on Mac17,3, slightly above the 0.3% goal. The cost is the 10 Hz sensor read. Lowering it depends on measuring real closes (Q1/Q2).

## Critical User Journeys (CUJs)

### CUJ 1: Closing the lid on a supported Mac

*   **Given**: a supported Apple Silicon MacBook, LidBlur enabled, lid open at about 110°, no external display, user working.
*   **When**: the user closes the lid at normal speed.
*   **Then**:
    - Crossing 60° on the way down shows the overlay.
    - Blur and dim grow with the falling angle, reaching at least 95% before the panel goes dark.
    - The Mac sleeps as usual.
    - On wake, the screen is clear and stays clear until a fresh sensor reading arrives.

### CUJ 2: Working with the lid at a low angle

*   **Given**: LidBlur enabled, user typing with the lid at about 45°.
*   **When**: the lid stays still, or the user types or uses the trackpad.
*   **Then**: within 1 s the screen is fully clear, and the overlay window is hidden.

### CUJ 3: Clamshell mode with an external monitor

*   **Given**: an external monitor and power attached, LidBlur enabled.
*   **When**: the user closes the lid and keeps working on the external monitor.
*   **Then**:
    - The overlay is hidden as soon as display reconfiguration begins.
    - No LidBlur window appears on the external monitor.
    - The effect stays off until the built-in display returns and is not mirrored.

### CUJ 4: Something goes wrong

*   **Given**: the effect is partly on and the sensor stops reporting (or reports garbage, or the main thread stalls, or the screen stays more than 90% blurred for 10 s while awake).
*   **When**: the timeout, validation or watchdog trips, or the user presses the panic hotkey.
*   **Then**:
    - The screen clears within 500 ms.
    - The status line explains why.
    - The panic hotkey or watchdog also disables the effect until the user turns it back on.

### CUJ 5: A Mac without the sensor

*   **Given**: a Mac where no matching HID device is found, or the device returns no plausible changing values.
*   **When**: the user launches LidBlur.
*   **Then**:
    - A first-launch window explains that this Mac has no readable lid-angle sensor.
    - The Enabled toggle is disabled.
    - No login item is registered.
    - The app can be quit.

### CUJ 6: Install and first launch

*   **Given**: a fresh user account on macOS 14 or later.
*   **When**: the user runs `brew install --cask <tap>/lidblur` (or opens the DMG) and launches the app.
*   **Then**:
    - Gatekeeper opens it with no warning beyond the standard downloaded-app prompt.
    - No privacy permission prompt appears.
    - A first-launch window explains what the app does, that it is not a privacy tool, and how to preview it.
    - Launch at Login is off until the user opts in.
    - Launching the app again later reopens that window.

## Technical Plan (Architecture)

LidBlur is one Swift/AppKit app target with `LSUIElement = YES` (no Dock icon) and one unit-test target. It adds no third-party dependencies. All decisions flow one way:

1. Inputs (sensor, system state, timers) are collected into a single snapshot.
2. One pure function turns the snapshot into a target effect level.
3. The overlay draws that level.

Nothing else writes to the overlay.

```text
 ┌──────────────┐  angle samples   ┌──────────────────┐
 │ HIDLidSensor │─────────────────▶│                  │
 │ (IOKit HID)  │                  │   EffectEngine   │  target level 0…1
 └──────────────┘                  │  (pure step fn + │──────────────┐
 ┌──────────────┐  state changes   │   small memory)  │              ▼
 │ SystemMonitor│─────────────────▶│                  │      ┌───────────────┐
 │ sleep/wake,  │                  └────────▲─────────┘      │ OverlayWindow │
 │ displays,    │                           │ ticks          │ (built-in     │
 │ mirror, a11y,│                  ┌────────┴─────────┐      │  display only)│
 │ input idle   │                  │   TickScheduler  │      └───────────────┘
 └──────────────┘                  │ idle timer ↔     │
 ┌──────────────┐  disable / clear │ display link     │
 │ Panic hotkey,│─────────────────▶└──────────────────┘
 │ Watchdog,    │
 │ Menu toggle  │      MenuBarController ◀── status text (state + angle + reason)
 └──────────────┘
```

### 1. HIDLidSensor: reading the hinge sensor

- **Shape:** `HIDLidSensor` is a concrete class and the only file that touches IOKit HID. It exposes `start(onSample:onStatus:)`, `poll()`, `stop()`, `status` (`searching`, `found`, `notFound`, `silent` or `invalid`), `latest` and `lastRawBytes`. There is no protocol and no fake: the engine is a pure function, so tests feed it recorded samples directly.
- **Details:**
  - Matching: an `IOHIDManager` matches all four keys exactly: vendor 0x05AC, product 0x8104, usage page 0x20 (sensor), usage 0x8A (orientation). The constants must be confirmed by the experiment (Q5).
  - It never seizes the device and never calls `IOHIDRequestAccess`. Broad matching would also catch the keyboard and trackpad, and that can trigger the Input Monitoring prompt.
  - Device-found and device-removed callbacks are registered, so the sensor is picked up again after wake or after the device re-registers.
  - Reading: if the experiment shows push reports (Q1), it uses `IOHIDDeviceRegisterInputReportCallback`. Otherwise, each scheduler tick calls `IOHIDDeviceGetReport` (feature report, ID 1).
  - Validation: a sample is valid only if the angle is within 0°–360° and the change since the last sample is physically possible (provisional limit: 2000°/s). Invalid samples are dropped and counted.
- **Runtime support check:** the device exists, and within 2 s it returns at least one valid, changing value. No list of Mac models.

### 2. SystemMonitor: everything else the effect depends on

It publishes one value type, `SystemState`:

| Field | Source |
|---|---|
| `systemAwake`, `displayAwake` | `NSWorkspace.shared.notificationCenter`: `willSleep`/`didWake`, `screensDidSleep`/`screensDidWake` |
| `sessionActive` (not locked or switched out) | `sessionDidResignActive`/`sessionDidBecomeActive` on the same center |
| `builtInDisplayID` | the `NSScreen` whose `NSScreenNumber` passes `CGDisplayIsBuiltin`; never the main or first screen |
| `builtInMirrored` | `CGDisplayIsInMirrorSet(builtInDisplayID)` |
| `reconfiguring` | `CGDisplayRegisterReconfigurationCallback`: true on the begin-configuration flag, false once the change finishes and screens are re-read; `NSApplication.didChangeScreenParametersNotification` as a backstop |
| `reduceTransparency`, `reduceMotion` | `NSWorkspace.shared.accessibilityDisplayShould…`, refreshed on `accessibilityDisplayOptionsDidChangeNotification` |
| `secondsSinceInput` | `CGEventSourceSecondsSinceLastEventType(.combinedSessionState, …)` for keys, mouse moves and scrolls. Believed to need no permission; Q5 checks this too. |

Note: sleep, wake and accessibility notifications arrive on `NSWorkspace.shared.notificationCenter`, not on `NotificationCenter.default`. Getting this wrong is a common bug.

### 3. EffectEngine: deciding the effect level

The engine is a pure step function with a small memory struct, so it is fully unit-testable. Every threshold below is a named field of `EngineConstants`; the provisional numbers live only in implementation file 8.

```text
step(memory, input) -> (memory', output)

input  = { now, enabled, sample?: (angle, time), system: SystemState }
memory = { filteredAngle, lastSampleTime, lastDownwardMoveTime,
           level, highLevelSince, disabledReason }
output = { level: 0…1, windowVisible: Bool, appState, reason }
```

**Gates.** Any one of these forces `level = 0` and hides the window, with `reason` set:

- disabled
- no built-in display
- built-in display mirrored
- reconfiguring
- asleep or display asleep
- session inactive
- sensor not found or invalid
- no valid sample for longer than `staleTimeout` (Goal 2)
- just woke, with no fresh sample since

**Filtering.**
- `filteredAngle` is an exponential moving average. Its time constant (`emaTimeConstant`) is short, so it adds little lag.
- The lid counts as "moving down" if the filtered angle fell by at least `downMoveDegrees` within `downMoveWindow`.

**Raw level from angle.**
- `t = clamp((startAngle − angle) / (startAngle − fullAngle), 0, 1)`
- `raw = smoothstep(t)`
- `fullAngle = max(defaultFullAngle, calibratedDarkAngle + calibrationMargin)` (Q3).
- Hysteresis: once the effect has started, it does not end on the way up until the angle passes `startAngle + hysteresis`.

**Motion gating (Goals 3 and 7).** The level may rise only while the lid is moving down. It must fall to 0 when any of these holds:
- the lid has not moved down for `stillTimeout` and the angle is above `holdAngle`
- there was keyboard or trackpad input within `inputTimeout`
- the lid is moving up (fast clear)

Below `holdAngle` the level is held, so a slow final close still completes.

**Rate limits.**
- Rising: the level follows the raw value directly, so it keeps up with the user's hand.
- Falling: the level drops from 1 to 0 over no less than `clearDuration`, so clearing is quick but never snaps. With Reduce Motion on, the falling ramp stays (a full-screen snap is worse), but no other smoothing is added.
- Hysteresis plus the falling ramp keep direction changes under 3 per second (WCAG 2.3.1). There is no separate flip counter; the `wobble` test checks the limit.

**Watchdog.** If `level > watchdogLevel` for longer than `watchdogDuration` while awake, the engine:
1. sets `disabledReason = .watchdog`
2. forces `level = 0`
3. leaves the effect disabled until the user re-enables it

**App states.** The `appState` output drives the menu:

| State | Meaning |
|---|---|
| `Disabled` | the user turned it off, or the panic hotkey or watchdog did |
| `Unsupported` | no readable sensor |
| `Idle` | lid open and still, window hidden |
| `Active` | effect on screen |
| `Suspended` | a gate is closed: asleep, clamshell, mirrored, reconfiguring, locked |

**Calibration.** When `screensDidSleep` fires, the engine stores the last valid angle in `UserDefaults` (`calibratedDarkAngle`), keeping the last 5 values; their median feeds `fullAngle`. 

### 4. TickScheduler: low cost when idle

- **Idle (window hidden):** if the sensor pushes reports, no timer runs at all. Otherwise a `DispatchSourceTimer` runs at 5 Hz with 50 ms leeway.
- **In the band** (filtered angle below `startAngle + 5°`, or `level > 0`): the scheduler switches to `NSScreen.displayLink` on the built-in screen. Each frame reads or uses the latest sample, steps the engine and sets the overlay level directly. It starts no Core Animation transaction per sample.
- **Fully stopped** while asleep, display asleep, session inactive, disabled or unsupported. It restarts on the matching wake or activation notification.
- **App Nap:** while enabled and the display is awake, the app holds `ProcessInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "lid angle")`, so App Nap cannot delay idle ticks. The experiment checks whether this is needed.

### 5. OverlayWindow: drawing the effect

**Window setup:**
- one borderless `NSWindow`, created when entering the band and destroyed after any display reconfiguration
- `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`
- `ignoresMouseEvents = true`; `canBecomeKey` and `canBecomeMain` return false
- `isExcludedFromWindowsMenu = true`, `sharingType = .none`, and hidden from accessibility
- `level = .screenSaver`
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`
- frame = the built-in screen's full `frame` (covers the menu bar, Q7)
- fallback: if it fails to appear over another app's full-screen Space on macOS 26, switch to a non-activating `NSPanel`

**Content (variant B by default, Q4):**
- An `NSVisualEffectView` with `material = .fullScreenUI` (to be compared with `.hudWindow` in the experiment), `blendingMode = .behindWindow`, `state = .active` and a dark appearance. Its alpha is `level`.
- A black `CALayer` dim on top. Its opacity is `maxDim × level^0.6`, so the dim rises faster than the blur and hides the crossfade ghost. Provisional `maxDim = 0.7`.
- With Reduce Transparency on, the blur view is hidden and only the dim is used.

**Visibility:**
- `orderFrontRegardless()` when `windowVisible` becomes true; `orderOut(nil)` when it becomes false.
- It is never left on screen at alpha 0, so idle compositing cost is zero (Goal 6).

**Display changes:**
- On the begin-configuration flag: `orderOut` immediately, then drop the window.
- After the change finishes, re-resolve the built-in screen. A new window is created only the next time the effect is needed.
- This prevents macOS from moving a stale window onto an external monitor (CUJ 3).

### 6. Safety controls

- **Panic hotkey:** registered with Carbon `RegisterEventHotKey` (Control-Option-Command-B by default; not configurable in v1). It sets `disabledReason = .panic`, forces level 0 and posts a status update. Believed to need no permission; checked in the experiment.
- **Crash:** the window server removes a dead process's windows, so a crash already clears the screen.
- **Backlight:** the app never changes the backlight, so no state can leave the screen dark.

### 7. MenuBarController and app shell

**Menu bar:** an `NSStatusItem` with a template icon. Menu items:
1. **Status line** (disabled item), for example "Idle · Lid 112° · sensor OK", "Suspended · external display", "Disabled · watchdog tripped" or "Unsupported · no lid-angle sensor"
2. **Enabled** (checkmark; grayed out when Unsupported)
3. **Launch at Login** (checkmark; `SMAppService.mainApp`, opt-in; shows "Needs approval in System Settings" when the status is `.requiresApproval`)
4. **Preview Effect**: plays a 1.5 s scripted ramp from 0 to 1 and back to 0 through the same engine and overlay
5. **Copy Diagnostics**
6. **About / Releases page**
7. **Quit**

**First-launch window:**
- shown on first run and again whenever the app is reopened (`applicationShouldHandleReopen`), so the app stays reachable when its menu-bar item is hidden behind the notch
- explains what the app does, says it is not a privacy tool, and names the panic hotkey
- has buttons for Preview, Enable and Launch at Login

**Persistence:** `UserDefaults`, with four keys: `enabled` (Bool, default true when supported), `calibratedDarkAngles` ([Double], last 5), `hasLaunchedBefore` (Bool) and `disabledReason` (String?, cleared when the user re-enables). There is no settings UI for angles.

### 8. Diagnostics

- **Logging:** `os.Logger` (subsystem `com.<team>.lidblur`), category `engine`, with one debug-level line per tick in the band: time, raw angle, filtered angle, level, appState, reason, display ID and mirror flag. Viewable in Console.app. Nothing is sent over the network.
- **Copy Diagnostics:** copies a plain-text block to the clipboard: model identifier, macOS version, app version, sensor status, the last 8 raw report bytes, the current thresholds and calibration, display IDs, mirror state and the current reason.

### 9. Build, signing and distribution

- **Project:** Xcode project, Swift 6 language mode, deployment target macOS 14 (Q9), arm64 only.
- **Signing:**
  - hardened runtime on, no App Sandbox, empty entitlements file
  - signed with a Developer ID Application certificate
  - bundle ID fixed before the first release (`com.<team>.lidblur`), because login-item registration and permission records are tied to it
- **Release:** a shell script that:
  1. archives the app
  2. builds the `.dmg` with `hdiutil`
  3. notarizes it with `notarytool submit --wait`
  4. staples both the app and the DMG
  5. checks the result with `spctl -a -vv` and `stapler validate`
  6. prints the SHA-256 for the cask
- **Homebrew:** a separate tap repository, `homebrew-lidblur`, with `Casks/lidblur.rb`. The cask includes `depends_on macos: ">= :sonoma"`, `depends_on arch: :arm64`, `uninstall quit:` and `zap trash:` for the preferences file.

## Alternatives Considered

### Alternative A: Blur that follows the angle alone (the original mapping)

*   **Pros**:
    - Simplest possible logic: one curve from angle to level.
    - Matches the original pitch exactly.
    - Effect is visible on opening too, whenever the Mac is awake.
*   **Cons**:
    - Anyone working at 40–60° (plane tray, bed, propped laptop) gets a permanent partial blur and dim.
    - It keeps a full-screen window composited all the time at those angles, which turns a brief cost into a constant battery drain.
    - It hits low-vision users hardest, since they sit close at odd angles.
*   **Reason for Rejection**: It breaks Goal 7 (low-angle use is safe) and Goal 6 (near-zero idle cost). Motion gating keeps the visible effect during a real close and removes both failures.

### Alternative B: Real variable blur through ScreenCaptureKit plus a Core Image Gaussian blur

*   **Pros**:
    - True blur radius tied to the angle; no crossfade ghost.
    - Uses only public APIs.
*   **Cons**:
    - Needs the Screen Recording permission and shows the recording indicator, which is alarming for a cosmetic app.
    - Captures and blurs the full screen every frame (about 3456x2234 at up to 120 Hz), which costs significant GPU and battery.
    - Adds at least a frame of lag in a band that lasts only 150–250 ms.
*   **Reason for Rejection**: It breaks Goal 9 (no permission prompts) and Goal 6, and the lag defeats the effect.

### Alternative C: Private window-server blur radius (`CGSSetWindowBackgroundBlurRadius` via `dlsym`)

*   **Pros**:
    - True variable blur with no capture, no permission and low cost.
    - iTerm2 has shipped it.
*   **Cons**:
    - A second undocumented dependency on top of the sensor. Any macOS update can remove or change it, with no warning and no workaround.
    - Doubles the per-release re-testing burden.
*   **Reason for Rejection**: It is deferred, not ruled out. Variant B (blur plus a faster-rising dim) may be good enough. This option is adopted only if the experiment shows variants A–C all ghost or flash (Q4). The `OverlayWindow` boundary keeps it a one-file change.

### Alternative D: Dimming with the real backlight or gamma tables (`IODisplaySetFloatParameter`, `CGSetDisplayTransferByTable`)

*   **Pros**:
    - True dimming with no overlay window.
    - Shows up in screen recordings consistently.
*   **Cons**:
    - If the app crashes or hangs mid-dim, the screen stays dark or tinted. The window server does not undo it the way it removes a dead app's windows.
    - Gamma changes interfere with Night Shift, True Tone, HDR and tools like Lunar.
*   **Reason for Rejection**: It breaks Goal 2 (fails clear). An overlay window is the only approach a crash undoes automatically.

### Alternative E: A manual slider or no-sensor mode for Macs without the sensor

*   **Pros**: The app installs and does something on every Mac.
*   **Cons**:
    - A slider that blurs your own screen has nothing to do with the lid, so it is a different, pointless product.
    - It adds UI, settings and a test matrix for no value.
*   **Reason for Rejection**: Without the sensor there is no feature. CUJ 5 shows a clear message and disables the app instead.

### Alternative F: User-tunable numeric angle thresholds

*   **Pros**: Users can adapt the effect to their model or taste.
*   **Cons**:
    - Degrees mean nothing to most users.
    - Two numeric fields invite broken settings, for example a start angle below the full angle.
    - It shifts calibration work onto users instead of measuring it.
*   **Reason for Rejection**: Measured constants plus automatic per-machine calibration (the median dark angle) cover the real variation. If a control is ever needed, it is a single Early / Normal / Late choice with the live angle shown.

### Alternative G: A Mac App Store build

*   **Pros**:
    - Easiest discovery and install.
    - Automatic updates.
    - User trust.
*   **Cons**: App Sandbox blocks opening this HID device. The sensor is read through public calls, but the device is not reachable from the sandbox.
*   **Reason for Rejection**: Not technically possible without dropping the core feature.

### Alternative H: Sparkle auto-updates in v1

*   **Pros**:
    - Users get fixes quickly, which matters when a macOS update breaks the sensor.
*   **Cons**:
    - A third-party dependency.
    - A signing key to manage, and an appcast feed to host.
    - It overlaps with Homebrew's own upgrade path.
*   **Reason for Rejection**: Deferred to a later version. v1 relies on `brew upgrade` and a menu link to the Releases page, and keeps old signed DMGs for rollback.

### Alternative I: Polling only when the lid is not fully open (the original power plan)

*   **Pros**: Zero sensor activity while the lid is open.
*   **Cons**:
    - Every close starts from fully open, so nothing would ever restart polling.
    - The only other lid signal macOS offers, the clamshell switch, changes only at about 0°, which is too late.
*   **Reason for Rejection**: It cannot work. Push reports (if available) or slow idle polling plus a display-link rate in the band achieves the same goal.

--------------------------------------------------------------------------------

## Non-Functional Requirements

- **Security & Privacy:**
  - No network access: no analytics and no update checks. The Releases link opens in the browser.
  - Reads one HID sensor device and the time since the last keyboard or trackpad input, never key codes or contents.
  - Unsandboxed but with hardened runtime and no entitlements.
- **Performance:** with the lid idle, no overlay window is on screen, and there are no ticks or one 5 Hz timer. In the band, the cost is one display-link callback per frame. Measured by Goal 6 with Activity Monitor.
- **Rollout & Rollback:**
  - Every release keeps its signed DMG on GitHub Releases. Rollback is installing the previous DMG or pinning the cask version.
  - If a macOS release blocks the sensor, the app reports Unsupported and disables itself. The README states that support may end, and the project is archived rather than patched around.

### Additional Resources

*   `concepts_brief.md`: the Goldfish brainstorm review and the experiment plan.
*   LidAngleSensor (Sam Henri Gold): prior art for sensor matching and report decoding. Check its license; credit it in the README.
*   Lunar: prior art for built-in display and mirroring detection.

### Future Improvements

*   **Private blur radius** (Alternative C) if dim plus crossfade proves unacceptable.
*   **Sparkle** updates once there are enough users to justify it.
*   **Intel 16" MacBook Pro** support if it passes the experiment.
*   **Early / Normal / Late** timing choice if calibration proves insufficient.

--------------------------------------------------------------------------------

## Detailed Implementation Plan

**Order of work:** build the experiment probe (file 1) first and run it. Record the answers to Q1–Q6 in this document, then build files 2 onward. If a kill criterion from `concepts_brief.md` trips, stop after file 1.

**Layout:** a single Xcode project at the repository root. App sources are under `LidBlur/`, unit tests under `LidBlurTests/`, and the probe under `Tools/lidprobe/`.

### Target Files to Create/Modify

#### 1. `Tools/lidprobe/main.swift` (Create)

*   **Type / Scope**: a standalone Swift command-line tool, built with `swiftc main.swift -o lidprobe`. It is not part of the Xcode app target.
*   **Proposed Changes**: answers Q1–Q6 on real hardware.
    - **Sensor modes:**
      - `lidprobe sensor`: matches the four HID keys, registers an input-report callback, and also polls `IOHIDDeviceGetReport` (feature report, ID 1) at 120 Hz.
        - Prints a CSV row per sample: `mono_time_ms, source(push|poll), raw_hex, angle_deg`.
        - Prints `SCREENS_DID_SLEEP <time>` and `SCREENS_DID_WAKE <time>` lines from `NSWorkspace` notifications, using a minimal `NSApplication` run loop.
      - `lidprobe sensor --broad`: matches on vendor ID only, to confirm whether broad matching triggers the Input Monitoring prompt.
    - **Overlay mode (`lidprobe overlay`):**
      - Opens one window on the `CGDisplayIsBuiltin` screen, configured as in Technical Plan §5, and maps the angle linearly from 60° to 20° on every sample.
      - Keys `a`, `b` and `c` switch the visual variant. Key `m` cycles through `.fullScreenUI`, `.hudWindow` and `.underWindowBackground`. The live angle and level are drawn in the corner for filming.
      - Includes the reconfiguration callback and `orderOut` logic, so the external-monitor check is meaningful.
    - **Output:** results are written by hand into Open Questions Q1–Q6, and the CSV logs are kept in `Tools/lidprobe/results/<model>-<macOS>.csv`.

#### 2. `LidBlur.xcodeproj` (Create)

*   **Type / Scope**: Xcode project.
*   **Proposed Changes**: two targets.
    - **App target `LidBlur`:**
      - macOS 14 deployment target, arm64 only, Swift 6 language mode
      - hardened runtime on, App Sandbox off
      - `Info.plist` and `LidBlur.entitlements` from files 3 and 4
      - bundle ID `com.<team>.lidblur`, with `<team>` replaced by the final reverse-DNS prefix before the first release
    - **Unit-test target `LidBlurTests`:** hosted by no app (logic tests), with the `LidBlurTests/Traces` folder as a resource.
    - **Shared scheme `LidBlur`:** runs the tests.

#### 3. `LidBlur/Info.plist` (Create)

*   **Type / Scope**: bundle configuration.
*   **Proposed Changes**:
    - `LSUIElement = YES`: no Dock icon or app menu
    - `CFBundleShortVersionString` and `CFBundleVersion`, bumped by the release script
    - `LSMinimumSystemVersion = 14.0`
    - `NSHumanReadableCopyright`
    - No usage-description keys, because no privacy permission is requested.

#### 4. `LidBlur/LidBlur.entitlements` (Create)

*   **Type / Scope**: code-signing entitlements.
*   **Proposed Changes**: an empty dictionary. It is kept as an explicit file so a reviewer can see that no entitlement is requested.

#### 5. `LidBlur/AppDelegate.swift` (Create)

*   **Type / Scope**: app entry point and wiring. Uses `@main` with `NSApplicationDelegate`.
*   **Proposed Changes**:
    - **Owns the components:** `Settings`, `HIDLidSensor`, `SystemMonitor`, `EffectEngine` memory, `TickScheduler`, `OverlayWindowController`, `PanicHotKey`, `MenuBarController`, `WelcomeWindowController` and `Diagnostics`.
    - **Runs the loop:** on each scheduler tick, it builds `EngineInput` from the latest sample, `SystemState`, `Settings.enabled` and any active preview, then calls `EffectEngine.step`. It passes the output to:
      - the overlay (`apply(level:visible:reduceTransparency:)`)
      - the scheduler (`mode`)
      - the menu (`appState`, `reason`, angle)
      - diagnostics
    - **Lifecycle hooks:**
      - `applicationDidFinishLaunching`: starts the sensor check, shows the welcome window if `!hasLaunchedBefore`, and registers the hotkey.
      - `applicationShouldHandleReopen`: shows the welcome window.
      - `applicationWillTerminate`: orders the overlay out and stops the sensor.

#### 6. `LidBlur/Sensor/HIDLidSensor.swift` (Create)

*   **Type / Scope**: the only file that imports IOKit HID.
*   **Proposed Changes**: defines `enum SensorStatus { searching, found, notFound, silent, invalid }`, `struct AngleSample { angle: Double; time: TimeInterval /* monotonic */ }` and the `HIDLidSensor` class with the API in Technical Plan §1.
    - **Matching:** an `IOHIDManager` with an exact matching dictionary (vendor 0x05AC, product 0x8104, usage page 0x20, usage 0x8A, as confirmed by Q5). Open options are `kIOHIDOptionsTypeNone`, never seize.
    - **Device lifecycle:** matching and removal callbacks update `status` and the current device handle.
    - **Reading:**
      - If Q1 shows push reports: register the input-report callback on a 64-byte buffer.
      - Otherwise: `poll()` calls `IOHIDDeviceGetReport(kIOHIDReportTypeFeature, 1, …)`.
      - Decoding (bytes 1–2, little-endian, as degrees) follows the format confirmed by the probe.
    - **Validation:** a sample is accepted only if the angle is in [0, 360] and `|Δangle|/Δt ≤ 2000°/s`. Rejected samples increment an invalid counter; 10 in a row set `invalid`.
    - **Support check:** after `start`, if there is no device within 2 s, the status becomes `notFound`. If the device exists but there is no valid sample within 2 s, it becomes `silent`.
    - **Threading:** runs on the main run loop. All callbacks are main-thread.

#### 7. `LidBlur/System/SystemMonitor.swift` (Create)

*   **Type / Scope**: system-state observer.
*   **Proposed Changes**:
    - **State:** publishes `SystemState { systemAwake, displayAwake, sessionActive, builtInDisplayID: CGDirectDisplayID?, builtInMirrored, reconfiguring, reduceTransparency, reduceMotion, justWoke }`, through an `onChange` closure and a `current` property.
    - **Observers:** subscribes on `NSWorkspace.shared.notificationCenter` to:
      - `willSleep`, `didWake`
      - `screensDidSleep`, `screensDidWake`
      - `sessionDidResignActive`, `sessionDidBecomeActive`
      - `accessibilityDisplayOptionsDidChangeNotification`
    - **Display changes:**
      - Registers `CGDisplayRegisterReconfigurationCallback`. The `.beginConfigurationFlag` sets `reconfiguring = true` and calls `onChange` synchronously, so the overlay hides before screens move. The finishing callback, and `NSApplication.didChangeScreenParametersNotification`, re-resolve the built-in display and set `reconfiguring = false`.
      - Built-in display: `NSScreen.screens.first { CGDisplayIsBuiltin($0.displayID) != 0 }`. Mirroring: `CGDisplayIsInMirrorSet`.
    - **Wake:** `justWoke` is set on `didWake` or `screensDidWake`. The engine clears it once a fresh sample arrives.
    - **Input:** `secondsSinceInput()` returns the minimum of `CGEventSourceSecondsSinceLastEventType(.combinedSessionState, t)` over keyDown, mouseMoved, scrollWheel and leftMouseDown.
    - **`screensDidSleep` hook:** forwards the last valid angle to `Settings.recordDarkAngle` for calibration.

#### 8. `LidBlur/Engine/EffectEngine.swift` (Create)

*   **Type / Scope**: pure logic. No AppKit, IOKit or timers, so it is fully unit-tested.
*   **Proposed Changes**:
    ```text
    struct EngineConstants { startAngle=60, defaultFullAngle=20, calibrationMargin=5,
        hysteresis=3, holdAngle=25, stillTimeout=0.75, inputTimeout=1.5,
        downMoveDegrees=0.5, downMoveWindow=0.10, emaTimeConstant=0.03,
        staleTimeout=0.5, clearDuration=0.15,
        watchdogLevel=0.9, watchdogDuration=10 }
    enum AppState { disabled, unsupported, idle, active, suspended }
    enum Reason { userDisabled, panic, watchdog, noSensor, sensorSilent, sensorInvalid,
        noBuiltInDisplay, mirrored, reconfiguring, asleep, sessionInactive, justWoke,
        stale, still, recentInput, openingFast, none }
    struct EngineInput { now, enabled, disabledReason?, sensorStatus, sample?,
        system: SystemState, secondsSinceInput, fullAngle, previewLevel? }
    struct EngineMemory { filteredAngle?, lastSampleTime?, angleHistory (last 100 ms),
        lastDownMoveTime?, level, effectStarted, highLevelSince? }
    struct EngineOutput { level, windowVisible, appState, reason, filteredAngle?,
        requestDisable: Reason? /* watchdog */, inBand: Bool }
    static func step(_ m: EngineMemory, _ i: EngineInput) -> (EngineMemory, EngineOutput)
    ```
    - **Evaluation order:**
      1. Hard gates (Technical Plan §3), which return level 0 and `windowVisible = false`.
      2. A preview override (`previewLevel` set and display gates open), which outputs it directly.
      3. EMA filter and down-motion detection.
      4. Raw level from smoothstep.
      5. Motion gating.
      6. Rate limits.
      7. The watchdog.
    - **Window visibility:** `windowVisible = level > 0.001`.
    - **Scheduler mode:** `inBand = filteredAngle < startAngle + 5 || level > 0`.

#### 9. `LidBlur/Scheduling/TickScheduler.swift` (Create)

*   **Type / Scope**: tick source.
*   **Proposed Changes**:
    - **Modes:** `stopped`, `idle`, `band`.
      - `idle`: a `DispatchSourceTimer` on the main queue at 200 ms with 50 ms leeway, or no timer when the sensor delivers push reports, in which case ticks are driven by samples.
      - `band`: `NSScreen.displayLink(target:selector:)` on the built-in screen, added to the main run loop in `.common` mode.
    - **Rules:** `setMode(_:screen:)` switches idempotently. The display link is invalidated on any reconfiguration.
    - **App Nap:** holds a `ProcessInfo` activity token while the mode is not `stopped`.

#### 10. `LidBlur/Overlay/OverlayWindowController.swift` (Create)

*   **Type / Scope**: the only file that creates the overlay window.
*   **Proposed Changes**:
    - **`apply(level:visible:reduceTransparency:on screen:)`:**
      - Creates the window lazily with every property in Technical Plan §5 (a `NSWindow` subclass overrides `canBecomeKey`/`canBecomeMain` to return false).
      - Content: a dark-appearance `NSVisualEffectView` (`material` from a constant, `.behindWindow`, `.active`) plus a black dim `CALayer` sublayer.
      - Sets `effectView.alphaValue = level` (0 when `reduceTransparency`) and `dim.opacity = maxDim * pow(level, 0.6)`, inside `CATransaction` with actions disabled.
      - Calls `orderFrontRegardless()` or `orderOut(nil)` on visibility edges.
    - **`teardown()`:** orders out and releases the window. Called on reconfiguration begin and on quit.
    - **Variant constant:** `OverlayStyle { blurAndDim, dimOnly }`, set from Q4.

#### 11. `LidBlur/Safety/PanicHotKey.swift` (Create)

*   **Type / Scope**: Carbon global hotkey.
*   **Proposed Changes**: registers ⌃⌥⌘B with `RegisterEventHotKey` and an `InstallEventHandler` on the application event target. The handler calls a closure that sets `Settings.enabled = false` and `disabledReason = .panic`, and immediately calls `OverlayWindowController.teardown()`, without waiting for the next tick. It unregisters on quit. If registration fails, the error is logged and shown in diagnostics.

#### 12. `LidBlur/UI/MenuBarController.swift` (Create)

*   **Type / Scope**: `NSStatusItem` and menu.
*   **Proposed Changes**:
    - **Menu:** the items listed in Technical Plan §7.
    - **Status line:** `"\(appState) · \(reasonText) · Lid \(Int(angle))°"`, rebuilt in `menuNeedsUpdate` so it does not update every tick.
    - **Actions:**
      - Enabled: toggles `Settings.enabled`, and clears `disabledReason` when turned on.
      - Launch at Login: calls `SMAppService.mainApp.register()` / `unregister()` and shows the `.requiresApproval` text. Errors appear in the status line.
      - Preview: sets a preview ramp (1.5 s, 0→1→0) consumed by AppDelegate as `previewLevel`.
      - Copy Diagnostics: calls `Diagnostics.report()` and copies it to `NSPasteboard`.
    - **Icon:** a template image `MenuBarIcon` from the asset catalog.

#### 13. `LidBlur/UI/WelcomeWindowController.swift` (Create)

*   **Type / Scope**: first-launch and reopen window (AppKit, about 400×300).
*   **Proposed Changes**:
    - **Text:** what the app does; "This is a visual effect, not a privacy tool"; the panic hotkey; and the current support status. The unsupported message is "This Mac has no lid-angle sensor LidBlur can read".
    - **Buttons:** Preview Effect, Enable (hidden when unsupported), and a Launch at Login checkbox.
    - **Activation:** calls `NSApp.activate()` when shown, since the app has no Dock icon. Sets `hasLaunchedBefore = true` on close.

#### 14. `LidBlur/Support/Settings.swift` (Create)

*   **Type / Scope**: `UserDefaults` wrapper.
*   **Proposed Changes**: properties `enabled` (default true), `disabledReason` (raw string), `hasLaunchedBefore` and `calibratedDarkAngles` ([Double], capped at 5).
    - `recordDarkAngle(_:)` ignores values outside 5°–60° and appends the rest.
    - `fullAngle` = `max(20, median(calibratedDarkAngles) + 5)`, or 20 when the list is empty.

#### 15. `LidBlur/Support/Diagnostics.swift` (Create)

*   **Type / Scope**: logging and the diagnostics report.
*   **Proposed Changes**:
    - **Logging:** `Logger(subsystem: bundleID, category: "engine")`. `logTick(output:sample:system:)` writes at `.debug` level, and only while `inBand`.
    - **Report:** `report()` builds the plain-text block from Technical Plan §8. The model identifier comes from `sysctlbyname("hw.model")`.

#### 16. `LidBlur/Assets.xcassets` (Create)

*   **Type / Scope**: asset catalog.
*   **Proposed Changes**: `AppIcon` (all macOS sizes) and `MenuBarIcon` (a monochrome template PDF of a half-closed laptop).

#### 17. `LidBlurTests/EffectEngineTests.swift` (Create)

*   **Type / Scope**: XCTest unit tests for the engine.
*   **Proposed Changes**: each case loads a JSON trace (`[{t, angle}]`, plus optional scripted sensor-status changes) with a small helper in the same file and replays it through `EffectEngine.step` at 120 Hz and asserts on the outputs.
    - `fastClose` and `slowClose`: the level reaches at least 0.95 by `fullAngle`.
    - `lowAngleTyping` (a hold at 45° with recent input): the level is 0 within 1 s.
    - `holdAt40NoInput`: the level is 0 within 0.75 s + 0.15 s.
    - `holdAt22`: the level is held.
    - `wobbleAtThreshold` (oscillating 59–63°): at most 3 direction flips per second, and no flicker.
    - `sensorDropout` (no samples for 600 ms): the level is 0 with reason `stale`.
    - `garbageValues` (jumps of 500° per sample): samples are rejected and the level is 0.
    - `opening`: the level is 0 within 150 ms of upward motion.
    - `reconfigureMidClose`, `mirroredDuringClose`, `sleepThenWakeStale` (a stale 5° sample after wake): the level is 0 and `windowVisible` is false.
    - `watchdog` (a hold at 15° for 11 s, awake): `requestDisable == .watchdog`.
    - `reduceMotion`: the same targets without extra smoothing.
    - `previewIgnoresSensorButNotDisplayGates`: preview runs without a sensor, but not while mirrored.

#### 18. `LidBlurTests/SettingsTests.swift` (Create)

*   **Type / Scope**: XCTest.
*   **Proposed Changes**: tests the calibration median, the cap of 5 values, rejection of values outside 5°–60°, and the 20° floor. Uses a dedicated `UserDefaults(suiteName:)` that is removed in `tearDown`.

#### 19. `LidBlurTests/Traces/*.json` (Create)

*   **Type / Scope**: test fixtures.
*   **Proposed Changes**: `fast_close.json`, `slow_close.json`, `low_angle_typing.json`, `wobble.json`, `dropout.json`, `garbage.json`, `opening.json` and `long_hold.json`.
    - The first two are converted from real `lidprobe` CSV logs.
    - The rest are synthetic, generated by hand from the same format.

#### 20. `scripts/release.sh` (Create)

*   **Type / Scope**: release automation (bash, run locally).
*   **Proposed Changes**:
    - **Inputs:** a version argument, plus these environment variables: `DEVELOPER_ID` (signing identity name) and `NOTARY_PROFILE` (a `notarytool store-credentials` keychain profile name, so no secrets are kept in the repository).
    - **Steps:**
      1. Set the version.
      2. `xcodebuild archive` and export with Developer ID.
      3. `codesign --verify --strict`.
      4. `notarytool submit --wait` the zipped app, then `stapler staple` the app.
      5. `hdiutil create` the DMG, sign it, notarize it and staple it.
      6. `spctl -a -vv -t install` on the DMG.
      7. Print the SHA-256 and update the version and checksum in the cask file from file 22.
    - **Failure:** the script stops on the first failing step (`set -euo pipefail`).

#### 21. `.github/workflows/ci.yml` (Create)

*   **Type / Scope**: CI on GitHub Actions, on a `macos-14` runner.
*   **Proposed Changes**: runs `xcodebuild test -scheme LidBlur -destination 'platform=macOS'` on every push and pull request. No signing or notarization in CI, since that needs the developer's credentials and runs only through `release.sh`.

#### 22. `homebrew-lidblur/Casks/lidblur.rb` (Create, in a separate repository)

*   **Type / Scope**: Homebrew cask in a personal tap.
*   **Proposed Changes**:
    - `version`, `sha256` and a `url` pointing to the GitHub Release DMG
    - `name "LidBlur"`, `desc` and `homepage`
    - `depends_on macos: ">= :sonoma"` and `depends_on arch: :arm64`
    - `app "LidBlur.app"`
    - `uninstall quit: "com.<team>.lidblur"` and `zap trash: ["~/Library/Preferences/com.<team>.lidblur.plist"]`

#### 23. `README.md` (Create)

*   **Type / Scope**: user documentation.
*   **Proposed Changes**:
    - what it does, with a GIF from the filmed experiment
    - "a visual effect, not a privacy tool"
    - supported Macs, determined at runtime: the app tells you
    - install via the DMG or `brew install --cask <user>/lidblur/lidblur`
    - the panic hotkey and troubleshooting with Copy Diagnostics
    - known limitations: no opening animation, no lock screen, screen sharing (Q6), and support may end with a future macOS
    - credit to LidAngleSensor

#### 24. `LICENSE` (Create)

*   **Type / Scope**: license.
*   **Proposed Changes**: MIT. If any LidAngleSensor code (not just constants) is copied, its license text is added to `THIRD_PARTY_NOTICES.md`.

#### 25. `.gitignore` (Create)

*   **Type / Scope**: VCS config.
*   **Proposed Changes**: ignores `build/`, `DerivedData/`, `*.xcuserstate`, `xcuserdata/`, release `*.dmg` and `*.zip` files, and `Tools/lidprobe/lidprobe`. The probe's CSV results are kept.

### Verification Plan

*   **Compilation/Build**: `xcodebuild -scheme LidBlur -configuration Release build`, and `swiftc Tools/lidprobe/main.swift -o Tools/lidprobe/lidprobe`.
*   **Unit Tests**: `xcodebuild test -scheme LidBlur -destination 'platform=macOS'`. All cases in files 17 and 18 must pass.
*   **Static Analysis & Linting**: Swift 6 strict concurrency with zero warnings (`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` for Release).
*   **Test Coverage Requirement**: 90%+ line coverage of `EffectEngine.swift` and `Settings.swift`. The AppKit and IOKit files are covered by the manual checks below.
*   **E2E / manual, on a supported Mac** (each maps to a Goal or CUJ):
    1. **Visible effect (Goal 1, CUJ 1):** 20 filmed closes at mixed speeds. Level ≥ 0.95 before dark in at least 18 of them.
    2. **Low-angle work (CUJ 2):** 5 minutes of typing at 45°; the screen stays clear.
    3. **Clamshell and mirroring (Goal 5, CUJ 3):** 20 clamshell cycles plus mirroring to a projector. After each cycle, `CGWindowListCopyWindowInfo` shows no LidBlur window on a non-built-in display.
    4. **Sleep and wake (Goal 3):** 10 sleep/wake cycles; no stuck blur after wake.
    5. **Recovery (CUJ 4):** the panic hotkey clears the effect within 500 ms. The watchdog trips in the forced-hold test.
    6. **Idle cost (Goal 6):** 10 minutes idle with the lid open. Activity Monitor Energy Impact is about 0, and CPU is under 0.3%.
    7. **Permissions and Gatekeeper (Goal 9, CUJ 6):** install from the notarized DMG on a fresh user account. No privacy prompts, and Gatekeeper accepts the app.
    8. **Accessibility (Goal 8):** with Reduce Transparency on, the effect is dim only. With Reduce Motion on, there is no added easing.
    9. **Screen sharing (Q6):** with a call active, check whether viewers see the overlay; record the result in the README.
    10. **Unsupported Mac (CUJ 5):** run on a Mac without the sensor and get the unsupported message.

--------------------------------------------------------------------------------

*Drafted with EGM*
