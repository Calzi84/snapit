# Snap it

Screenshot-Werkzeug für macOS. Liegt in der Menüleiste, nimmt auf Tastendruck
einen Ausschnitt auf und öffnet ihn sofort zum Beschriften.

![Menüleiste](docs/menue.png)

## Was es kann

| | |
|---|---|
| **Aufnehmen** | Ausschnitt, einzelnes Fenster oder ganzer Bildschirm |
| **Zeichnen** | Pfeil, Linie, Rechteck, Ellipse, Freihand, Marker |
| **Beschriften** | Text, nummerierte Marken (1, 2, 3 …) |
| **Unkenntlich machen** | Verpixeln von Namen, Adressen, Beträgen |
| **Zuschneiden** | direkt im Editor |
| **Text auslesen** | erkennt Text im Bild und legt ihn in die Zwischenablage |
| **Ideen merken** | Screenshot mit Notiz in einer eigenen Ablage sammeln |

Alles wird als Objekt gespeichert, nicht ins Bild gebrannt: Jeder Pfeil bleibt
verschiebbar und löschbar, bis gesichert wird.

## Installation

Voraussetzung ist Xcode oder die Command Line Tools (`xcode-select --install`).

```bash
git clone <repo-adresse> snapit
cd snapit
./build.sh install
```

Danach erscheint das Symbol in der Menüleiste.

**Beim ersten Aufnehmen fragt macOS nach der Berechtigung zur
Bildschirmaufnahme.** Ohne sie bleibt das Bild schwarz. Die Freigabe steht unter
_Systemeinstellungen › Datenschutz & Sicherheit › Bildschirmaufnahme_.

## Bedienung

| Taste | Wirkung |
|---|---|
| `⌘⇧2` | Ausschnitt aufnehmen (in den Einstellungen änderbar) |
| `V A L R E P H T B N C` | Werkzeug wählen |
| `⌘Z` / `⇧⌘Z` | zurück / wieder vor |
| `⌘C` | in die Zwischenablage |
| `⌘S` | in den eingestellten Ordner sichern |
| `⇧⌘S` | sichern unter … |
| `⌘L` | Text im Bild erkennen |
| `⌘D` | als Idee merken |
| `Esc` | verwerfen |

Beim Ziehen hält `⇧` Linien auf 45° und macht Rechtecke quadratisch.

## Ablage

Standardmäßig unter **Bilder › Snap it**, getrennt nach `Aufnahmen` und `Ideen`.
Beide Orte lassen sich in den Einstellungen frei wählen. Die Ideen liegen als
normale PNG-Dateien dort, der Index daneben als `ideen.json` — auch ohne die App
lesbar.

## Updates verteilen

Die App sieht einmal täglich in der `version.json` des Repos nach, ob eine
neuere Fassung vorliegt, und bietet sie dann an. Die Adresse steckt in der
Info.plist und lässt sich in den Einstellungen überschreiben.

Neue Fassung herausgeben:

```bash
./release.sh 1.1.0 "Marker ist jetzt breiter"
```

Das baut die App, packt sie, legt ein GitHub-Release an und schreibt die
`version.json` fort. Auf den anderen Macs erscheint der Hinweis beim nächsten
Start.

**Zur Signatur:** `build.sh` signiert die App nur ad hoc. Für die Verteilung an
mehrere Rechner ohne Gatekeeper-Warnung braucht es ein Developer-ID-Zertifikat
und eine Notarisierung. Ohne das muss die App auf jedem Mac einmal über
_Rechtsklick › Öffnen_ freigegeben werden — und die Freigabe zur
Bildschirmaufnahme wird nach einem Update erneut abgefragt, weil sich die
Signatur bei jedem Build ändert.

## Aufbau

```
Sources/SnapIt/
├─ main.swift              Start, außerdem --iconset und --vorschau
├─ AppDelegate.swift       Menüleiste, Tastenkürzel, Fensterverwaltung
├─ Aufnahme.swift          Bildschirmaufnahme über screencapture
├─ Model.swift             Formen, Dokument, Undo
├─ Render.swift            Zeichnen und Export
├─ Zeichenflaeche.swift    Zeichenfläche und Maussteuerung
├─ Leiste.swift            Werkzeugleiste im Glasstil
├─ EditorFenster.swift     Editorfenster
├─ Einstellungen*.swift    Einstellungen samt Fenster
├─ Ideen*.swift            Ideen-Ablage samt Übersicht
├─ Texterkennung.swift     Vision
├─ Aktualisierung.swift    Update-Prüfung
├─ Symbolbild.swift        App- und Menüleistensymbol im Code gezeichnet
└─ Theme.swift             Farben, Maße, Glasmaterial
```

Das Layout lässt sich ohne Bildschirmaufnahme prüfen — die App fotografiert ihr
eigenes Fenster:

```bash
SNAPIT_KEIN_GLAS=1 .build/release/SnapIt --vorschau bild.png vorschau.png
```
