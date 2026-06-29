#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/RoamVibing.app"
ZIP_FILE="$ROOT_DIR/dist/RoamVibing.app.zip"
NOTARY_ZIP_FILE="$ROOT_DIR/dist/RoamVibing-notary.zip"
LEGACY_APP_DIR="$ROOT_DIR/dist/LidAwake.app"
LEGACY_ZIP_FILE="$ROOT_DIR/dist/LidAwake.app.zip"
LEGACY_AGENTCARRY_APP_DIR="$ROOT_DIR/dist/AgentCarry.app"
LEGACY_AGENTCARRY_ZIP_FILE="$ROOT_DIR/dist/AgentCarry.app.zip"
STAGING_APP="/private/tmp/RoamVibingBuild/RoamVibing.app"
STAGING_CONTENTS_DIR="$STAGING_APP/Contents"
VERIFY_DIR="/private/tmp/RoamVibingZipVerify"
VERIFY_APP="$VERIFY_DIR/RoamVibing.app"
ENABLE_PRIVILEGED_HELPER="${ROAMVIBING_ENABLE_PRIVILEGED_HELPER:-0}"
ROAMVIBING_SIGN_IDENTITY="${ROAMVIBING_SIGN_IDENTITY:-}"
ROAMVIBING_NOTARY_KEYCHAIN_PROFILE="${ROAMVIBING_NOTARY_KEYCHAIN_PROFILE:-}"
ROAMVIBING_SKIP_NOTARIZATION="${ROAMVIBING_SKIP_NOTARIZATION:-0}"
HELPER_EXECUTABLE_NAME="RoamVibingPrivilegedHelper"
HELPER_LABEL="com.local.RoamVibing.PrivilegedHelper"
LAUNCH_DAEMON_PLIST="$ROOT_DIR/Resources/LaunchDaemons/$HELPER_LABEL.plist"
HELPER_INSTALL_APP="/Applications/RoamVibing.app"
HELPER_STAGING_DAEMON_DIR="$STAGING_APP/Contents/Library/LaunchDaemons"

cd "$ROOT_DIR"

if [[ "$ENABLE_PRIVILEGED_HELPER" == "1" ]]; then
  if [[ -z "$ROAMVIBING_SIGN_IDENTITY" ]]; then
    echo "ROAMVIBING_SIGN_IDENTITY is required when ROAMVIBING_ENABLE_PRIVILEGED_HELPER=1" >&2
    exit 2
  fi

  if [[ "$ROAMVIBING_SKIP_NOTARIZATION" != "1" && -z "$ROAMVIBING_NOTARY_KEYCHAIN_PROFILE" ]]; then
    echo "ROAMVIBING_NOTARY_KEYCHAIN_PROFILE is required when ROAMVIBING_ENABLE_PRIVILEGED_HELPER=1" >&2
    echo "For local-only helper testing, set ROAMVIBING_SKIP_NOTARIZATION=1. Do not distribute that build." >&2
    exit 2
  fi
fi

swift build -c release --product RoamVibing
if [[ "$ENABLE_PRIVILEGED_HELPER" == "1" ]]; then
  swift build -c release --product "$HELPER_EXECUTABLE_NAME"
fi
swift "$ROOT_DIR/scripts/generate-icons.swift" "$ROOT_DIR/Resources"
iconutil -c icns "$ROOT_DIR/Resources/RoamVibingIcon.iconset" -o "$ROOT_DIR/Resources/RoamVibingIcon.icns"

rm -rf "$STAGING_APP" "$APP_DIR" "$VERIFY_DIR" "$LEGACY_APP_DIR" "$LEGACY_AGENTCARRY_APP_DIR"
rm -f "$ZIP_FILE" "$NOTARY_ZIP_FILE" "$LEGACY_ZIP_FILE" "$LEGACY_AGENTCARRY_ZIP_FILE"
mkdir -p \
  "$STAGING_CONTENTS_DIR/MacOS" \
  "$STAGING_CONTENTS_DIR/Resources" \
  "$ROOT_DIR/dist"
cp -f "$ROOT_DIR/.build/release/RoamVibing" "$STAGING_CONTENTS_DIR/MacOS/RoamVibing"
cp -f "$ROOT_DIR/Resources/Info.plist" "$STAGING_CONTENTS_DIR/Info.plist"
cp -f "$ROOT_DIR/Resources/RoamVibingIcon.icns" "$STAGING_CONTENTS_DIR/Resources/RoamVibingIcon.icns"
cp -f "$ROOT_DIR/Resources/RoamVibingStatusTemplateOn.png" "$STAGING_CONTENTS_DIR/Resources/RoamVibingStatusTemplateOn.png"
cp -f "$ROOT_DIR/Resources/RoamVibingStatusTemplateOff.png" "$STAGING_CONTENTS_DIR/Resources/RoamVibingStatusTemplateOff.png"
cp -f "$ROOT_DIR/Resources/RoamVibingLogo.svg" "$STAGING_CONTENTS_DIR/Resources/RoamVibingLogo.svg"

if [[ "$ENABLE_PRIVILEGED_HELPER" == "1" ]]; then
  mkdir -p "$HELPER_STAGING_DAEMON_DIR"
  cp -f "$ROOT_DIR/.build/release/$HELPER_EXECUTABLE_NAME" "$HELPER_STAGING_DAEMON_DIR/$HELPER_EXECUTABLE_NAME"
  cp -f "$LAUNCH_DAEMON_PLIST" "$HELPER_STAGING_DAEMON_DIR/$HELPER_LABEL.plist"
fi

xattr -cr "$STAGING_APP"
if [[ "$ENABLE_PRIVILEGED_HELPER" == "1" ]]; then
  codesign --force --options runtime --sign "$ROAMVIBING_SIGN_IDENTITY" --identifier "$HELPER_LABEL" "$HELPER_STAGING_DAEMON_DIR/$HELPER_EXECUTABLE_NAME"
  codesign --force --options runtime --sign "$ROAMVIBING_SIGN_IDENTITY" "$STAGING_APP"
  codesign --verify --deep --strict "$STAGING_APP"
  if [[ "$ROAMVIBING_SKIP_NOTARIZATION" == "1" ]]; then
    echo "Skipping notarization for a local-only helper build. Do not distribute this build."
  else
    ditto -c -k --keepParent --norsrc "$STAGING_APP" "$NOTARY_ZIP_FILE"
    xcrun notarytool submit "$NOTARY_ZIP_FILE" --keychain-profile "$ROAMVIBING_NOTARY_KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$STAGING_APP"
    spctl -a -vv --type execute "$STAGING_APP"
  fi
  echo "Helper-enabled builds must be installed in /Applications before helper registration: $HELPER_INSTALL_APP"
else
  codesign --force --sign - "$STAGING_APP"
  codesign --verify --deep --strict "$STAGING_APP"
fi
ditto --norsrc "$STAGING_APP" "$APP_DIR"
xattr -cr "$APP_DIR"
xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
codesign --verify --deep --strict "$APP_DIR"
ditto -c -k --keepParent --norsrc "$STAGING_APP" "$ZIP_FILE"
mkdir -p "$VERIFY_DIR"
ditto -x -k "$ZIP_FILE" "$VERIFY_DIR"
codesign --verify --deep --strict "$VERIFY_APP"

echo "$APP_DIR"
echo "$ZIP_FILE"
if [[ "$ENABLE_PRIVILEGED_HELPER" == "1" && "$ROAMVIBING_SKIP_NOTARIZATION" != "1" ]]; then
  echo "$NOTARY_ZIP_FILE"
fi
