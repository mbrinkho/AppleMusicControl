#!/bin/bash
# Builds AppleMusicControl.pkg — a double-click installer for macOS
set -euo pipefail

BUNDLE_ID="com.applemusiccontrol"
VERSION="1.0"
INSTALL_LOCATION="/Library/Application Support/AppleMusicControl"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.pkg-build"
PAYLOAD_DIR="$BUILD_DIR/payload"
SCRIPTS_DIR="$BUILD_DIR/scripts"
OUTPUT="$SCRIPT_DIR/AppleMusicControl.pkg"

echo "Building AppleMusicControl.pkg…"
rm -rf "$BUILD_DIR"
mkdir -p "$PAYLOAD_DIR"
mkdir -p "$SCRIPTS_DIR"

# ── Payload ────────────────────────────────────────────────────────────────────
cp "$SCRIPT_DIR/server.py" "$PAYLOAD_DIR/"
cp -r "$SCRIPT_DIR/public"  "$PAYLOAD_DIR/"
echo "  ✓ Payload staged → $INSTALL_LOCATION"

# ── postinstall ────────────────────────────────────────────────────────────────
# Single-quoted heredoc — no variable expansion, no escaping needed.
# Constants are hardcoded since they never change.
cat > "$SCRIPTS_DIR/postinstall" <<'SCRIPT'
#!/bin/bash
INSTALL_DIR="/Library/Application Support/AppleMusicControl"
SRV_BUNDLE_ID="com.applemusiccontrol.server"

# ── Identify the real (non-root) user ─────────────────────────────────────────
REAL_USER=$(stat -f '%Su' /dev/console 2>/dev/null || true)
if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    REAL_USER=$(ls -ld /Users/*/Desktop 2>/dev/null | awk '{print $3}' | grep -v root | head -1)
fi
REAL_HOME=$(dscl . -read "/Users/$REAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
[ -z "$REAL_HOME" ] && REAL_HOME="/Users/$REAL_USER"

AGENT_PLIST="$REAL_HOME/Library/LaunchAgents/$SRV_BUNDLE_ID.plist"
APP_PATH="$REAL_HOME/Applications/Apple Music Control.app"

# ── Detect Python ──────────────────────────────────────────────────────────────
PYTHON="/usr/bin/python3"
for candidate in /usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    [ -x "$candidate" ] && PYTHON="$candidate" && break
done

# ── Ensure installed files are readable by all users ──────────────────────────
chmod -R a+rX "$INSTALL_DIR" 2>/dev/null || true

# ── LaunchAgent plist ──────────────────────────────────────────────────────────
mkdir -p "$REAL_HOME/Library/LaunchAgents"
cat > "$AGENT_PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$SRV_BUNDLE_ID</string>
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
    <string>$REAL_HOME/Library/Logs/AppleMusicControl.log</string>
    <key>StandardErrorPath</key>
    <string>$REAL_HOME/Library/Logs/AppleMusicControl.log</string>
</dict>
</plist>
PLIST
chown "$REAL_USER" "$AGENT_PLIST" 2>/dev/null || true

# ── .app bundle ────────────────────────────────────────────────────────────────
mkdir -p "$APP_PATH/Contents/MacOS"

cat > "$APP_PATH/Contents/MacOS/AppleMusicControl" << 'LAUNCHER'
#!/bin/bash
PLIST="$HOME/Library/LaunchAgents/com.applemusiccontrol.server.plist"
INSTALL_DIR="/Library/Application Support/AppleMusicControl"

server_running() {
    curl -sf http://localhost:3000/api/now-playing >/dev/null 2>&1
}

if ! server_running; then
    if [ -f "$PLIST" ]; then
        launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || \
        launchctl load "$PLIST" 2>/dev/null || true
        sleep 1
    fi
    if ! server_running; then
        /usr/bin/python3 "$INSTALL_DIR/server.py" &>/dev/null &
        sleep 1
    fi
fi

open "http://localhost:3000"
LAUNCHER
chmod +x "$APP_PATH/Contents/MacOS/AppleMusicControl"

cat > "$APP_PATH/Contents/Info.plist" << 'INFOPLIST'
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
</dict>
</plist>
INFOPLIST
chown -R "$REAL_USER" "$APP_PATH" 2>/dev/null || true

exit 0
SCRIPT
chmod +x "$SCRIPTS_DIR/postinstall"

# ── preinstall: stop any running instance ──────────────────────────────────────
cat > "$SCRIPTS_DIR/preinstall" <<'SCRIPT'
#!/bin/bash
REAL_USER=$(stat -f '%Su' /dev/console 2>/dev/null || true)
if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
    USER_ID=$(id -u "$REAL_USER" 2>/dev/null || true)
    REAL_HOME=$(dscl . -read "/Users/$REAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    PLIST="$REAL_HOME/Library/LaunchAgents/com.applemusiccontrol.server.plist"
    if [ -f "$PLIST" ] && [ -n "$USER_ID" ]; then
        launchctl bootout "gui/$USER_ID" "$PLIST" 2>/dev/null || \
        launchctl unload "$PLIST" 2>/dev/null || true
    fi
fi
exit 0
SCRIPT
chmod +x "$SCRIPTS_DIR/preinstall"
echo "  ✓ Scripts created"

# ── Component package ──────────────────────────────────────────────────────────
COMPONENT_PKG="$BUILD_DIR/component.pkg"
pkgbuild \
    --root "$PAYLOAD_DIR" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --install-location "$INSTALL_LOCATION" \
    --scripts "$SCRIPTS_DIR" \
    "$COMPONENT_PKG"
echo "  ✓ Component package built"

# ── Distribution XML ───────────────────────────────────────────────────────────
DIST_XML="$BUILD_DIR/distribution.xml"
cat > "$DIST_XML" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<installer-gui-script minSpecVersion="1">
    <title>Apple Music Control</title>
    <welcome file="welcome.html" mime-type="text/html"/>
    <options customize="never" require-scripts="true" rootVolumeOnly="true"/>
    <pkg-ref id="$BUNDLE_ID"/>
    <choices-outline>
        <line choice="default">
            <line choice="$BUNDLE_ID"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="$BUNDLE_ID" visible="false">
        <pkg-ref id="$BUNDLE_ID"/>
    </choice>
    <pkg-ref id="$BUNDLE_ID" version="$VERSION" onConclusion="none">component.pkg</pkg-ref>
</installer-gui-script>
XML

cat > "$BUILD_DIR/welcome.html" <<HTML
<html><body style="font-family:-apple-system,sans-serif;padding:16px">
<h2>Apple Music Control</h2>
<p>This installs a lightweight local web server that lets you control
Apple Music from any browser on this machine.</p>
<p>After installation:</p>
<ul>
  <li>An <strong>Apple Music Control</strong> app appears in ~/Applications</li>
  <li>Double-click it to open the controller — the server starts automatically</li>
  <li>The server also starts automatically on every login</li>
</ul>
<p><strong>Requires:</strong> macOS 12 or later and Apple Music.</p>
<p><strong>Python 3 is required.</strong> If not already installed, open Terminal and run:<br>
<code>xcode-select --install</code><br>
then click <em>Install</em> in the dialog before running this installer.</p>
</body></html>
HTML

# ── Final product package ──────────────────────────────────────────────────────
productbuild \
    --distribution "$DIST_XML" \
    --package-path "$BUILD_DIR" \
    --resources "$BUILD_DIR" \
    "$OUTPUT"

rm -rf "$BUILD_DIR"
echo "  ✓ Installer built"
echo ""
echo "→  $OUTPUT"
echo ""
echo "Double-click AppleMusicControl.pkg to install."
