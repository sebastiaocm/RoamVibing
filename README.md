# RoamVibing

Keep coding when the lid closes.

RoamVibing is a small macOS menu-bar app for keeping a Mac awake while AI coding agents, downloads, scripts, or audio are running.

It has two modes and safety settings grouped under the menu-bar `Settings` item:

- `Normal Awake`: uses IOKit power assertions. This is non-admin and prevents idle sleep while the lid stays open.
- `Closed-Lid Mode`: asks for administrator permission and runs `/usr/bin/pmset -a disablesleep 1`, then verifies macOS reports `SleepDisabled 1`. Use this only when you need the MacBook closed without an external display. Turning it off runs `/usr/bin/pmset -a disablesleep 0` and verifies `SleepDisabled 0`.
- `Battery Safety`: optionally stops the RoamVibing session when the Mac is running on battery at or below your chosen threshold. The default is on at 20%.
- `Instant Lock on Activity`: arms after a short idle period while a RoamVibing session is running. When the lid opens after being closed, or when keyboard or mouse input is detected, it locks the screen immediately and turns the active RoamVibing session off. This is one-shot per RoamVibing session so the next time you close the lid, macOS can sleep normally.
- `Mute on Lid Close`: the default is on. When macOS reports the lid closing during a RoamVibing session, RoamVibing mutes active audio output devices through CoreAudio. It does not unmute when the lid opens.

## Requirements

- macOS 13 or newer
- Xcode command line tools or Xcode

## Run From Source

```sh
swift run RoamVibing
```

The app appears in the menu bar as a coder-at-laptop icon.

## Build a `.app`

```sh
./scripts/build-app.sh
```

The app bundle is created at:

```text
dist/RoamVibing.app
dist/RoamVibing.app.zip
```

The menu app is signed as a local-only app without App Sandbox. Closed-Lid Mode needs a direct macOS administrator prompt for the power-management command; the previous sandboxed-helper approach could leave the helper waiting for authentication and never start Closed-Lid Mode. RoamVibing does not include network client/server code, network listeners, remote-control APIs, event taps, or Accessibility/Input Monitoring access.

The zip is built from the strictly verified staging app and then extracted into `/private/tmp` for a final strict codesign check.

## Security & Permissions

Closed-Lid Mode changes a protected macOS power setting. Depending on how the app was built and installed, macOS may ask for administrator approval, Touch ID, or your Mac password before RoamVibing changes that setting.

RoamVibing does not include network client/server code, network listeners, remote-control APIs, event taps, or Accessibility/Input Monitoring access. Closed-Lid Mode uses fixed `/usr/bin/pmset` commands and verifies the macOS power state after changing it.

See `docs/privileged-helper-security.md` for the detailed security boundary, privileged install path, build requirements, and rollback details.

## Safety

Closed-lid mode disables sleep at the power-management level. Use it on a stable, ventilated surface. Do not put a closed Mac in a bag while this is enabled, and turn it off before traveling or leaving the machine unattended on battery power.

Battery Safety does not force an immediate sleep command. It releases RoamVibing's wake blockers, and if Closed-Lid Mode is active it disables the closed-lid bypass, so macOS can sleep normally.

Instant Lock on Activity uses macOS clamshell state when available, plus aggregate idle-time counters as a fallback. It does not read keystrokes, capture mouse events, use an event tap, or request Accessibility/Input Monitoring permissions.

Mute on Lid Close uses CoreAudio to mute currently active output devices plus the default output routes. It does not change microphone input, record audio, use Accessibility permissions, use event taps, or contact the network.
