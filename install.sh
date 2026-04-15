#!/bin/bash
# Apple Music Control — one-command installer
set -euo pipefail

BUNDLE_ID="com.applemusiccontrol.server"
INSTALL_DIR="$HOME/Library/Application Support/AppleMusicControl"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_PLIST="$AGENT_DIR/$BUNDLE_ID.plist"
APP_DIR="$HOME/Applications"
APP_PATH="$APP_DIR/Apple Music Control.app"
PYTHON="$(which python3 2>/dev/null || echo /usr/bin/python3)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing Apple Music Control…"

# ── 1. Copy server files ───────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/server.py" "$INSTALL_DIR/server.py"
cp -r "$SCRIPT_DIR/public"  "$INSTALL_DIR/public"
echo "  ✓ Files copied to $INSTALL_DIR"

# ── 2. LaunchAgent (auto-start on login) ──────────────────────────────────────
mkdir -p "$AGENT_DIR"
cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON</string>
        <string>$INSTALL_DIR/server.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$INSTALL_DIR/server.log</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/server.log</string>
</dict>
</plist>
PLIST
echo "  ✓ LaunchAgent created"

# Reload if already registered; otherwise load fresh
launchctl unload "$AGENT_PLIST" 2>/dev/null || true
launchctl load "$AGENT_PLIST"
echo "  ✓ Server started (runs on login automatically)"

# ── 3. .app bundle ────────────────────────────────────────────────────────────
mkdir -p "$APP_PATH/Contents/MacOS"

cat > "$APP_PATH/Contents/MacOS/AppleMusicControl" <<'LAUNCHER'
#!/bin/bash
# Start the server if it isn't already running
launchctl start com.applemusiccontrol.server 2>/dev/null || true
sleep 0.4
open "http://localhost:3000"
LAUNCHER
chmod +x "$APP_PATH/Contents/MacOS/AppleMusicControl"

cat > "$APP_PATH/Contents/Info.plist" <<'INFOPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AppleMusicControl</string>
    <key>CFBundleIdentifier</key>
    <string>com.applemusiccontrol</string>
    <key>CFBundleName</key>
    <string>Apple Music Control</string>
    <key>CFBundleDisplayName</key>
    <string>Apple Music Control</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
INFOPLIST
echo "  ✓ App created at $APP_PATH"

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
echo "Done! Server is running at http://localhost:3000"
echo "Double-click 'Apple Music Control' in ~/Applications to open the controller."
echo ""
echo "To uninstall: bash $(dirname "$0")/uninstall.sh"
