#!/bin/bash
# mac-screenshots-to-photos uninstaller
# Restores default screenshot behavior. Leaves the watched folder
# (and anything still in it) untouched.
set -euo pipefail

WATCH_DIR="${1:-$HOME/Pictures/Screenshots Auto-Import}"
FA_SCRIPTS="$HOME/Library/Scripts/Folder Action Scripts"
SCPT_NAME="screenshots-to-photos.scpt"
FA_NAME="$(basename "$WATCH_DIR")"

# Detach the Folder Action
osascript <<EOF2 || true
tell application "System Events"
	delete (every folder action whose path is "$WATCH_DIR")
end tell
EOF2

# Remove the compiled script
rm -f "$FA_SCRIPTS/$SCPT_NAME"

# Screenshots back to the Desktop (macOS default)
defaults write com.apple.screencapture location "$HOME/Desktop"
killall SystemUIServer 2>/dev/null || true

echo "Uninstalled. Screenshots save to the Desktop again."
echo "Watched folder kept as-is: $WATCH_DIR"
