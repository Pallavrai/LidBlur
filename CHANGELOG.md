# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.1] - 2026-10-27

### Added

- **Settings window:** opens on first launch and whenever the app is opened again.
- **Show icon in menu bar** option. With the icon hidden, LidBlur keeps running in the background.

### Changed

- **Settings redesign:** the Settings window now follows the macOS System Settings style.
- **Start angle:** the default is now 95°, and the slider is limited to 70°–110°. Below 70° the screen is too hard to see for the effect to show.
- **Dimming:** it now fades in exact step with the blur, so a nearly cleared effect no longer leaves the screen darker.

### Fixed

- **Opening after sleep:** after a full close, the screen no longer appears instantly when you open the lid. The blur is held through sleep and recedes as the lid opens. ([#1](https://github.com/Pallavrai/LidBlur/issues/1))
- **Display reconfiguration:** the built-in display's reconfiguration on wake no longer removes the blur. LidBlur only reacts when another display is connected.

## [0.1.0] - 2026-10-26

### Added

- **Hinge-driven effect:** a blur and dim on the built-in display that follows the MacBook's lid angle. It grows while closing and recedes while opening.
- **Holding still** keeps the blur. Keyboard or pointer input fades it out until the lid closes further.
- **Adjustable start angle:** a menu slider (30°–110°, default 80°), plus **Start Blur at Current Lid Angle**.
- **Calibration:** the full-effect angle is calibrated per machine from where the display turns off.
- **Display handling:** the effect pauses during clamshell mode, mirroring, display changes, sleep, and inactive sessions.
- **Accessibility:** Reduce Transparency switches to dim only, and Reduce Motion skips the angle smoothing.
- **Safety:**
  - Control-Option-Command-B quits immediately.
  - The app quits itself if it freezes with the blur showing.
  - A near-full blur is dismissed after two minutes with no input.
- **Menu items:** Preview Effect, Copy Diagnostics, Launch at Login, and a welcome window.
- **Homebrew:** a cask in this repository.

[Unreleased]: https://github.com/Pallavrai/LidBlur/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/Pallavrai/LidBlur/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Pallavrai/LidBlur/releases/tag/v0.1.0
