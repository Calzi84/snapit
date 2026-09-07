import AppKit

/// Fährt die Zeichenfläche mit erzeugten Mausereignissen ab. Das findet
/// Fehler in der Bedienung, die eine reine Layoutaufnahme nicht zeigt.
enum Selbsttest {

    private static var fehler: [String] = []
    private static var geprueft = 0

    private static func pruefe(_ was: String, _ bedingung: Bool) {
        geprueft += 1
        if bedingung {
            print("  ✓ \(was)")
        } else {
            print("  ✗ \(was)")
            fehler.append(was)
        }
    }

    private static func ereignis(_ art: NSEvent.EventType, _ p: CGPoint,
                                 in flaeche: NSView, klicks: Int = 1) -> NSEvent {
        let imFenster = flaeche.convert(p, to: nil)
        return NSEvent.mouseEvent(with: art, location: imFenster, modifierFlags: [],
                                  timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: flaeche.window?.windowNumber ?? 0,
                                  context: nil, eventNumber: 0,
                                  clickCount: klicks, pressure: 1)!
    }

    /// Zieht mit gedrückter Maustaste von a nach b.
    private static func ziehen(_ flaeche: Zeichenflaeche, von a: CGPoint, nach b: CGPoint) {
        flaeche.mouseDown(with: ereignis(.leftMouseDown, a, in: flaeche))
        for i in 1...6 {
            let t = CGFloat(i) / 6
            let p = CGPoint(x: a.x + (b.x - a.x)*t, y: a.y + (b.y - a.y)*t)
            flaeche.mouseDragged(with: ereignis(.leftMouseDragged, p, in: flaeche))
        }
        flaeche.mouseUp(with: ereignis(.leftMouseUp, b, in: flaeche))
    }

    static func starten(_ quelle: URL, ziel: URL) -> Int {
        guard let doc = Aufnahme.laden(quelle) else {
            print("Bild nicht lesbar"); return 1
        }
        let fenster = EditorFenster(doc: doc)
        fenster.zeigen()
        guard let flaeche = fenster.window?.contentView?.subviews
                .compactMap({ $0 as? Zeichenflaeche }).first else {
            print("Zeichenfläche nicht gefunden"); return 1
        }
        flaeche.layoutSubtreeIfNeeded()

        let mitte = CGPoint(x: flaeche.bounds.midX, y: flaeche.bounds.midY)
        let links = CGPoint(x: mitte.x - 160, y: mitte.y - 90)
        let rechts = CGPoint(x: mitte.x + 160, y: mitte.y + 90)

        print("\nFenster")
        pruefe("Fenster lässt sich nicht am Inhalt verschieben",
               fenster.window?.isMovableByWindowBackground == false)
        pruefe("Zeichenfläche fängt Mausklicks ab", flaeche.mouseDownCanMoveWindow == false)
        pruefe("Bild sitzt innerhalb der Fläche",
               flaeche.bildRect.maxY <= flaeche.bounds.height - Theme.leisteHoehe)

        print("\nZeichenwerkzeuge")
        for w in [Werkzeug.pfeil, .linie, .rechteck, .ellipse, .stift, .marker, .pixel] {
            let vorher = doc.formen.count
            flaeche.werkzeug = w
            ziehen(flaeche, von: links, nach: rechts)
            pruefe("\(w.rawValue) legt eine Form an", doc.formen.count == vorher + 1)
        }

        print("\nNummern")
        flaeche.werkzeug = .nummer
        flaeche.mouseDown(with: ereignis(.leftMouseDown, mitte, in: flaeche))
        flaeche.mouseUp(with: ereignis(.leftMouseUp, mitte, in: flaeche))
        let ersteNummer = doc.formen.last
        flaeche.mouseDown(with: ereignis(.leftMouseDown,
                                         CGPoint(x: mitte.x + 60, y: mitte.y), in: flaeche))
        flaeche.mouseUp(with: ereignis(.leftMouseUp,
                                       CGPoint(x: mitte.x + 60, y: mitte.y), in: flaeche))
        pruefe("Nummern zählen hoch", ersteNummer?.nummer == 1 && doc.formen.last?.nummer == 2)

        // Nach einer Rücknahme muss die nächste Marke die freigewordene Zahl tragen
        doc.zurueckNehmen()
        flaeche.mouseDown(with: ereignis(.leftMouseDown,
                                         CGPoint(x: mitte.x + 90, y: mitte.y), in: flaeche))
        flaeche.mouseUp(with: ereignis(.leftMouseUp,
                                       CGPoint(x: mitte.x + 90, y: mitte.y), in: flaeche))
        pruefe("Zähler springt nach Rücknahme nicht", doc.formen.last?.nummer == 2)

        print("\nAuswählen und Verschieben")
        flaeche.werkzeug = .auswahl
        let ziel1 = doc.formen.first!
        let vorPos = ziel1.p1
        // Auf die zuletzt gelegte Form klicken und ziehen
        let letzte = doc.formen.last!
        let trefferBild = letzte.p1
        let treffer = CGPoint(x: trefferBild.x * flaeche.skala + flaeche.bildRect.minX,
                              y: trefferBild.y * flaeche.skala + flaeche.bildRect.minY)
        let vorherLetzte = letzte.p1
        ziehen(flaeche, von: treffer, nach: CGPoint(x: treffer.x + 40, y: treffer.y + 25))
        pruefe("Form lässt sich verschieben", letzte.p1 != vorherLetzte)
        pruefe("andere Formen bleiben liegen", ziel1.p1 == vorPos)

        print("\nZurücknehmen")
        let standVorUndo = doc.formen.count
        pruefe("Rücknahme ist möglich", doc.kannZurueck)
        doc.zurueckNehmen()
        pruefe("Verschieben wurde zurückgenommen", doc.formen.count == standVorUndo)
        doc.zurueckNehmen()
        pruefe("eine Form weniger nach zweiter Rücknahme", doc.formen.count == standVorUndo - 1)
        doc.vorNehmen()
        pruefe("Wiederholen stellt sie zurück", doc.formen.count == standVorUndo)

        print("\nZuschneiden")
        let vorGroesse = doc.groesse
        flaeche.werkzeug = .zuschnitt
        ziehen(flaeche, von: CGPoint(x: flaeche.bildRect.minX + 30, y: flaeche.bildRect.minY + 30),
               nach: CGPoint(x: flaeche.bildRect.midX, y: flaeche.bildRect.midY))
        pruefe("Bild wurde kleiner", doc.groesse.width < vorGroesse.width)
        pruefe("Werkzeug springt danach auf Auswahl", flaeche.werkzeug == .auswahl)
        doc.zurueckNehmen()
        pruefe("Zuschnitt ist rücknehmbar", doc.groesse == vorGroesse)

        print("\nExport")
        let fertig = Render.rendern(doc)
        pruefe("Export liefert ein Bild", fertig != nil)
        pruefe("Export hat die Bildgröße", fertig?.size == doc.groesse)
        if let f = fertig, let daten = Render.png(f) {
            try? daten.write(to: ziel)
            pruefe("PNG ist nicht leer", daten.count > 5000)
        } else {
            pruefe("PNG konnte geschrieben werden", false)
        }

        print("\n\(geprueft - fehler.count) von \(geprueft) Prüfungen bestanden")
        if !fehler.isEmpty {
            print("Offen:")
            for f in fehler { print("  · \(f)") }
        }
        return fehler.isEmpty ? 0 : 2
    }
}
