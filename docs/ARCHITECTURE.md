# Architecture

LidBlur is a Swift package with two targets:

| Target | Contents |
| --- | --- |
| `LidBlurCore` | The effect engine and settings. Pure Swift, no AppKit, fully unit-tested. |
| `LidBlur` | The menu-bar app: sensor, system monitoring, overlay window and UI. |

`scripts/build.sh` wraps the `LidBlur` executable in an app bundle using `App/Info.plist`, `App/AppIcon.icns` and `App/LidBlur.entitlements`.

## Data flow

```text
HIDLidSensor ──angle──┐
SystemMonitor ─state──┼──▶ EffectEngine.step ──level──▶ OverlayWindowController
Settings ──angles─────┘          ▲                          (built-in display only)
                                 │ tick
                           TickScheduler
```

On every tick, `AppDelegate` does five things:

1. polls the sensor
2. builds an `EngineInput`
3. calls `EffectEngine.step`
4. applies the resulting level to the overlay
5. updates the scheduler and menu

`EffectEngine.step` decides the effect level on its own; no other component does.

## Components

- **`HIDLidSensor`** is the only file that uses IOKit HID.
  - It matches Apple's lid-angle sensor exactly (vendor `0x05AC`, product `0x8104`, usage page `0x20`, usage `0x8A`) and polls feature report 1.
  - Broader matching would also open the keyboard and trackpad, and could trigger an Input Monitoring prompt.
  - Implausible values or jumps are rejected.
  - If no device appears within two seconds, the Mac is marked unsupported.
- **`SystemMonitor`** publishes a `SystemState`. It covers:
  - sleep and wake
  - session changes
  - which screen is the built-in display (`CGDisplayIsBuiltin`), and whether it is mirrored
  - display reconfiguration
  - Reduce Transparency and Reduce Motion

  On the start of a display reconfiguration, it reports synchronously so the overlay is removed before macOS moves windows between screens.
- **`EffectEngine`** (in `LidBlurCore`) is a pure function from `(EngineMemory, EngineInput)` to `(EngineMemory, EngineOutput)`. See below.
- **`TickScheduler`** controls how often the app ticks:
  - **idle:** a 10 Hz timer while the lid is open and still
  - **band:** one tick per display frame, through `NSScreen.displayLink`, while the lid is in or entering the effect range
  - **stopped:** no ticks while asleep, disabled or unsupported
- **`OverlayWindowController`** owns one borderless window on the built-in display. The window:
  - ignores the mouse and can't become key
  - sits at `.screenSaver` level and joins all Spaces
  - is excluded from screen capture (`sharingType = .none`)
  - contains an `NSVisualEffectView` and a black dim layer. The dim rises faster than the blur, which hides the crossfade look of fading a fixed-radius blur.

  The window is only on screen while the level is above zero.
- **`PanicHotKey`** registers Control-Option-Command-B through Carbon, which needs no permission. Pressing it exits the process, and the window server removes the overlay.
- **`FreezeGuard`** is a background timer. If the main thread stops ticking for two seconds while the overlay is visible, it exits the process.
- **`MenuBarController`** and **`WelcomeWindowController`** provide the UI.

## Effect engine rules

1. **Gates.** The effect is forced to zero in any of these cases:
   - there is no built-in display, or it is mirrored
   - a display reconfiguration is in progress
   - the system or display is asleep
   - the session is inactive
   - the user has disabled the effect
   - the sensor is missing or not responding
   - the latest sample is older than 0.5 s, or was taken before the last wake
2. **Filtering.** The angle passes through a short exponential moving average (15 ms), which is skipped under Reduce Motion. The lid counts as closing when the filtered angle drops at least 0.5° within 0.15 s.
3. **Mapping.** A smoothstep curve maps the angle to a target level, running from the user's start angle down to the full angle. The full angle is calibrated per machine from the angle seen just before the display turns off, plus 5°, with a floor of 20°.
4. **Motion.** While closing, the target follows the angle. While holding or opening, the target can only stay the same or fall, so the blur recedes with the lid and never reappears by itself.
5. **Dismissal.** Keyboard or pointer input within the last 1.5 s dismisses the effect until the lid closes further.
6. **Easing.** The level approaches its target exponentially: 30 ms while following the hinge, 150 ms when fading after a dismissal.
7. **Watchdog.** A near-full blur held for two minutes with no input is dismissed.

All constants are in `EngineConstants`.

## Testing

`swift test` runs the `LidBlurCore` tests. They replay synthetic lid traces through the engine at 120 Hz:

- fast and slow closes, and sudden tilts sampled at the idle rate
- holding still, input dismissal, and opening
- wobble near the start angle
- sensor dropouts, invalid values and stale samples after wake
- display gates, the watchdog and preview

The AppKit and IOKit layers are thin and are checked by hand on hardware.
