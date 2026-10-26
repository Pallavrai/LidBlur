# LidBlur

A macOS menu-bar app that blurs and dims your MacBook screen as you close the lid, and clears it when the lid stops or opens.

**This is a visual effect, not a privacy tool.** It only affects the built-in display, never external monitors.

## Supported Macs

LidBlur reads the MacBook's hinge (lid-angle) sensor. Not every MacBook has one LidBlur can read. The app checks at launch and tells you if yours is unsupported. Requires macOS 14 or later on Apple Silicon.

## Install

- Download `LidBlur-<version>.dmg` from Releases and drag LidBlur to Applications, or
- `brew install --cask pallavrai/lidblur/lidblur`

## Use

The laptop icon in the menu bar has: a live lid-angle readout, Enabled, Launch at Login, a **Blur starts at** slider (30°–110°, default 80°), **Start Blur at Current Lid Angle**, Preview Effect, Copy Diagnostics and Quit. If the menu-bar icon is hidden (for example behind the notch), open LidBlur again from Applications to get its window.

**If the screen ever stays blurred:** press **Control-Option-Command-B**. That quits LidBlur immediately and the screen returns to normal. LidBlur also turns itself off if the screen stays almost fully blurred for 10 seconds while the Mac is awake, and quits itself if it freezes while the blur is showing.

The effect pauses for:

- clamshell mode
- mirroring
- typing or trackpad use
- holding the lid still above about 25° for 2 seconds (the blur fades out gradually)

## Known limitations

- Only the closing effect is shown. On opening, the lock screen comes first, and apps can't draw over it.
- Whether the overlay shows in screen sharing depends on the sharing app.
- Apple doesn't document the hinge sensor. A future macOS could change or block it, and LidBlur would then report the sensor as unsupported.

## Troubleshooting

Use **Copy Diagnostics** and paste the result into an issue. Logs are in Console.app under subsystem `com.pallavrai.lidblur`. LidBlur makes no network connections.

## Build

```bash
swift test
scripts/bundle.sh            # builds and ad-hoc signs dist/LidBlur.app
```

To release, run `scripts/release.sh <version>` with `DEVELOPER_ID` and `NOTARY_PROFILE` set. The `Tools/lidprobe` tool reads the sensor and tests the overlay on a new Mac; see the comments at the top of its source file.

## Credits

Sensor matching and report format are from [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) by Sam Henri Gold.

## License

MIT, © 2026 Pallav Rai
