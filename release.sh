#!/bin/bash
# Gibt eine neue Fassung heraus:
#   ./release.sh 1.1.0 "Was neu ist"
#
# Baut die App, packt sie, hängt sie an ein GitHub-Release und schreibt
# version.json fort. Die Mitarbeiter-Macs sehen das Update dann beim
# nächsten Start — die App prüft version.json einmal täglich.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-}"
NOTIZ="${2:-}"
if [ -z "$VERSION" ]; then
    echo "Aufruf: ./release.sh <version> \"<notiz>\""
    exit 1
fi

REPO="$(git config --get remote.origin.url | sed -E 's#.*github.com[:/]([^/]+/[^/.]+)(\.git)?#\1#')"
if [ -z "$REPO" ]; then
    echo "Kein GitHub-Remote gesetzt."
    exit 1
fi

echo "$VERSION" > VERSION

# Die Update-Adresse zeigt auf version.json im Hauptzweig.
ZWEIG="$(git rev-parse --abbrev-ref HEAD)"
export SNAPIT_UPDATE_URL="https://raw.githubusercontent.com/$REPO/$ZWEIG/version.json"
./build.sh

echo "▸ Packe Archiv …"
ARCHIV="build/SnapIt-$VERSION.zip"
rm -f "$ARCHIV"
ditto -c -k --sequesterRsrc --keepParent "build/Snap it.app" "$ARCHIV"

cat > version.json << JSON
{
  "version": "$VERSION",
  "notizen": "$NOTIZ",
  "download": "https://github.com/$REPO/releases/download/v$VERSION/SnapIt-$VERSION.zip"
}
JSON

git add VERSION version.json
git commit -m "Fassung $VERSION" || true
git tag -f "v$VERSION"
git push origin "$ZWEIG" --tags

echo "▸ Lege Release an …"
gh release create "v$VERSION" "$ARCHIV" --title "Snap it $VERSION" --notes "$NOTIZ" \
    || gh release upload "v$VERSION" "$ARCHIV" --clobber

echo "▸ Fertig. Die Mitarbeiter sehen das Update beim nächsten Start."
