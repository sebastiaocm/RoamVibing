#!/usr/bin/env bash
set -euo pipefail

HELPER_LABEL="com.local.RoamVibing.PrivilegedHelper"
HELPER_EXECUTABLE_NAME="RoamVibingPrivilegedHelper"
TARGET_HELPER="/Library/PrivilegedHelperTools/$HELPER_EXECUTABLE_NAME"
TARGET_PLIST="/Library/LaunchDaemons/$HELPER_LABEL.plist"
ROOT_SCRIPT="$(mktemp -t roamvibing-helper-uninstall.XXXXXX)"

cleanup() {
  rm -f "$ROOT_SCRIPT"
}
trap cleanup EXIT

cat > "$ROOT_SCRIPT" <<ROOT_SCRIPT
#!/bin/sh
set -eu
/usr/bin/pmset -a disablesleep 0 2>/dev/null || true
/bin/launchctl bootout system/$HELPER_LABEL 2>/dev/null || true
/bin/rm -f "$TARGET_HELPER" "$TARGET_PLIST"
ROOT_SCRIPT
chmod 700 "$ROOT_SCRIPT"

/usr/bin/osascript - "$ROOT_SCRIPT" <<'APPLESCRIPT'
on run argv
	do shell script quoted form of item 1 of argv with administrator privileges
end run
APPLESCRIPT

defaults write com.local.RoamVibing UsePrivilegedHelper -bool false

echo "Uninstalled local Touch ID helper and disabled Closed-Lid Mode."
