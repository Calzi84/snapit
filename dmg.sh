#!/bin/bash
# Packt die gebaute App in ein Disk-Image zum Hineinziehen nach /Applications.
#   ./dmg.sh          nutzt build/Snap it.app
set -euo pipefail
cd "$(dirname "$0")"

NAME="Snap it"
VERSION="$(cat VERSION)"
APP="build/$NAME.app"

if [ ! -d "$APP" ]; then
    echo "✗ $APP fehlt — erst ./build.sh ausführen." >&2
    exit 1
fi

BUEHNE="$(mktemp -d)"
trap 'rm -rf "$BUEHNE"' EXIT

cp -R "$APP" "$BUEHNE/"
ln -s /Applications "$BUEHNE/Applications"

# Kurzanleitung mit ins Image, für den Fall der Gatekeeper-Rückfrage
cat > "$BUEHNE/Bitte lesen.txt" << 'TEXT'
Snap it installieren
====================

1. Snap it in den Ordner "Applications" ziehen.
2. Snap it öffnen.

Falls macOS meldet, die App könne nicht auf Schadsoftware geprüft werden:

  Systemeinstellungen  →  Datenschutz & Sicherheit
  → ganz nach unten scrollen  →  "Dennoch öffnen"

Das ist einmalig nötig, weil die App aus dem eigenen Haus stammt und nicht
über den App Store verteilt wird. Bei späteren Updates fragt macOS nicht
mehr — die App aktualisiert sich dann selbst.

Ohne diesen Schritt geht es mit dem Installationsbefehl aus der Anleitung.

Nach dem ersten Start
---------------------
Das Symbol sitzt oben rechts in der Menüleiste.
Ausschnitt aufnehmen: Cmd-Shift-2

Beim ersten Mal fragt macOS nach der Freigabe zur Bildschirmaufnahme.
Einmal erlauben, danach nie wieder.
TEXT

ZIEL="build/SnapIt-$VERSION.dmg"
rm -f "$ZIEL"
hdiutil create -volname "$NAME" -srcfolder "$BUEHNE" -ov -format UDZO -quiet "$ZIEL"
echo "▸ Fertig: $ZIEL  ($(du -h "$ZIEL" | cut -f1))"
