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

    /// Zug mit unruhiger Hand: die Höhe schwankt um bis zu 12 Punkte.
    private static func wackeln(_ flaeche: Zeichenflaeche, von a: CGPoint, nach b: CGPoint) {
        flaeche.mouseDown(with: ereignis(.leftMouseDown, a, in: flaeche))
        for i in 1...8 {
            let t = CGFloat(i) / 8
            let p = CGPoint(x: a.x + (b.x - a.x)*t,
                            y: a.y + (b.y - a.y)*t + (i % 2 == 0 ? 12 : -9))
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
            flaeche.auswahlAufheben()
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

        print("\nGröße ändern")
        func inAnsicht(_ q: CGPoint) -> CGPoint {
            CGPoint(x: q.x * flaeche.skala + flaeche.bildRect.minX,
                    y: q.y * flaeche.skala + flaeche.bildRect.minY)
        }
        flaeche.auswahlAufheben()
        flaeche.werkzeug = .rechteck
        ziehen(flaeche, von: CGPoint(x: mitte.x - 60, y: mitte.y - 40),
               nach: CGPoint(x: mitte.x + 60, y: mitte.y + 40))
        if let kasten = doc.formen.last, kasten.werkzeug == .rechteck {
            pruefe("frisch gezeichnete Form ist ausgewählt", flaeche.hatAuswahl)
            let vorher = kasten.rechteck
            let anzahl = doc.formen.count

            let griffUR = inAnsicht(CGPoint(x: vorher.maxX, y: vorher.maxY))
            ziehen(flaeche, von: griffUR, nach: CGPoint(x: griffUR.x + 50, y: griffUR.y + 30))
            pruefe("Eckanfasser vergrößert das Rechteck",
                   kasten.rechteck.width > vorher.width + 20 && kasten.rechteck.height > vorher.height + 10)
            pruefe("gegenüberliegende Ecke bleibt stehen",
                   abs(kasten.rechteck.minX - vorher.minX) < 0.5 && abs(kasten.rechteck.minY - vorher.minY) < 0.5)
            pruefe("Ziehen am Anfasser legt keine neue Form an", doc.formen.count == anzahl)

            let r2 = kasten.rechteck
            let griffRechts = inAnsicht(CGPoint(x: r2.maxX, y: r2.midY))
            ziehen(flaeche, von: griffRechts, nach: CGPoint(x: griffRechts.x - 30, y: griffRechts.y + 40))
            pruefe("Kantenanfasser ändert nur die Breite",
                   kasten.rechteck.width < r2.width && abs(kasten.rechteck.height - r2.height) < 0.5)

            doc.zurueckNehmen()
            flaeche.auswahlAufheben()
            let zurueck = doc.formen.last?.rechteck ?? .zero
            pruefe("Größenänderung ist rücknehmbar", abs(zurueck.width - r2.width) < 0.5)
        } else {
            pruefe("Rechteck für die Größenprüfung angelegt", false)
        }

        flaeche.werkzeug = .linie
        let l1 = CGPoint(x: mitte.x - 80, y: mitte.y + 70)
        let l2 = CGPoint(x: mitte.x + 80, y: mitte.y + 70)
        ziehen(flaeche, von: l1, nach: l2)
        if let linie = doc.formen.last, linie.werkzeug == .linie {
            let anfang = linie.p1, ende = linie.p2
            ziehen(flaeche, von: inAnsicht(ende), nach: CGPoint(x: l2.x, y: l2.y + 50))
            pruefe("Endanfasser versetzt nur das Linienende", linie.p2 != ende && linie.p1 == anfang)
        } else {
            pruefe("Linie für die Größenprüfung angelegt", false)
        }

        flaeche.auswahlAufheben()
        flaeche.werkzeug = .marker
        wackeln(flaeche, von: CGPoint(x: mitte.x - 100, y: mitte.y - 90),
                nach: CGPoint(x: mitte.x + 60, y: mitte.y - 90))
        if let m = doc.formen.last, m.werkzeug == .marker,
           let rechtsEnde = m.punkte.max(by: { $0.x < $1.x }) {
            let breiteVorher = (m.punkte.map { $0.x }.max() ?? 0) - (m.punkte.map { $0.x }.min() ?? 0)
            let g = inAnsicht(rechtsEnde)
            ziehen(flaeche, von: g, nach: CGPoint(x: g.x + 60, y: g.y + 25))
            let xs = m.punkte.map { $0.x }
            pruefe("Marker wird am Ende länger und bleibt auf der Zeile",
                   (xs.max()! - xs.min()!) > breiteVorher + 30
                   && Set(m.punkte.map { ($0.y * 100).rounded() }).count == 1)
        } else {
            pruefe("Marker für die Größenprüfung angelegt", false)
        }
        flaeche.auswahlAufheben()

        print("\nZwischenablage")
        let probe = NSPasteboard(name: NSPasteboard.Name("SnapItSelbsttest"))
        if let bild = Render.rendern(doc) {
            Zwischenablage.bild(bild, auf: probe)
            let eintraege = probe.pasteboardItems ?? []
            pruefe("Kopieren legt genau einen Eintrag ab", eintraege.count == 1)
            let typen = eintraege.first?.types ?? []
            pruefe("der Eintrag trägt PNG und TIFF", typen.contains(.png) && typen.contains(.tiff))
        } else {
            pruefe("Bild für die Zwischenablage gerendert", false)
        }
        probe.releaseGlobally()

        print("\nZeichnen bleibt im Bild")
        flaeche.werkzeug = .pfeil
        // Zug über den Bildrand hinaus: die Form muss an der Kante enden
        ziehen(flaeche, von: mitte,
               nach: CGPoint(x: flaeche.bildRect.maxX + 260, y: flaeche.bildRect.maxY + 180))
        if let f = doc.formen.last {
            let imBild = f.p2.x >= 0 && f.p2.y >= 0
                && f.p2.x <= doc.groesse.width && f.p2.y <= doc.groesse.height
            pruefe("Zug über den Bildrand hinaus endet an der Kante", imBild)
        } else {
            pruefe("Zug über den Bildrand legt eine Form an", false)
        }

        // Neben dem Bild gehört der Zug dem Fenster, nicht dem Werkzeug.
        // Geprüft wird die Zuständigkeit statt eines echten Zuges — ein
        // mouseDown dort startet eine Zieh-Schleife, die im Test nie endet.
        let neben = CGPoint(x: flaeche.bildRect.minX - 40, y: flaeche.bildRect.minY - 20)
        pruefe("Rand neben dem Bild verschiebt das Fenster", !flaeche.istZeichenbereich(neben))
        pruefe("oberer Fensterrand verschiebt das Fenster",
               !flaeche.istZeichenbereich(CGPoint(x: flaeche.bounds.midX, y: 8)))
        pruefe("auf dem Bild wird gezeichnet", flaeche.istZeichenbereich(mitte))

        print("\nMarker")
        flaeche.werkzeug = .marker
        wackeln(flaeche, von: CGPoint(x: mitte.x - 140, y: mitte.y),
                nach: CGPoint(x: mitte.x + 140, y: mitte.y))
        if let m = doc.formen.last, m.werkzeug == .marker, m.punkte.count > 2 {
            let hoehen = Set(m.punkte.map { ($0.y * 100).rounded() })
            pruefe("Marker läuft trotz unruhiger Hand waagerecht", hoehen.count == 1)
        } else {
            pruefe("Marker legt eine Form an", false)
        }

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

        // Ansicht mit ausgewählter Form ablegen, damit sich die Anfasser ansehen lassen
        flaeche.werkzeug = .ellipse
        flaeche.auswahlAufheben()
        ziehen(flaeche, von: CGPoint(x: mitte.x - 90, y: mitte.y - 150),
               nach: CGPoint(x: mitte.x + 90, y: mitte.y - 40))
        flaeche.display()
        if let inhalt = fenster.window?.contentView,
           let rep = inhalt.bitmapImageRepForCachingDisplay(in: inhalt.bounds) {
            inhalt.cacheDisplay(in: inhalt.bounds, to: rep)
            let ansicht = ziel.deletingPathExtension().appendingPathExtension("ansicht.png")
            try? rep.representation(using: .png, properties: [:])?.write(to: ansicht)
            print("Ansicht: \(ansicht.path)")
        }

        print("\n\(geprueft - fehler.count) von \(geprueft) Prüfungen bestanden")
        if !fehler.isEmpty {
            print("Offen:")
            for f in fehler { print("  · \(f)") }
        }
        return fehler.isEmpty ? 0 : 2
    }
}
