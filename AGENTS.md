# AGENTS.md

Guidance for AI coding agents (and humans) working on this repo.

## What this is

A native macOS menu bar app (SwiftUI `MenuBarExtra`) that controls a Samsung air conditioner
through the SmartThings REST API (`https://api.smartthings.com/v1`). No third-party dependencies.

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/Aeris/AerisApp.swift` | App entry point, menu bar label |
| `Sources/Aeris/PanelView.swift` | The drop-down panel UI, settings view, chip flow layout |
| `Sources/Aeris/ACStore.swift` | `@MainActor` state: polling, commands, debounced setpoint, launch-at-login |
| `Sources/Aeris/SmartThingsClient.swift` | Thin REST client; status kept as loose JSON |
| `Sources/Aeris/Auth.swift` | Sign-in state, token renewal; own-app OAuth code flow and `aeris://` callback |
| `Sources/Aeris/SmartThingsCLI.swift` | Default sign-in: reads the SmartThings CLI's token, runs the CLI to renew it |
| `Sources/Aeris/StepSlider.swift` | Snapping slider for discrete steps (airflow angles); commits on release |
| `Sources/Aeris/Schedules.swift` | On/off schedules and "turn off in" timer as SmartThings Rules |
| `Sources/Aeris/SchedulesView.swift` | Schedules screen (clock button in the panel header) |
| `Sources/Aeris/Keychain.swift` | Credentials storage in the login Keychain |
| `Sources/Aeris/DemoRecorder.swift` | DEBUG-only renderer for README screenshots/GIF |
| `scripts/build-app.sh` | Builds universal `dist/Aeris.app` + zip, ad-hoc signed |
| `scripts/make-icon.swift` | Draws the app icon |
| `scripts/release-notes.sh` | Prints a version's GitHub release notes from `CHANGELOG.md` |
| `scripts/make-demo.sh` | Regenerates screenshots, GIF and MP4 into `dist/demo/` |
| `install.sh` | One-line installer/uninstaller; downloads `releases/latest/download/Aeris.zip` |
| `.github/workflows/release.yml` | On `v*` tag: build and attach zip to a GitHub release |

## Commands

```bash
swift build                    # compile (debug)
swift run                      # run from source
scripts/build-app.sh 1.2.3     # release bundle + zip in dist/
scripts/make-demo.sh           # demo media in dist/demo/
```

Test without touching a real AC by pointing the app at a mock server:
`AERIS_API=http://127.0.0.1:8799 AERIS_TOKEN=test swift run`.
`AERIS_TOKEN` bypasses the Keychain and is meant only for development.

Sign-in (default): registering a SmartThings OAuth app needs a paid developer plan, so Aeris uses the
official SmartThings CLI's login. It reads `accessToken`/`expires` for `default:api.smartthings.com` from
`~/Library/Application Support/@smartthings/cli/credentials.json` and, when the token is within 5 minutes
of expiry or gets a 401, runs `smartthings locations --json` so the CLI renews (or opens the browser to
log in). Never read, use or store the CLI's refresh token. Renewals are serialized in `AuthManager`.

Own-app sign-in (optional, developer plan): with a client ID/secret (built in from the `AERIS_CLIENT_ID`
/ `AERIS_CLIENT_SECRET` repo secrets, or entered in Settings) Aeris uses the OAuth code flow via
`https://api.smartthings.com/v1/oauth/authorize` → `https://kashmithnisakya.github.io/aeris/callback/`
(`gh-pages` branch) → `aeris://oauth/callback`. Refresh tokens are single-use.

Test env vars: `AERIS_ST_CLI` and `AERIS_ST_CREDENTIALS` (fake CLI and credentials file),
`AERIS_CLIENT_ID` / `AERIS_CLIENT_SECRET`, `AERIS_KEYCHAIN_SERVICE` (isolated Keychain),
`AERIS_POLL_SECONDS`, and in debug builds `AERIS_TEST_SIGNIN=1`.

## Conventions

- Keep it dependency-free and targeting macOS 13+.
- Controls are data-driven: only show a capability if it appears in the device status and is not
  listed in `custom.disabledCapabilities`. Supported option lists come from the status
  (`supportedAcModes`, `supportedAcFanModes`, …), never hard-coded.
- Never log, print or commit tokens, device IDs or location IDs.
- Airflow uses `samsungce.airConditionerAirFlowDirection` (set{Vertical,Horizontal}Direction swing/fixed,
  set{Vertical,Horizontal}AngleStep "1"…, setHorizontalSwingRange). Feature switches are listed in
  `ACStore.featureSwitches` and hidden when the capability is missing or in `samsungce.unavailableCapabilities`.
- Preview the panel for a real model: export `smartthings devices:status <id> -j > status.json`, then run the
  debug build with `AC_DEMO_STATUS=status.json AC_DEMO_OUT=<dir>` (renders `real-light/dark.png`).
- Schedules are SmartThings Rules named `Aeris: …` (`/v1/rules?locationId=`), one `every.specific` with
  reference `Midnight` + minute offset and optional `daysOfWeek` ["Mon"…]; the action is `switch.on/off`.
  Times are in the location's time zone. Rules can't be disabled (status updates are rejected), so pausing
  deletes the rule and keeps the schedule in UserDefaults. The timer is a one-day rule (`Aeris: Timer …`)
  deleted after it fires; stray timer rules are cleaned up on load.
- UI in the panel uses `.buttonStyle(.plain)` so `ImageRenderer` can draw it for demo media.

## Workflow

- `main` is protected: open a pull request, don't push directly.
- Screenshots and videos live on the orphan `assets` branch, not on `main`. Reference them with
  `https://raw.githubusercontent.com/kashmithnisakya/aeris/assets/<file>`.
- Keep `CHANGELOG.md` current: add user-facing changes under `## [Unreleased]` in the same PR.
- Release: in a PR, rename `## [Unreleased]` to `## [1.2.3] - YYYY-MM-DD`, add a fresh empty
  `## [Unreleased]` above it and update the compare links at the bottom. After it merges, push the tag:
  `git tag v1.2.3 && git push origin v1.2.3`. The release workflow uses that section as the release
  notes and fails if it is missing.
  Every release must include `Aeris-<version>.zip` and a fixed-name `Aeris.zip` (build-app.sh makes
  both). `install.sh` downloads `Aeris.zip`; the Homebrew cask in `kashmithnisakya/homebrew-tap`
  (`Casks/aeris.rb`) pins `Aeris-<version>.zip` with a sha256, and that tap's hourly `bump-aeris`
  workflow updates the version and checksum after each release (run it by hand to update sooner:
  `gh workflow run bump-aeris.yml -R kashmithnisakya/homebrew-tap`).
- Don't add AI co-author trailers to commits or PRs.
