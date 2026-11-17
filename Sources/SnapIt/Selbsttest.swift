import AppKit
import UniformTypeIdentifiers

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

    /// Zahl verschiedener Farben entlang einer Zeile — grobe Pixel ergeben
    /// lange Strecken gleicher Farbe und damit wenige Werte.
    private static func farbvielfalt(_ bild: NSImage, zeile: Int) -> Int {
        guard let tiff = bild.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), zeile < rep.pixelsHigh else { return 0 }
        var farben = Set<UInt32>()
        for x in 0..<rep.pixelsWide {
            guard let c = rep.colorAt(x: x, y: zeile)?.usingColorSpace(.sRGB) else { continue }
            let r = UInt32(c.redComponent * 255), g = UInt32(c.greenComponent * 255)
            let b = UInt32(c.blueComponent * 255)
            farben.insert(r << 16 | g << 8 | b)
        }
        return farben.count
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
        for w in [Werkzeug.pfeil, .linie, .rechteck, .ellipse, .stift, .marker, .pixel, .weichzeichnen] {
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

        print("\nVerpixeln und Weichzeichnen")
        let zeile = Int(doc.groesse.height / 2)
        if let fein = doc.effektBild(.pixel, staerke: 2),
           let grob = doc.effektBild(.pixel, staerke: 16) {
            let vf = farbvielfalt(fein, zeile: zeile), vg = farbvielfalt(grob, zeile: zeile)
            pruefe("feine Pixel zeigen mehr Einzelheiten als grobe (\(vf) gegen \(vg) Farben)", vf > vg * 2)
        } else {
            pruefe("Verpixeln liefert ein Bild", false)
        }
        if let weich = doc.effektBild(.weichzeichnen, staerke: 10),
           let tiff = weich.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            // Ohne clampedToExtent wäre der Rand durchsichtig und würde hell
            let ecke = rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 0
            let kante = rep.colorAt(x: rep.pixelsWide - 1, y: rep.pixelsHigh / 2)?.alphaComponent ?? 0
            pruefe("Weichzeichnen hat keinen durchsichtigen Rand", ecke > 0.99 && kante > 0.99)
            pruefe("Weichzeichnen behält die Bildgröße",
                   rep.pixelsWide == Int(doc.groesse.width) && rep.pixelsHigh == Int(doc.groesse.height))
        } else {
            pruefe("Weichzeichnen liefert ein Bild", false)
        }

        // Regler wirkt auf die ausgewählte Fläche, Rücknahme in einem Schritt
        flaeche.auswahlAufheben()
        flaeche.staerkeSetzen(4, beginn: false)
        flaeche.werkzeug = .pixel
        ziehen(flaeche, von: CGPoint(x: mitte.x - 70, y: mitte.y + 100),
               nach: CGPoint(x: mitte.x + 70, y: mitte.y + 160))
        if let flaecheForm = doc.formen.last, flaecheForm.werkzeug == .pixel, flaecheForm === doc.formen.last {
            let vorher = flaecheForm.staerke
            let stand = doc.formen.count
            flaeche.staerkeSetzen(9, beginn: true)
            flaeche.staerkeSetzen(12, beginn: false)
            flaeche.staerkeSetzen(14, beginn: false)
            pruefe("Regler ändert die Pixelgröße der ausgewählten Fläche",
                   abs(flaecheForm.staerke - 14 * doc.faktor) < 0.01)
            doc.zurueckNehmen()
            let nachher = doc.formen.last?.staerke ?? -1
            pruefe("ein Zurücknehmen stellt die alte Pixelgröße her",
                   abs(nachher - vorher) < 0.01 && doc.formen.count == stand)
        } else {
            pruefe("Pixelfläche für die Reglerprüfung angelegt", false)
        }
        flaeche.auswahlAufheben()

        print("\nVerdeckter Text bleibt unlesbar")
        // Die schwächste Stufe ist die gefährliche: Wer fein verpixelt, will
        // trotzdem, dass der Name weg ist. Die Kontrolle zuerst — liest die
        // Texterkennung schon den offenen Text nicht, wäre jedes „0 Wörter"
        // unten wertlos.
        for pt in [13.0, 24.0] as [CGFloat] {
            let offen = Lesbarkeit.probebild(punktgroesse: pt)
            let kontrolle = Lesbarkeit.treffer(Lesbarkeit.lesen(offen))
            pruefe("Kontrolle: \(Int(pt)) pt offen lesbar (\(kontrolle.gefunden)/\(kontrolle.von))",
                   kontrolle.gefunden == kontrolle.von)
            for art in [Werkzeug.pixel, .weichzeichnen] {
                guard let v = Lesbarkeit.verdeckt(offen, art: art, stufe: 1) else {
                    pruefe("\(art.rawValue) Stufe 1 gerendert", false); continue
                }
                let t = Lesbarkeit.treffer(Lesbarkeit.lesen(v))
                pruefe("\(art.rawValue) auf Stufe 1, \(Int(pt)) pt: kein Wort lesbar (\(t.gefunden))",
                       t.gefunden == 0)
            }
        }

        print("\nFremde Bilder öffnen")
        let gross = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4000, pixelsHigh: 2600,
                                     bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)
        let probeDatei = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snapit-probe-\(UUID().uuidString).jpg")
        if let g = gross, let jpg = g.representation(using: .jpeg, properties: [:]),
           (try? jpg.write(to: probeDatei)) != nil {
            let alsFoto = Aufnahme.laden(probeDatei, fremd: true)
            let alsAufnahme = Aufnahme.laden(probeDatei)
            pruefe("großes Foto bekommt kräftigere Striche (Faktor \(String(format: "%.1f", alsFoto?.faktor ?? 0)))",
                   (alsFoto?.faktor ?? 0) >= 2.4)
            pruefe("Bildgröße bleibt beim Öffnen erhalten", alsFoto?.groesse == CGSize(width: 4000, height: 2600))
            pruefe("eigene Aufnahmen behalten ihren Faktor", (alsAufnahme?.faktor ?? 0) == 1)
            try? FileManager.default.removeItem(at: probeDatei)
        } else {
            pruefe("Probebild geschrieben", false)
        }
        pruefe("Öffnen kennt PNG, JPEG und HEIC",
               [UTType.png, .jpeg, .heic].allSatisfy { Aufnahme.oeffenbareTypen.contains($0) })

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
