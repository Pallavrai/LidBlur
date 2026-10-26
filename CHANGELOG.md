# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/Pallavrai/LidBlur/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Pallavrai/LidBlur/releases/tag/v0.1.0
