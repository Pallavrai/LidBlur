# Contributing to LidBlur

Thanks for your interest in improving LidBlur. This document covers how to report problems, set up a development build, and submit changes.

## Reporting bugs and unsupported Macs

Open an [issue](https://github.com/Pallavrai/LidBlur/issues/new/choose) and include the output of **Copy Diagnostics** from the menu. It lists your Mac model, macOS version, sensor status and display setup, and contains no personal data.

Reports from Macs where LidBlur says "Unsupported" are especially useful, because Apple doesn't document which models expose the lid-angle sensor.

## Development setup

You need:

- an Apple Silicon MacBook with macOS 14 or later
- Xcode 16 or later

```bash
git clone https://github.com/Pallavrai/LidBlur.git
```

```bash
cd LidBlur && swift test
```

To run the app:

```bash
scripts/build.sh && open dist/LidBlur.app
```

You can also open `Package.swift` in Xcode.

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains how the pieces fit together.

## Making changes

- **Keep the engine pure.** Decision logic belongs in `LidBlurCore/EffectEngine.swift`, which has no AppKit or timers. Every behavior change there needs a test in `Tests/LidBlurCoreTests`.
- **Keep the app layer thin.** Files in `Sources/LidBlur` should only adapt macOS APIs to the engine's inputs and outputs.
- **Never trap the user.** Any change must keep the overlay click-through, keep the quit hotkey working, and clear the effect whenever the app is unsure.
- **No new dependencies or permissions** without discussing them in an issue first.
- **Match the surrounding code style.** Run `swift test` before opening a pull request. CI runs the same tests on every push.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Make your change with tests.
3. Update `CHANGELOG.md` under **Unreleased** if the change is user-visible.
4. Open a pull request describing what changed and how you tested it on hardware.

## Releasing (maintainers)

1. Update `CHANGELOG.md` and the version in `App/Info.plist`.
2. Build the release:

   ```bash
   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=lidblur scripts/build.sh 0.1.0 1
   ```

   - `NOTARY_PROFILE` is a keychain profile created once with `xcrun notarytool store-credentials`.
   - Without these variables the build is ad-hoc signed and not notarized.
   - The script writes the DMG checksum into `Casks/lidblur.rb`.
3. Commit, tag `v<version>`, push, and attach `dist/LidBlur-<version>.dmg` to a GitHub release for that tag.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating you agree to uphold it.
