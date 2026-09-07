# Snap it installieren

Screenshot-Werkzeug für den Mac. Liegt in der Menüleiste, nimmt auf Tastendruck
einen Ausschnitt auf und öffnet ihn sofort zum Beschriften.

---

## Weg 1 — ein Befehl (empfohlen)

Terminal öffnen (`Cmd-Leertaste`, „Terminal" eingeben, Return) und diese Zeile
einfügen:

```bash
curl -fsSL https://raw.githubusercontent.com/Calzi84/snapit/main/install.sh | bash
```

Das lädt Snap it, prüft die Signatur und startet die App. Es gibt keine
Sicherheitsrückfrage, weil die App nicht über den Browser kommt.

Derselbe Befehl aktualisiert später auch eine vorhandene Fassung.

---

## Weg 2 — mit der Maus

1. [Neueste Fassung herunterladen](https://github.com/Calzi84/snapit/releases/latest)
   — die Datei `SnapIt-*.dmg`
2. Doppelklick, dann **Snap it** in den Ordner **Applications** ziehen
3. Snap it öffnen

Beim ersten Öffnen meldet macOS, die App könne nicht auf Schadsoftware geprüft
werden. Das liegt daran, dass sie aus dem eigenen Haus kommt und nicht über den
App Store verteilt wird. Einmalig freigeben:

> **Systemeinstellungen → Datenschutz & Sicherheit →** ganz nach unten scrollen
> **→ „Dennoch öffnen"**

Danach kommt diese Meldung nie wieder, auch bei Updates nicht.

---

## Beim ersten Start

macOS fragt einmal nach der Freigabe zur **Bildschirmaufnahme**. Ohne sie bleibt
das Bild leer. Einmal erlauben genügt — die Freigabe bleibt auch nach Updates
bestehen.

Das Symbol sitzt oben rechts in der Menüleiste.

---

## Bedienung

| Taste | Wirkung |
|---|---|
| `⌘⇧2` | Ausschnitt aufnehmen |
| `⌘Z` / `⇧⌘Z` | zurück / wieder vor |
| `⌘C` | in die Zwischenablage |
| `⌘S` | sichern |
| `⌘L` | Text im Bild erkennen und kopieren |
| `⌘D` | als Idee merken |
| `Esc` | verwerfen |

Werkzeuge über die Leiste unten oder direkt per Taste: `V` Auswahl · `A` Pfeil ·
`L` Linie · `R` Rechteck · `E` Ellipse · `P` Freihand · `H` Marker · `T` Text ·
`B` Verpixeln · `N` Nummer · `C` Zuschneiden.

Beim Ziehen hält `⇧` Linien auf 45° und macht Rechtecke quadratisch. Der Marker
rastet auf Textzeilen ein und läuft gerade, auch wenn die Hand wackelt.

Screenshots und Ideen landen unter **Bilder › Snap it**. Beides lässt sich in
den Einstellungen ändern.

---

## Updates

Snap it sieht einmal täglich nach, ob eine neue Fassung vorliegt, und fragt
dann, ob sie geladen werden soll. Es ist nichts weiter zu tun.
