#!/bin/bash
# mac-screenshots-to-photos — fast mode installer
# Builds screenshot-sync (FSEvents watcher) and runs it as a LaunchAgent:
# screenshot -> clipboard in ~0.1 s -> Photos -> source file deleted.
set -euo pipefail
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8   # non-ASCII folder names over ssh

WATCH_DIR="${1:-$HOME/Pictures/Screenshots Auto-Import}"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL=com.gnehiur.screenshot-sync
APP="$HOME/Applications/screenshot-sync.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/screenshot-sync.log"

echo "== mac-screenshots-to-photos (fast mode) =="
echo "Watched folder will be: $WATCH_DIR"
echo

# --- 1. Build ----------------------------------------------------------------
command -v swiftc >/dev/null || { echo "swiftc not found: run 'xcode-select --install' first."; exit 1; }
BUILD="$(mktemp -d)/screenshot-sync.app"
mkdir -p "$BUILD/Contents/MacOS"
cp "$SRC_DIR/Info.plist" "$BUILD/Contents/"
swiftc -O -target "$(uname -m)-apple-macos14" -o "$BUILD/Contents/MacOS/screenshot-sync" "$SRC_DIR/main.swift"
codesign --force -s - "$BUILD" 2>/dev/null
echo "[1/4] Built screenshot-sync $(defaults read "$BUILD/Contents/Info.plist" CFBundleShortVersionString)."

# --- 2. Screenshot settings --------------------------------------------------
mkdir -p "$WATCH_DIR"
defaults write com.apple.screencapture location "$WATCH_DIR"
# The floating thumbnail holds the file back ~5 s; without it the file lands at once.
defaults write com.apple.screencapture show-thumbnail -bool false
killall SystemUIServer 2>/dev/null || true
echo "[2/4] Screenshots save to the watched folder; floating thumbnail off."

# --- 3. Retire the classic Folder Action on this folder (avoid double import) --
if osascript -e "tell application \"System Events\" to set enabled of (every folder action whose path is \"$WATCH_DIR\") to false" >/dev/null 2>&1; then
	echo "[3/4] Classic Folder Action on this folder (if any) disabled."
else
	echo "[3/4] Could not reach System Events; if the classic mode watches this folder,"
	echo "      run ../uninstall.sh \"$WATCH_DIR\" so screenshots are not imported twice."
fi

# --- 4. Install app + LaunchAgent -------------------------------------------
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$APP" && cp -R "$BUILD" "$APP" && rm -rf "$(dirname "$BUILD")"
cat > "$PLIST" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key>
	<array><string>$APP/Contents/MacOS/screenshot-sync</string><string>$WATCH_DIR</string></array>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
	<key>ProcessType</key><string>Interactive</string>
	<key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
P
launchctl bootstrap "gui/$UID" "$PLIST"
echo "[4/4] Running as LaunchAgent $LABEL (log: $LOG)."

echo
echo "Done. macOS will ask once to let screenshot-sync add to Photos — click Allow."
echo "Take a screenshot, then Cmd+V anywhere: the image should already be there."
