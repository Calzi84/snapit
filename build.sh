#!/bin/bash
# Baut "Snap it.app" aus den Swift-Quellen.
#   ./build.sh            baut nach build/Snap it.app
#   ./build.sh install    baut und legt die App in /Applications ab
set -euo pipefail
cd "$(dirname "$0")"

NAME="Snap it"
BUNDLE_ID="de.navion.snapit"
VERSION="$(cat VERSION)"
# Adresse der version.json im Repo — wird beim Update abgefragt.
UPDATE_URL="${SNAPIT_UPDATE_URL:-}"

echo "▸ Kompiliere ($VERSION) …"
swift build -c release

BIN=".build/release/SnapIt"
APP="build/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ Zeichne Icon …"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
"$BIN" --iconset "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cp "$BIN" "$APP/Contents/MacOS/SnapIt"

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$NAME</string>
    <key>CFBundleDisplayName</key>       <string>$NAME</string>
    <key>CFBundleExecutable</key>        <string>SnapIt</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>SnapItUpdateURL</key>           <string>$UPDATE_URL</string>
    <key>NSHumanReadableCopyright</key>  <string>Navion GmbH</string>
</dict>
</plist>
PLIST

# Ad-hoc-Signatur: ohne sie beanstandet Gatekeeper die App bei jedem Start.
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  (Signieren übersprungen)"

echo "▸ Fertig: $APP"

if [ "${1:-}" = "install" ]; then
    echo "▸ Installiere nach /Applications …"
    pkill -f "/Applications/$NAME.app" 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/$NAME.app"
    cp -R "$APP" "/Applications/$NAME.app"
    open "/Applications/$NAME.app"
    echo "▸ Snap it läuft jetzt in der Menüleiste."
fi
