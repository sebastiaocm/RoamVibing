#!/usr/bin/env bash
set -euo pipefail

APP_PATH="/Applications/RoamVibing.app"
HELPER_LABEL="com.local.RoamVibing.PrivilegedHelper"
HELPER_EXECUTABLE_NAME="RoamVibingPrivilegedHelper"
BUNDLED_HELPER="$APP_PATH/Contents/Library/LaunchDaemons/$HELPER_EXECUTABLE_NAME"
TARGET_HELPER="/Library/PrivilegedHelperTools/$HELPER_EXECUTABLE_NAME"
TARGET_PLIST="/Library/LaunchDaemons/$HELPER_LABEL.plist"
TMP_PLIST="$(mktemp -t roamvibing-helper-plist.XXXXXX)"
ROOT_SCRIPT="$(mktemp -t roamvibing-helper-install.XXXXXX)"

cleanup() {
  rm -f "$TMP_PLIST" "$ROOT_SCRIPT"
}
trap cleanup EXIT

if [[ $# -ne 0 ]]; then
  echo "Usage: $0" >&2
  echo "Install RoamVibing at $APP_PATH before running this helper installer." >&2
  exit 2
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected RoamVibing at $APP_PATH" >&2
  exit 2
fi

if [[ ! -x "$BUNDLED_HELPER" ]]; then
  echo "Expected helper executable at $BUNDLED_HELPER" >&2
  echo "Build with ROAMVIBING_ENABLE_PRIVILEGED_HELPER=1 first." >&2
  exit 2
fi

codesign --verify --deep --strict "$APP_PATH"
codesign --verify --strict "$BUNDLED_HELPER"

cat > "$TMP_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$HELPER_LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$TARGET_HELPER</string>
	</array>
	<key>MachServices</key>
	<dict>
		<key>$HELPER_LABEL</key>
		<true/>
	</dict>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
PLIST
plutil -lint "$TMP_PLIST" >/dev/null

cat > "$ROOT_SCRIPT" <<'ROOT_SCRIPT'
#!/bin/sh
set -eu
BUNDLED_HELPER="$1"
TARGET_HELPER="$2"
TMP_PLIST="$3"
TARGET_PLIST="$4"
HELPER_LABEL="$5"

/bin/launchctl bootout "system/$HELPER_LABEL" 2>/dev/null || true
/bin/mkdir -p /Library/PrivilegedHelperTools
/usr/bin/install -o root -g wheel -m 755 "$BUNDLED_HELPER" "$TARGET_HELPER"
/usr/bin/install -o root -g wheel -m 644 "$TMP_PLIST" "$TARGET_PLIST"
/bin/launchctl bootstrap system "$TARGET_PLIST"
/bin/launchctl enable "system/$HELPER_LABEL"
ROOT_SCRIPT
chmod 700 "$ROOT_SCRIPT"

/usr/bin/osascript - "$ROOT_SCRIPT" "$BUNDLED_HELPER" "$TARGET_HELPER" "$TMP_PLIST" "$TARGET_PLIST" "$HELPER_LABEL" <<'APPLESCRIPT'
on run argv
	set command to quoted form of item 1 of argv & " " & quoted form of item 2 of argv & " " & quoted form of item 3 of argv & " " & quoted form of item 4 of argv & " " & quoted form of item 5 of argv & " " & quoted form of item 6 of argv
	do shell script command with administrator privileges
end run
APPLESCRIPT

defaults write com.local.RoamVibing UsePrivilegedHelper -bool true
launchctl print "system/$HELPER_LABEL" >/dev/null

echo "Installed local Touch ID helper."
echo "Open RoamVibing and choose Start Closed-Lid Mode. macOS should offer Touch ID when available."
