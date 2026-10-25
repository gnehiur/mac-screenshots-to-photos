#!/bin/bash
# mac-screenshots-to-photos — fast mode uninstaller
# Stops and removes screenshot-sync. Leaves the screenshot folder and its
# contents alone; re-run the classic ../install.sh to go back to Folder Actions.
set -euo pipefail

LABEL=com.gnehiur.screenshot-sync
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/screenshot-sync.app"
defaults delete com.apple.screencapture show-thumbnail 2>/dev/null || true

echo "Fast mode uninstalled. Screenshots still save to: $(defaults read com.apple.screencapture location 2>/dev/null || echo '~/Desktop')"
echo "Restore the classic pipeline with ./install.sh in the repo root, or ./uninstall.sh there to go fully back to defaults."
