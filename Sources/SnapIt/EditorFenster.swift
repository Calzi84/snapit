import AppKit

/// Das Fenster, in dem ein frischer Screenshot bearbeitet wird.
final class EditorFenster: NSWindowController, NSWindowDelegate, ZeichenflaecheDelegat {

    private let doc: Dokument
    private let flaeche: Zeichenflaeche
    private let leiste = Leiste()
    private var monitor: Any?
    private var meldung: MeldungsView?
    /// Datei, aus der das Bild stammt (Idee erneut geöffnet) — dann wird dort gesichert.
    var herkunft: URL?

    private static var offene: [EditorFenster] = []

    init(doc: Dokument) {
        self.doc = doc
        self.flaeche = Zeichenflaeche(doc: doc)

        let bildschirm = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let pw = doc.groesse.width, ph = doc.groesse.height
        // Die Glasleiste schwebt über dem Bild, oben bleibt Platz für die Fensterknöpfe.
        let zusatzHoehe = Theme.leisteHoehe + 2*Theme.leisteAbstand + Theme.titelHoehe
        let maxB = bildschirm.width * 0.88
        let maxH = bildschirm.height * 0.88 - zusatzHoehe
        let s = min(1 / doc.faktor, maxB / max(pw, 1), maxH / max(ph, 1))
        let breite = max(Leiste.mindestBreite, (pw * s).rounded() + 2*Theme.leisteAbstand)
        let hoehe = (ph * s).rounded() + zusatzHoehe

        let fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: breite, height: hoehe),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable,
                                           .fullSizeContentView],
                               backing: .buffered, defer: false)
        fenster.title = "Snap it"
        fenster.titlebarAppearsTransparent = true
        fenster.titleVisibility = .hidden
        fenster.backgroundColor = Theme.fensterBG
        fenster.appearance = NSAppearance(named: .darkAqua)
        fenster.minSize = NSSize(width: Leiste.mindestBreite, height: 320)
        fenster.center()
        super.init(window: fenster)

        fenster.delegate = self
        let inhalt = NSView(frame: fenster.contentLayoutRect)
        inhalt.wantsLayer = true
        inhalt.layer?.backgroundColor = Theme.fensterBG.cgColor
        inhalt.addSubview(flaeche)
        inhalt.addSubview(leiste)
        fenster.contentView = inhalt

        flaeche.delegat = self
        flaeche.farbe = Theme.palette[Einstellungen.geteilt.standardFarbe]
        flaeche.staerkeUI = CGFloat(Einstellungen.geteilt.standardStaerke)
        verdrahten()
        anordnen()
        zustandGeaendert()

        EditorFenster.offene.append(self)
        Fensterwacht.geoeffnet()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: – Aufbau

    private func verdrahten() {
        leiste.beiWerkzeug = { [weak self] w in self?.flaeche.werkzeug = w }
        leiste.beiFarbe = { [weak self] i in
            self?.flaeche.farbe = Theme.palette[i]
            Einstellungen.geteilt.standardFarbe = i
        }
        leiste.beiStaerke = { [weak self] s in
            self?.flaeche.staerkeUI = s
            Einstellungen.geteilt.standardStaerke = Double(s)
        }
        leiste.beiAktion = { [weak self] a in
            guard let self else { return }
            switch a {
            case .zurueck:   self.zurueck()
            case .vor:       self.vor()
            case .text:      self.textErkennen()
            case .idee:      self.alsIdee()
            case .verwerfen: self.close()
            case .kopieren:  self.kopieren()
            case .sichern:   self.sichern()
            }
        }
    }

    private func anordnen() {
        guard let inhalt = window?.contentView else { return }
        let r = inhalt.bounds
        let a = Theme.leisteAbstand
        flaeche.frame = r
        flaeche.einzugOben = Theme.titelHoehe
        flaeche.einzugUnten = Theme.leisteHoehe + 2*a
        leiste.frame = NSRect(x: a, y: a,
                              width: max(r.width - 2*a, Leiste.mindestBreite - 2*a),
                              height: Theme.leisteHoehe)
        leiste.needsLayout = true
        flaeche.needsDisplay = true
    }

    func windowDidResize(_ n: Notification) { anordnen() }

    func zeigen() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(flaeche)
        tastenUeberwachen()
    }

    func windowWillClose(_ n: Notification) {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        EditorFenster.offene.removeAll { $0 === self }
        Fensterwacht.geschlossen()
    }

    func zustandGeaendert() {
        leiste.verlaufSetzen(zurueck: doc.kannZurueck, vor: doc.kannVor)
    }

    func werkzeugZuruecksetzen() {
        flaeche.werkzeug = .auswahl
        leiste.werkzeugSetzen(.auswahl)
    }

    // MARK: – Tastatur

    private func tastenUeberwachen() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.window?.isKeyWindow == true else { return e }
            // Während einer Texteingabe gehen alle Tasten ins Feld
            if self.window?.firstResponder is NSTextView { return e }

            let cmd = e.modifierFlags.contains(.command)
            let shift = e.modifierFlags.contains(.shift)

            if cmd {
                switch e.charactersIgnoringModifiers?.lowercased() {
                case "z": shift ? self.vor() : self.zurueck(); return nil
                case "c": self.kopieren(); return nil
                case "s": shift ? self.sichernUnter() : self.sichern(); return nil
                case "l": self.textErkennen(); return nil
                case "d": self.alsIdee(); return nil
                case "w": self.close(); return nil
                default: return e
                }
            }

            if e.keyCode == 53 { self.close(); return nil }   // Esc

            let kuerzel: [String: Werkzeug] = [
                "v": .auswahl, "a": .pfeil, "l": .linie, "r": .rechteck, "e": .ellipse,
                "p": .stift, "h": .marker, "t": .text, "b": .pixel, "n": .nummer, "c": .zuschnitt,
            ]
            if let z = e.charactersIgnoringModifiers?.lowercased(), let w = kuerzel[z] {
                self.flaeche.werkzeug = w
                self.leiste.werkzeugSetzen(w)
                return nil
            }
            return e
        }
    }

    // MARK: – Aktionen

    private func zurueck() { flaeche.textCommit(); doc.zurueckNehmen(); flaeche.auswahlAufheben(); flaeche.needsDisplay = true; zustandGeaendert() }
    private func vor()     { flaeche.textCommit(); doc.vorNehmen();     flaeche.auswahlAufheben(); flaeche.needsDisplay = true; zustandGeaendert() }

    private func fertigesBild() -> NSImage? {
        flaeche.textCommit()
        flaeche.auswahlAufheben()
        return Render.rendern(doc)
    }

    private func kopieren() {
        guard let bild = fertigesBild(), let daten = Render.png(bild) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(daten, forType: .png)
        pb.writeObjects([bild])
        zeigeMeldung("In die Zwischenablage kopiert")
    }

    private func sichern() {
        guard let bild = fertigesBild(), let daten = Render.png(bild) else { return }
        let ziel: URL
        if let h = herkunft {
            ziel = h
        } else {
            Einstellungen.geteilt.ordnerSicherstellen()
            ziel = Einstellungen.geteilt.bilderOrdner
                .appendingPathComponent(Einstellungen.geteilt.dateiname(praefix: "Snap it"))
        }
        do {
            try daten.write(to: ziel)
            if Einstellungen.geteilt.nachSichernKopieren {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(daten, forType: .png)
            }
            if Einstellungen.geteilt.imFinderZeigen {
                NSWorkspace.shared.activateFileViewerSelecting([ziel])
            }
            zeigeMeldung("Gesichert in \(ziel.deletingLastPathComponent().lastPathComponent)") {
                self.close()
            }
        } catch {
            zeigeMeldung("Konnte nicht sichern: \(error.localizedDescription)")
        }
    }

    private func sichernUnter() {
        guard let bild = fertigesBild(), let daten = Render.png(bild) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = Einstellungen.geteilt.bilderOrdner
        panel.nameFieldStringValue = Einstellungen.geteilt.dateiname(praefix: "Snap it")
        panel.beginSheetModal(for: window!) { antwort in
            guard antwort == .OK, let url = panel.url else { return }
            try? daten.write(to: url)
            self.zeigeMeldung("Gesichert") { self.close() }
        }
    }

    private func alsIdee() {
        guard let bild = fertigesBild() else { return }
        let feld = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        feld.placeholderString = "Wofür ist das eine Idee?"
        let alarm = NSAlert()
        alarm.messageText = "Als Idee merken"
        alarm.informativeText = "Landet im Ideen-Ordner und ist über die Menüleiste wieder auffindbar."
        alarm.accessoryView = feld
        alarm.addButton(withTitle: "Merken")
        alarm.addButton(withTitle: "Abbrechen")
        alarm.window.initialFirstResponder = feld
        alarm.beginSheetModal(for: window!) { antwort in
            guard antwort == .alertFirstButtonReturn else { return }
            if Ideenablage.sichern(bild, notiz: feld.stringValue) != nil {
                self.zeigeMeldung("Als Idee gemerkt") { self.close() }
            } else {
                self.zeigeMeldung("Konnte die Idee nicht sichern")
            }
        }
    }

    private func textErkennen() {
        guard let bild = fertigesBild() else { return }
        zeigeMeldung("Text wird gelesen …", dauer: 6)
        Texterkennung.lesen(bild) { [weak self] text in
            guard let self else { return }
            guard let text else { self.zeigeMeldung("Kein Text gefunden"); return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            let zeilen = text.split(separator: "\n").count
            self.zeigeMeldung("\(zeilen) Zeile\(zeilen == 1 ? "" : "n") Text kopiert")
        }
    }

    // MARK: – Rückmeldung

    private func zeigeMeldung(_ text: String, dauer: TimeInterval = 1.6, danach: (() -> Void)? = nil) {
        meldung?.removeFromSuperview()
        let v = MeldungsView(text: text)
        flaeche.addSubview(v)
        v.frame = NSRect(x: (flaeche.bounds.width - v.breite)/2,
                         y: flaeche.bounds.height - Theme.leisteHoehe - 2*Theme.leisteAbstand - 46,
                         width: v.breite, height: 36)
        v.autoresizingMask = [.minXMargin, .maxXMargin]
        meldung = v
        DispatchQueue.main.asyncAfter(deadline: .now() + dauer) { [weak v] in
            guard let v, v.superview != nil else { return }
            NSAnimationContext.runAnimationGroup { k in
                k.duration = 0.22
                v.animator().alphaValue = 0
            } completionHandler: {
                v.removeFromSuperview()
                danach?()
            }
        }
    }
}

/// Kurze Rückmeldung am unteren Bildrand.
///
/// Glas und Beschriftung sind eigene Unterebenen. Den Text in draw() zu
/// zeichnen wäre kürzer, er läge dann aber unter der Glasschicht — Unterebenen
/// werden nach der eigenen Zeichnung gemalt.
final class MeldungsView: NSView {
    let breite: CGFloat
    private let schrift = NSFont.systemFont(ofSize: 12.5, weight: .medium)
    private let glas: NSView
    private let beschriftung: NSTextField

    init(text: String) {
        let groesse = (text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .medium)])
        self.breite = groesse.width + 36
        self.glas = Theme.glas(radius: 18)
        self.beschriftung = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true

        beschriftung.font = schrift
        beschriftung.textColor = Theme.schrift
        beschriftung.alignment = .center
        addSubview(glas)
        addSubview(beschriftung)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        glas.frame = bounds
        let h = beschriftung.intrinsicContentSize.height
        beschriftung.frame = NSRect(x: 0, y: (bounds.height - h)/2, width: bounds.width, height: h)
    }

    override func draw(_ dirty: NSRect) {
        NSColor.black.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height/2, yRadius: bounds.height/2).fill()
    }
}
