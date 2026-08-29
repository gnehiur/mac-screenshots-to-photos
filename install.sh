#!/bin/bash
# mac-screenshots-to-photos installer
# Makes macOS screenshots behave like iPhone screenshots:
# every screenshot lands in Photos (and iCloud), not on your Desktop.
set -euo pipefail

WATCH_DIR="${1:-$HOME/Pictures/Screenshots Auto-Import}"
FA_SCRIPTS="$HOME/Library/Scripts/Folder Action Scripts"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
SCPT_NAME="screenshots-to-photos.scpt"

echo "== mac-screenshots-to-photos =="
echo "Watched folder will be: $WATCH_DIR"
echo

# --- Critical precondition -------------------------------------------------
# If Photos imports "by reference" (checkbox off), it only stores a pointer
# to the file. Auto-deleting the source would then instantly orphan the photo.
# Copy-mode MUST be on before we enable delete-after-import.
cat <<'EOF'
REQUIRED FIRST: open Photos > Settings... > General and make sure
    "Importing: Copy items to the Photos library"   is CHECKED.

Why: with that box unchecked, Photos stores a *reference* (a note that
says "the file lives over there") instead of a real copy. This pipeline
deletes the source file after import - deleting the original behind a
reference kills the photo. With the box checked, Photos owns a real copy
and the source file is safely disposable.
EOF
read -r -p "Is that box checked right now? [y/N] " ans
case "$ans" in
	y|Y|yes|YES) ;;
	*) echo "Please enable it in Photos first, then re-run this installer."; exit 1 ;;
esac

# --- 1. Watched folder + compiled Folder Action script ---------------------
mkdir -p "$WATCH_DIR" "$FA_SCRIPTS"
osacompile -o "$FA_SCRIPTS/$SCPT_NAME" "$SRC_DIR/screenshots-to-photos.applescript"
echo "[1/3] Folder Action script installed: $FA_SCRIPTS/$SCPT_NAME"

# --- 2. Point macOS screenshots at the watched folder ----------------------
defaults write com.apple.screencapture location "$WATCH_DIR"
killall SystemUIServer 2>/dev/null || true
echo "[2/3] Screenshot save location set to the watched folder."

# --- 3. Attach the Folder Action -------------------------------------------
# First run will trigger macOS permission prompts (System Events, and later
# Photos when the first screenshot imports). Approve them - each is asked once.
FA_NAME="$(basename "$WATCH_DIR")"
osascript <<EOF2
tell application "System Events"
	set folder actions enabled to true
	if (count of (folder actions whose path is "$WATCH_DIR")) is 0 then
		make new folder action at end of folder actions with properties {path:"$WATCH_DIR"}
	end if
	tell folder action "$FA_NAME"
		delete (every script whose name is "$SCPT_NAME")
		make new script at end of scripts with properties {name:"$SCPT_NAME"}
	end tell
end tell
EOF2
echo "[3/3] Folder Action attached."

echo
echo "Done. Take a screenshot (Cmd+Shift+3/4) to test:"
echo "  - it should appear in Photos within seconds"
echo "  - the file in '$WATCH_DIR' should delete itself"
echo "If macOS asks for permission to control 'Photos', click Allow."
