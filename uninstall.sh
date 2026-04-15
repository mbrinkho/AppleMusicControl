#!/bin/bash
# Apple Music Control — uninstaller
set -euo pipefail

BUNDLE_ID="com.applemusiccontrol.server"
INSTALL_DIR="$HOME/Library/Application Support/AppleMusicControl"
AGENT_PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
APP_PATH="$HOME/Applications/Apple Music Control.app"

echo "Uninstalling Apple Music Control…"

# Stop and unload the server
if [ -f "$AGENT_PLIST" ]; then
    launchctl unload "$AGENT_PLIST" 2>/dev/null || true
    rm -f "$AGENT_PLIST"
    echo "  ✓ LaunchAgent removed"
fi

# Remove app
if [ -d "$APP_PATH" ]; then
    rm -rf "$APP_PATH"
    echo "  ✓ App removed"
fi

# Remove server files
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "  ✓ Server files removed"
fi

echo ""
echo "Apple Music Control has been uninstalled."
