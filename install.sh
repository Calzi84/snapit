#!/bin/bash
# Installiert Snap it auf diesem Mac und aktualisiert eine vorhandene Fassung.
#
#   curl -fsSL https://raw.githubusercontent.com/Calzi84/snapit/main/install.sh | bash
#
# Das Archiv wird mit curl geladen. Anders als ein Download über den Browser
# bekommt es damit kein Quarantäne-Merkmal, es gibt also keine Gatekeeper-Rückfrage.
set -euo pipefail

REPO="Calzi84/snapit"
NAME="Snap it"
ERWARTETE_SIGNATUR="Navion Snap it"

echo "▸ Suche die neueste Fassung …"
INFO="$(curl -fsSL "https://raw.githubusercontent.com/$REPO/main/version.json")"
VERSION="$(printf '%s' "$INFO" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
URL="$(printf '%s' "$INFO" | sed -n 's/.*"download"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

if [ -z "$VERSION" ] || [ -z "$URL" ]; then
    echo "✗ Konnte die Versionsangaben nicht lesen." >&2
    exit 1
fi
echo "  Fassung $VERSION"

# Zielordner: /Applications, falls beschreibbar, sonst der eigene Ordner
ZIEL="/Applications"
if [ ! -w "$ZIEL" ]; then
    ZIEL="$HOME/Applications"
    mkdir -p "$ZIEL"
    echo "  (Keine Schreibrechte auf /Applications — installiere nach $ZIEL)"
fi

ARBEIT="$(mktemp -d)"
trap 'rm -rf "$ARBEIT"' EXIT

echo "▸ Lade herunter …"
curl -fL# -o "$ARBEIT/snapit.zip" "$URL"

echo "▸ Entpacke …"
ditto -x -k "$ARBEIT/snapit.zip" "$ARBEIT/entpackt"
APP="$(find "$ARBEIT/entpackt" -maxdepth 1 -name '*.app' | head -1)"
if [ -z "$APP" ]; then
    echo "✗ Im Archiv war keine App." >&2
    exit 1
fi

echo "▸ Prüfe die Signatur …"
if ! codesign --verify --deep --strict "$APP" 2>/dev/null; then
    echo "✗ Die Signatur ist beschädigt. Installation abgebrochen." >&2
    exit 1
fi
UNTERSCHRIFT="$(codesign -dvvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
if [ "$UNTERSCHRIFT" != "$ERWARTETE_SIGNATUR" ]; then
    echo "✗ Unerwarteter Unterzeichner: ${UNTERSCHRIFT:-keiner}" >&2
    echo "  Erwartet war: $ERWARTETE_SIGNATUR" >&2
    exit 1
fi
echo "  Signiert von: $UNTERSCHRIFT"

if pgrep -f "$NAME.app" >/dev/null 2>&1; then
    echo "▸ Beende die laufende Fassung …"
    pkill -f "$NAME.app" || true
    sleep 1
fi

echo "▸ Installiere nach $ZIEL …"
rm -rf "$ZIEL/$NAME.app"
ditto "$APP" "$ZIEL/$NAME.app"

echo "▸ Starte …"
open "$ZIEL/$NAME.app"

cat << 'HINWEIS'

✓ Snap it ist installiert.

  Das Symbol sitzt oben rechts in der Menüleiste.
  Ausschnitt aufnehmen: Cmd-Shift-2

  Beim ersten Mal fragt macOS nach der Freigabe zur Bildschirmaufnahme.
  Einmal erlauben — danach wird nicht mehr gefragt, auch nach Updates nicht.

HINWEIS
