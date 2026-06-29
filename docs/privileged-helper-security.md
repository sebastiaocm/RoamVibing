# Privileged Helper Security

RoamVibing's Touch ID Helper is optional. It exists only to let Closed-Lid Mode changes happen after macOS device-owner approval, which can offer Touch ID first and fall back to the Mac password after the helper is installed and approved.

## Command Scope

The helper only runs these power-management commands:

- enable: `/usr/bin/pmset -a disablesleep 1`
- disable: `/usr/bin/pmset -a disablesleep 0`

The helper accepts only enable or disable. It does not accept arbitrary commands, executable paths, URLs, scripts, environment changes, or additional arguments.

## Boundaries

- No shell.
- No `osascript`.
- No `sudo`.
- No network client or server APIs.
- No remote-control APIs.
- No event taps.
- No Accessibility or Input Monitoring permissions.
- XPC clients must match the RoamVibing app code-signing requirement.
- The app verifies the helper code-signing requirement before connecting.

## Build and Release

The default build does not package the helper and uses the administrator-password flow.

The helper is packaged only when the build is run with `ROAMVIBING_ENABLE_PRIVILEGED_HELPER=1`. Helper-enabled builds also require `ROAMVIBING_SIGN_IDENTITY` and `ROAMVIBING_NOTARY_KEYCHAIN_PROFILE` so the app and helper can be signed, submitted with `notarytool`, stapled with `stapler`, checked with `spctl`, and shipped notarized and stapled.

Local-only helper testing can skip notarization with `ROAMVIBING_SKIP_NOTARIZATION=1`. That path still requires `ROAMVIBING_SIGN_IDENTITY`, signs the app and helper, and packages the helper only when `ROAMVIBING_ENABLE_PRIVILEGED_HELPER=1`, but it must not be distributed.

Local-only helper testing can also be installed manually when `SMAppService` refuses an Apple Development build:

```sh
./scripts/install-local-touchid-helper.sh
```

That script copies the signed helper to `/Library/PrivilegedHelperTools`, writes a fixed LaunchDaemon plist to `/Library/LaunchDaemons`, bootstraps the fixed Mach service, and enables `UsePrivilegedHelper` for the app. It asks for administrator approval once. The XPC connection still enforces the RoamVibing code-signing requirements before the helper accepts any request.

Do not ship an ad-hoc signed helper as a security feature.

## Install Location

Helper-enabled builds must be installed under `/Applications`. RoamVibing refuses helper registration from `~/Applications`, `dist/`, `/private/tmp`, symlink escapes, or any other path outside `/Applications`.

## Rollback

1. Turn `Use Touch ID Helper` off.
2. Choose `Uninstall Touch ID Helper`.
3. Rebuild or reinstall RoamVibing without `ROAMVIBING_ENABLE_PRIVILEGED_HELPER=1`.

For a local helper installed with `scripts/install-local-touchid-helper.sh`, run:

```sh
./scripts/uninstall-local-touchid-helper.sh
```

That script first sets `/usr/bin/pmset -a disablesleep 0`, then unloads and removes the local LaunchDaemon files, and disables `UsePrivilegedHelper`.

After rollback, Closed-Lid Mode uses the administrator-password flow.

When the helper is enabled, uninstall disables Closed-Lid Mode before unregistering the helper and verifies macOS reports the bypass disabled. If that safety disable or verification fails, RoamVibing leaves the helper registered and shows an error. A pending or unapproved helper is not serving XPC yet, so rollback unregisters it without trying helper XPC first.
