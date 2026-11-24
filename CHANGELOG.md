# Changelog

All notable changes to Aeris are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

The section for each version is used as that version's GitHub release notes.

## [Unreleased]

## [1.4.0] - 2026-11-24

### Changed
- **Redesigned in the style of macOS Control Center.** A status line under your AC's name
  ("Cooling to 24° · Room 27°"), a large power button and temperature, mode icons, sliding
  segmented controls for fan speed and special modes, a collapsible Airflow card and proper switches.
- Settings and Schedules use the same card design. Pick your air conditioner from a list, and pause
  schedules with a switch.
- Launch at login and Quit moved into Settings.

## [1.3.1] - 2026-11-24

### Changed
- Airflow angles use a **slider** instead of a row of numbers. Drag or click to aim; the AC is updated
  when you let go. While swinging, the slider is dimmed. Drag it to fix the angle.

## [1.3.0] - 2026-11-24

### Added
- **Airflow controls** for Samsung ACs that support them: up/down and left/right swing, or a fixed
  angle (steps 1–6 up/down, 1–5 left/right), and the left/right swing range (all, left, right).
- Quick switches for the display light, beep and auto-clean, shown when your AC supports them.
- **Schedules** (clock button): turn the AC on or off at a time on chosen days, pause or delete them.
  They're saved in SmartThings, so they run even when your Mac is asleep or off.
- **Turn off in** 30 min / 1 h / 2 h / 4 h, also run by SmartThings.

### Fixed
- The **Sign in with SmartThings** button looked greyed out even though it worked.
- "Finish signing in in your browser" now shows a browser icon instead of a spinner.

## [1.2.0] - 2026-11-24

### Added
- **Sign in with SmartThings.** Sign in once and Aeris renews its access by itself, instead of needing
  a new personal access token every 24 hours. Sign-in uses SmartThings' free, official command-line
  tool (`brew install smartthingscommunity/smartthings/smartthings`); Settings shows the install
  command if it's missing.
- Optional: sign in with your own SmartThings app (developer plan) by entering its Client ID and Secret.

### Changed
- Pasting a personal access token moved to Settings → Advanced. A token saved by an earlier version
  keeps working until it expires.

## [1.1.1] - 2026-11-24

No changes to the app itself. This release makes Aeris easier to install and update.

### Added
- Install with Homebrew: `brew install --cask kashmithnisakya/tap/aeris`.
- Install without Homebrew: `curl -fsSL https://raw.githubusercontent.com/kashmithnisakya/aeris/main/install.sh | bash`.
  Run it again to update, or add `--uninstall` to remove Aeris with its saved token and settings.
- App icon and install commands at the top of the README.

### Changed
- `brew upgrade aeris` now picks up new versions on its own; `--greedy` is no longer needed.
- Every release now also includes a fixed-name `Aeris.zip` that always points to the newest version.

## [1.1.0] - 2026-11-24

### Changed
- Renamed the app from **AC Control** to **Aeris**.
- New app ID `com.kashmithnisakya.aeris`. If you used AC Control, delete it and paste your
  SmartThings token into Aeris again.
- Refresh, Settings, Launch at login and Quit in the panel have a simpler, flatter look.

### Added
- Demo GIF, video and light/dark screenshots in the README.
- `AGENTS.md` with guidance for contributors and coding agents.

## [1.0.0] - 2026-11-24

First release of the menu bar app (as **AC Control**).

### Added
- AC icon in the menu bar that shows the target temperature while the AC is on.
- Panel with on/off, target temperature (−/+), mode, fan speed, swing and special modes
  (Sleep, Quiet, WindFree…). Only the options your AC supports are shown.
- Room temperature, humidity and online status.
- SmartThings token stored in the macOS Keychain; first air conditioner on the account picked automatically.
- Launch at login.
- Universal build for Apple Silicon and Intel, macOS 13 Ventura or later.

[Unreleased]: https://github.com/kashmithnisakya/aeris/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/kashmithnisakya/aeris/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/kashmithnisakya/aeris/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/kashmithnisakya/aeris/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/kashmithnisakya/aeris/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/kashmithnisakya/aeris/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/kashmithnisakya/aeris/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/kashmithnisakya/aeris/releases/tag/v1.0.0
