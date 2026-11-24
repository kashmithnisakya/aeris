# AC Control

A tiny macOS menu bar app for controlling a Samsung / SmartThings air conditioner.

Click the AC icon in the menu bar to turn it on or off, change the temperature, mode, fan speed,
swing and special modes (Sleep, Quiet, WindFree…). While the AC is on, the menu bar shows the
target temperature next to the icon.

- Native SwiftUI, no dependencies, ~1 MB
- Universal (Apple Silicon + Intel), macOS 13 Ventura or later
- Token stored in your macOS Keychain; the app only talks to `api.smartthings.com`
- Only shows the controls your AC actually supports

## Install

1. Download `ACControl-x.y.z.zip` from the [latest release](../../releases/latest) and unzip it.
2. Move **AC Control.app** to your Applications folder.
3. The app isn't notarized by Apple, so the first time **right-click it → Open → Open**.
   If macOS still refuses, run:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/AC Control.app"
   ```

## Set up

1. Create a SmartThings personal access token at <https://account.smartthings.com/tokens>.
   Tick the **Devices** permissions (list, see, control).
2. Click the AC icon in the menu bar, paste the token and press **Save**.
3. The first air conditioner on your account is picked automatically. To choose another,
   open ⚙ Settings → Device.

Tick **Launch at login** at the bottom of the panel to start it automatically.

> SmartThings personal access tokens can expire. If the app says the token was rejected,
> create a new one and paste it in Settings.

## Build from source

```bash
swift run                      # run a debug build
scripts/build-app.sh 1.0.0     # build dist/AC Control.app and dist/ACControl-1.0.0.zip
```

## Release

Push a tag and GitHub Actions builds the app and attaches the zip to a GitHub release:

```bash
git tag v1.0.1 && git push origin v1.0.1
```

## License

MIT
