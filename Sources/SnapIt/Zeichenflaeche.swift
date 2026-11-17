import AppKit

protocol ZeichenflaecheDelegat: AnyObject {
    func zustandGeaendert()
    func werkzeugZuruecksetzen()
    /// Stärke der neu ausgewählten Form im Maß des Reglers, oder nil.
    func auswahlGeaendert(staerke: CGFloat?)
}

/// Die Zeichenfläche: zeigt das Bild und nimmt alle Mauseingaben entgegen.
/// Sie ist geflippt, damit Bildkoordinaten (Ursprung oben links) direkt passen.
final class Zeichenflaeche: NSView {

    weak var delegat: ZeichenflaecheDelegat?
    var doc: Dokument
    var werkzeug: Werkzeug = .pfeil {
        didSet {
            if werkzeug == .zuschnitt { auswahl = nil }
            cursorSetzen()
            needsDisplay = true
        }
    }
    var farbe: NSColor = Theme.palette[0]
    var staerkeUI: CGFloat = 4

    /// Strichstärke in Bildpixeln — bei Retina-Aufnahmen doppelt so groß wie im Regler.
    private var staerke: CGFloat { staerkeUI * doc.faktor }

    private var aktuelle: Form?
    private var auswahl: Form? {
        didSet {
            needsDisplay = true
            guard auswahl !== oldValue else { return }
            // Regler auf den Wert der Auswahl stellen, damit sie beim ersten
            // Antippen nicht auf einen fremden Wert springt
            if let a = auswahl, a.werkzeug != .marker {
                delegat?.auswahlGeaendert(staerke: a.staerke / doc.faktor)
            } else {
                delegat?.auswahlGeaendert(staerke: nil)
            }
        }
    }
    private var zieheAb: CGPoint = .zero
    private var hatGemerkt = false

    /// Anfasser an einer ausgewählten Form. Die Flags sagen, welche Kanten ein
    /// Zug daran bewegt; `ende` gilt für Linien, Pfeile und Marker.
    private struct Griff {
        let punkt: CGPoint
        var links = false, rechts = false, oben = false, unten = false
        var ende: Int? = nil
        var istEcke: Bool { (links || rechts) && (oben || unten) }
    }
    private var griffAktiv: Griff?
    /// Lage der Form zu Beginn des Zugs — gerechnet wird immer von hier aus,
    /// sonst summieren sich Rundungsfehler bei jedem Mausschritt.
    private var griffStartRahmen: CGRect = .zero
    private var griffStartPunkte: [CGPoint] = []
    private var textFeld: NSTextField?
    /// Aus den vorhandenen Marken abgeleitet, damit der Zähler nach einer
    /// Rücknahme nicht weiterspringt.
    private var naechsteNummer: Int {
        (doc.formen.filter { $0.werkzeug == .nummer }.map { $0.nummer }.max() ?? 0) + 1
    }

    init(doc: Dokument) {
        self.doc = doc
        super.init(frame: .zero)
        wantsLayer = true
        zeilenErkennen()
    }

    /// Sucht die Textzeilen im Bild. Läuft nebenher; bis das Ergebnis da ist,
    /// zieht der Marker einfach waagerecht.
    func zeilenErkennen() {
        textzeilen = []
        Texterkennung.zeilen(doc.bild) { [weak self] zeilen in
            self?.textzeilen = zeilen
        }
    }

    /// Textzeile unter einem Punkt, mit etwas Toleranz nach oben und unten.
    private func zeileBei(_ p: CGPoint) -> CGRect? {
        let treffer = textzeilen.filter {
            p.x >= $0.minX - $0.height && p.x <= $0.maxX + $0.height
                && p.y >= $0.minY - $0.height*0.6 && p.y <= $0.maxY + $0.height*0.6
        }
        return treffer.min { abs($0.midY - p.y) < abs($1.midY - p.y) }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    /// Ohne das verschiebt ein Zug auf der Fläche das Fenster, statt zu zeichnen.
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: – Umrechnung

    /// Fläche, die dem Bild bleibt.
    private var buehne: CGRect {
        CGRect(x: 0, y: einzugOben,
               width: bounds.width,
               height: max(bounds.height - einzugOben - einzugUnten, 1))
    }

    var skala: CGFloat {
        guard doc.groesse.width > 0, doc.groesse.height > 0 else { return 1 }
        let b = buehne
        return min(b.width / doc.groesse.width, b.height / doc.groesse.height)
    }

    var bildRect: CGRect {
        let s = skala, b = buehne
        let w = doc.groesse.width * s, h = doc.groesse.height * s
        return CGRect(x: (b.minX + (b.width - w)/2).rounded(),
                      y: (b.minY + (b.height - h)/2).rounded(), width: w, height: h)
    }

    /// Rechnet einen Punkt der Ansicht in Bildpixel um und hält ihn im Bild.
    /// Ohne die Begrenzung lässt sich neben das Bild malen; beim Sichern fehlt
    /// dieser Teil dann, weil nur die Bildfläche exportiert wird.
    private func nachBild(_ p: CGPoint) -> CGPoint {
        let r = bildRect, s = max(skala, 0.0001)
        return CGPoint(x: min(max((p.x - r.minX)/s, 0), doc.groesse.width),
                       y: min(max((p.y - r.minY)/s, 0), doc.groesse.height))
    }

    private func nachView(_ p: CGPoint) -> CGPoint {
        let r = bildRect, s = skala
        return CGPoint(x: p.x * s + r.minX, y: p.y * s + r.minY)
    }

    private func nachView(_ r: CGRect) -> CGRect {
        let o = nachView(r.origin)
        return CGRect(x: o.x, y: o.y, width: r.width * skala, height: r.height * skala)
    }

    // MARK: – Zeichnen

    override func draw(_ dirty: NSRect) {
        Theme.fensterBG.setFill()
        dirty.fill()

        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: bildRect.minX, yBy: bildRect.minY)
        t.scaleX(by: skala, yBy: skala)
        t.concat()
        ctx.imageInterpolation = .high

        doc.bild.draw(in: CGRect(origin: .zero, size: doc.groesse))
        NSBezierPath(rect: CGRect(origin: .zero, size: doc.groesse)).setClip()
        for f in doc.formen { Render.zeichne(f, doc: doc) }
        if let a = aktuelle, a.werkzeug != .zuschnitt { Render.zeichne(a, doc: doc) }
        ctx.restoreGraphicsState()

        if let a = auswahl {
            // Rahmenformen zeigen den Auswahlrahmen genau durch ihre Anfasser,
            // Linien kommen mit den Endpunkten aus, Text und Nummern behalten
            // den Rahmen um ihre Fläche.
            let umriss: CGRect?
            switch a.werkzeug {
            case .rechteck, .ellipse, .pixel, .weichzeichnen: umriss = nachView(a.rechteck)
            case .stift:                      umriss = punkteRahmen(a).map { nachView($0) }
            case .linie, .pfeil, .marker:     umriss = nil
            default:
                umriss = nachView(a.rahmen(schrift: Render.schriftFuer(a.staerke))).insetBy(dx: -3, dy: -3)
            }
            if let r = umriss {
                Theme.gruen.withAlphaComponent(0.95).setStroke()
                let p = NSBezierPath(rect: r)
                p.lineWidth = 1.5
                p.setLineDash([5, 4], count: 2, phase: 0)
                p.stroke()
            }
            griffeZeichnen(a)
        }

        if let z = aktuelle, z.werkzeug == .zuschnitt {
            let r = nachView(z.rechteck)
            NSColor.black.withAlphaComponent(0.55).setFill()
            let aussen = NSBezierPath(rect: bildRect)
            aussen.append(NSBezierPath(rect: r))
            aussen.windingRule = .evenOdd
            aussen.fill()
            NSColor.white.setStroke()
            let rahmen = NSBezierPath(rect: r)
            rahmen.lineWidth = 1
            rahmen.stroke()
            hinweis("\(Int(z.rechteck.width)) × \(Int(z.rechteck.height))  ·  Loslassen schneidet zu",
                    bei: CGPoint(x: r.midX, y: max(r.minY - 26, 8)))
        }
    }

    private func hinweis(_ text: String, bei p: CGPoint) {
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let s = (text as NSString).size(withAttributes: attr)
        let kasten = CGRect(x: p.x - s.width/2 - 8, y: p.y - 3, width: s.width + 16, height: s.height + 6)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: kasten, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: CGPoint(x: kasten.minX + 8, y: kasten.minY + 3), withAttributes: attr)
    }

    // MARK: – Maus

    override func mouseDown(with e: NSEvent) {
        textCommit()
        let roh = convert(e.locationInWindow, from: nil)

        // Anfasser der ausgewählten Form gehen vor — auch vor dem Fensterrand,
        // denn an der Bildkante ragen sie ein Stück darüber hinaus.
        if let a = auswahl, let g = griff(an: roh, fuer: a) {
            griffAktiv = g
            griffStartRahmen = a.werkzeug == .stift ? (punkteRahmen(a) ?? a.rechteck) : a.rechteck
            griffStartPunkte = a.punkte
            hatGemerkt = false
            return
        }

        // Neben dem Bild wird das Fenster verschoben, nicht gezeichnet. Die
        // Fläche liegt über dem gesamten Fenster, auch über dem freien Rand
        // oben — ohne das ließe sich das Fenster nirgends mehr anfassen.
        guard bildRect.contains(roh) else {
            auswahl = nil
            window?.performDrag(with: e)
            return
        }

        let p = nachBild(roh)
        hatGemerkt = false
        // Wer mit einem Zeichenwerkzeug neben die Anfasser klickt, beginnt etwas Neues
        if werkzeug != .auswahl { auswahl = nil }

        switch werkzeug {
        case .auswahl:
            auswahl = treffer(p)
            zieheAb = p

        case .text:
            textFeldOeffnen(bei: p)

        case .nummer:
            doc.merken()
            let f = Form(werkzeug: .nummer, farbe: farbe, staerke: staerke, p1: p, p2: p)
            f.nummer = naechsteNummer
            doc.formen.append(f)
            delegat?.zustandGeaendert()
            needsDisplay = true

        case .stift:
            let f = Form(werkzeug: .stift, farbe: farbe, staerke: staerke, p1: p, p2: p)
            f.punkte = [p]
            aktuelle = f

        case .marker:
            // Auf die Textzeile einrasten: Höhe und Dicke kommen aus der Zeile,
            // damit ein wackeliger Zug trotzdem sauber über der Zeile liegt.
            let f = Form(werkzeug: .marker, farbe: farbe, staerke: staerke, p1: p, p2: p)
            if let z = zeileBei(p) {
                markerHoehe = z.midY
                f.staerke = max(z.height * 1.02, 6) / 4.5   // Render zeichnet staerke × 4,5
            } else {
                markerHoehe = p.y
            }
            let start = CGPoint(x: p.x, y: markerHoehe ?? p.y)
            f.p1 = start
            f.punkte = [start]
            aktuelle = f

        default:
            aktuelle = Form(werkzeug: werkzeug, farbe: farbe, staerke: staerke, p1: p, p2: p)
        }
    }

    override func mouseDragged(with e: NSEvent) {
        let p = nachBild(convert(e.locationInWindow, from: nil))

        if let g = griffAktiv, let a = auswahl {
            if !hatGemerkt { doc.merken(); hatGemerkt = true }
            groesseAendern(a, griff: g, auf: p, gleichmaessig: e.modifierFlags.contains(.shift))
            needsDisplay = true
            return
        }

        if werkzeug == .auswahl {
            guard let a = auswahl else { return }
            if !hatGemerkt { doc.merken(); hatGemerkt = true }
            a.verschieben(dx: p.x - zieheAb.x, dy: p.y - zieheAb.y)
            zieheAb = p
            needsDisplay = true
            return
        }

        guard let f = aktuelle else { return }
        if f.werkzeug == .marker {
            f.punkte.append(CGPoint(x: p.x, y: markerHoehe ?? p.y))
        } else if f.werkzeug == .stift {
            f.punkte.append(p)
        } else {
            var ziel = p
            // Shift hält Linien und Pfeile auf 45°, Rechtecke und Ellipsen quadratisch
            if e.modifierFlags.contains(.shift) {
                if f.werkzeug == .linie || f.werkzeug == .pfeil {
                    ziel = rasten45(von: f.p1, nach: p)
                } else if f.werkzeug.istRahmen {
                    let s = max(abs(p.x - f.p1.x), abs(p.y - f.p1.y))
                    ziel = CGPoint(x: f.p1.x + (p.x < f.p1.x ? -s : s),
                                   y: f.p1.y + (p.y < f.p1.y ? -s : s))
                }
            }
            f.p2 = ziel
        }
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        defer { aktuelle = nil; markerHoehe = nil; needsDisplay = true }
        if griffAktiv != nil {
            griffAktiv = nil
            if hatGemerkt { delegat?.zustandGeaendert() }
            return
        }
        if werkzeug == .auswahl {
            if hatGemerkt { delegat?.zustandGeaendert() }
            return
        }
        guard let f = aktuelle else { return }

        if f.werkzeug == .zuschnitt {
            doc.zuschneiden(auf: f.rechteck)
            zeilenErkennen()
            delegat?.werkzeugZuruecksetzen()
            delegat?.zustandGeaendert()
            return
        }

        let gross: Bool
        switch f.werkzeug {
        case .stift, .marker: gross = f.punkte.count > 2
        default: gross = hypot(f.p2.x - f.p1.x, f.p2.y - f.p1.y) > 4
        }
        guard gross else { return }

        doc.merken()
        doc.formen.append(f)
        // Ausgewählt lassen, damit sich die Form sofort an den Anfassern anpassen lässt
        if !griffe(f).isEmpty { auswahl = f }
        delegat?.zustandGeaendert()
    }

    private func treffer(_ p: CGPoint) -> Form? {
        for f in doc.formen.reversed() {
            if f.rahmen(schrift: Render.schriftFuer(f.staerke)).insetBy(dx: -4, dy: -4).contains(p) {
                return f
            }
        }
        return nil
    }

    // MARK: – Tastatur

    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 51, 117:   // Rückschritt, Entfernen
            if let a = auswahl, let i = doc.formen.firstIndex(where: { $0 === a }) {
                doc.merken()
                doc.formen.remove(at: i)
                auswahl = nil
                delegat?.zustandGeaendert()
                needsDisplay = true
                return
            }
        case 53:        // Esc
            if auswahl != nil { auswahl = nil; return }
        default: break
        }
        super.keyDown(with: e)
    }

    func auswahlAufheben() { auswahl = nil }

    var hatAuswahl: Bool { auswahl != nil }

    /// Farbe setzen — und die ausgewählte Form gleich mit umfärben.
    func farbeSetzen(_ c: NSColor) {
        farbe = c
        guard let a = auswahl, !a.werkzeug.istEffekt else { return }
        doc.merken()
        a.farbe = c
        delegat?.zustandGeaendert()
        needsDisplay = true
    }

    /// Stärke setzen. Bei ausgewählter Form wirkt der Regler sofort auf sie —
    /// nur so lässt sich die Pixelgröße einer gesetzten Fläche einstellen.
    /// `beginn` markiert den ersten Schritt eines Zugs; nur dort wird für die
    /// Rücknahme gemerkt, sonst stünde jeder Zwischenwert im Verlauf.
    func staerkeSetzen(_ wert: CGFloat, beginn: Bool) {
        staerkeUI = wert
        // Der Marker bleibt außen vor: seine Dicke stammt aus der erkannten
        // Textzeile und würde sonst vom Regler überschrieben.
        guard let a = auswahl, a.werkzeug != .marker else { return }
        if beginn { doc.merken() }
        a.staerke = wert * doc.faktor
        delegat?.zustandGeaendert()
        needsDisplay = true
    }

    // MARK: – Anfasser

    private func griffe(_ f: Form) -> [Griff] {
        switch f.werkzeug {
        case .rechteck, .ellipse, .pixel, .weichzeichnen:
            return griffeUm(f.rechteck, mitKanten: true)
        case .stift:
            guard let r = punkteRahmen(f) else { return [] }
            return griffeUm(r, mitKanten: false)
        case .linie, .pfeil:
            return [Griff(punkt: f.p1, ende: 0), Griff(punkt: f.p2, ende: 1)]
        case .marker:
            guard let l = f.punkte.min(by: { $0.x < $1.x }),
                  let r = f.punkte.max(by: { $0.x < $1.x }) else { return [] }
            return [Griff(punkt: l, ende: 0), Griff(punkt: r, ende: 1)]
        default:
            return []   // Text und Nummern: Größe über den Stärkeregler
        }
    }

    private func griffeUm(_ r: CGRect, mitKanten: Bool) -> [Griff] {
        var g = [
            Griff(punkt: CGPoint(x: r.minX, y: r.minY), links: true, oben: true),
            Griff(punkt: CGPoint(x: r.maxX, y: r.minY), rechts: true, oben: true),
            Griff(punkt: CGPoint(x: r.maxX, y: r.maxY), rechts: true, unten: true),
            Griff(punkt: CGPoint(x: r.minX, y: r.maxY), links: true, unten: true),
        ]
        if mitKanten {
            g += [
                Griff(punkt: CGPoint(x: r.midX, y: r.minY), oben: true),
                Griff(punkt: CGPoint(x: r.maxX, y: r.midY), rechts: true),
                Griff(punkt: CGPoint(x: r.midX, y: r.maxY), unten: true),
                Griff(punkt: CGPoint(x: r.minX, y: r.midY), links: true),
            ]
        }
        return g
    }

    /// Anfasser unter einem Punkt der Ansicht. Die Reichweite gilt in Punkten
    /// der Ansicht, damit sie bei jeder Vergrößerung gleich gut zu treffen ist.
    private func griff(an ansicht: CGPoint, fuer f: Form) -> Griff? {
        let reichweite: CGFloat = 9
        var bester: (Griff, CGFloat)?
        for g in griffe(f) {
            let m = nachView(g.punkt)
            let d = hypot(m.x - ansicht.x, m.y - ansicht.y)
            if d <= reichweite, d < (bester?.1 ?? .infinity) { bester = (g, d) }
        }
        return bester?.0
    }

    private func griffeZeichnen(_ f: Form) {
        for g in griffe(f) {
            let m = nachView(g.punkt)
            let r = CGRect(x: m.x - 5, y: m.y - 5, width: 10, height: 10)
            NSGraphicsContext.saveGraphicsState()
            let schatten = NSShadow()
            schatten.shadowColor = NSColor.black.withAlphaComponent(0.45)
            schatten.shadowOffset = NSSize(width: 0, height: -1)
            schatten.shadowBlurRadius = 2
            schatten.set()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: r).fill()
            NSGraphicsContext.restoreGraphicsState()
            Theme.gruen.setStroke()
            let rand = NSBezierPath(ovalIn: r.insetBy(dx: 0.75, dy: 0.75))
            rand.lineWidth = 1.5
            rand.stroke()
        }
    }

    private func groesseAendern(_ f: Form, griff g: Griff, auf p: CGPoint, gleichmaessig: Bool) {
        switch f.werkzeug {
        case .linie, .pfeil:
            if g.ende == 0 {
                f.p1 = gleichmaessig ? rasten45(von: f.p2, nach: p) : p
            } else {
                f.p2 = gleichmaessig ? rasten45(von: f.p1, nach: p) : p
            }

        case .marker:
            // Der Marker bleibt auf seiner Zeile: nur die Enden wandern waagerecht
            guard let y = griffStartPunkte.first?.y else { return }
            let xs = griffStartPunkte.map { $0.x }
            var l = xs.min() ?? p.x, r = xs.max() ?? p.x
            if g.ende == 0 { l = p.x } else { r = p.x }
            f.punkte = [CGPoint(x: min(l, r), y: y), CGPoint(x: max(l, r), y: y)]
            f.p1 = f.punkte[0]
            f.p2 = f.punkte[1]

        case .stift:
            let r0 = griffStartRahmen
            let neu = neuerRahmen(r0, griff: g, auf: p, gleichmaessig: gleichmaessig)
            let sx = r0.width > 0 ? neu.width / r0.width : 1
            let sy = r0.height > 0 ? neu.height / r0.height : 1
            f.punkte = griffStartPunkte.map {
                CGPoint(x: neu.minX + ($0.x - r0.minX) * sx, y: neu.minY + ($0.y - r0.minY) * sy)
            }

        default:
            let neu = neuerRahmen(griffStartRahmen, griff: g, auf: p, gleichmaessig: gleichmaessig)
            f.p1 = CGPoint(x: neu.minX, y: neu.minY)
            f.p2 = CGPoint(x: neu.maxX, y: neu.maxY)
        }
    }

    /// Neuer Rahmen beim Ziehen an einem Anfasser. Die gegenüberliegende Seite
    /// bleibt stehen; mit Umschalt behalten Ecken das Seitenverhältnis, damit
    /// ein Quadrat ein Quadrat bleibt.
    private func neuerRahmen(_ r0: CGRect, griff g: Griff, auf p: CGPoint,
                             gleichmaessig: Bool) -> CGRect {
        if g.istEcke {
            let ax = g.links ? r0.maxX : r0.minX
            let ay = g.oben ? r0.maxY : r0.minY
            var w = p.x - ax, h = p.y - ay
            if gleichmaessig, r0.width > 0, r0.height > 0 {
                let verhaeltnis = r0.width / r0.height
                if abs(w) / verhaeltnis > abs(h) {
                    h = (h < 0 ? -1 : 1) * abs(w) / verhaeltnis
                } else {
                    w = (w < 0 ? -1 : 1) * abs(h) * verhaeltnis
                }
            }
            return CGRect(x: min(ax, ax + w), y: min(ay, ay + h), width: abs(w), height: abs(h))
        }
        var minX = r0.minX, maxX = r0.maxX, minY = r0.minY, maxY = r0.maxY
        if g.links  { minX = p.x }
        if g.rechts { maxX = p.x }
        if g.oben   { minY = p.y }
        if g.unten  { maxY = p.y }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY),
                      width: abs(maxX - minX), height: abs(maxY - minY))
    }

    /// Hält eine Linie auf ein Vielfaches von 45°.
    private func rasten45(von a: CGPoint, nach p: CGPoint) -> CGPoint {
        let dx = p.x - a.x, dy = p.y - a.y
        let w = (atan2(dy, dx) / (.pi/4)).rounded() * (.pi/4)
        let l = sqrt(dx*dx + dy*dy)
        return CGPoint(x: a.x + cos(w)*l, y: a.y + sin(w)*l)
    }

    /// Umriss der Freihandpunkte ohne Strichbreite — dort sitzen die Anfasser.
    private func punkteRahmen(_ f: Form) -> CGRect? {
        guard let erster = f.punkte.first else { return nil }
        var minX = erster.x, maxX = erster.x, minY = erster.y, maxY = erster.y
        for q in f.punkte {
            minX = min(minX, q.x); maxX = max(maxX, q.x)
            minY = min(minY, q.y); maxY = max(maxY, q.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Ob an dieser Stelle gezeichnet wird. Daneben verschiebt ein Zug das Fenster.
    func istZeichenbereich(_ punkt: CGPoint) -> Bool { bildRect.contains(punkt) }

    // MARK: – Textwerkzeug

    private func textFeldOeffnen(bei p: CGPoint) {
        let schrift = NSFont.systemFont(ofSize: max(11, Render.schriftFuer(staerke).pointSize * skala),
                                        weight: .semibold)
        let feld = NSTextField(frame: NSRect(x: nachView(p).x, y: nachView(p).y,
                                             width: 240, height: schrift.pointSize * 1.6))
        feld.font = schrift
        feld.textColor = farbe
        feld.backgroundColor = NSColor.black.withAlphaComponent(0.45)
        feld.drawsBackground = true
        feld.isBordered = false
        feld.focusRingType = .none
        feld.placeholderString = "Text …"
        feld.target = self
        feld.action = #selector(textFertig)
        addSubview(feld)
        window?.makeFirstResponder(feld)
        textFeld = feld
        textPosition = p
    }

    private var textPosition: CGPoint = .zero

    /// Lagen der erkannten Textzeilen, für das Einrasten des Markers.
    private var textzeilen: [CGRect] = []
    /// Höhe, auf die der laufende Markerzug eingerastet ist.
    private var markerHoehe: CGFloat?

    /// Freiraum, den Titelleiste und Glasleiste beanspruchen.
    var einzugOben: CGFloat = 0
    var einzugUnten: CGFloat = 0

    @objc private func textFertig() { textCommit() }

    /// Übernimmt den Text als Form und schließt das Eingabefeld.
    func textCommit() {
        guard let feld = textFeld else { return }
        let inhalt = feld.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        textFeld = nil
        feld.removeFromSuperview()
        window?.makeFirstResponder(self)
        guard !inhalt.isEmpty else { return }
        doc.merken()
        let f = Form(werkzeug: .text, farbe: farbe, staerke: staerke,
                     p1: textPosition, p2: textPosition)
        f.text = inhalt
        doc.formen.append(f)
        delegat?.zustandGeaendert()
        needsDisplay = true
    }

    // MARK: – Zeiger

    private func cursorSetzen() {
        window?.invalidateCursorRects(for: self)
    }

    /// Nur über dem Bild ein Werkzeugzeiger. Die Fläche reicht unter die
    /// Glasleiste, dort gehört der gewöhnliche Mauszeiger hin.
    override func resetCursorRects() {
        let c: NSCursor
        switch werkzeug {
        case .auswahl: c = .arrow
        case .text:    c = .iBeam
        default:       c = .crosshair
        }
        addCursorRect(bildRect, cursor: c)
    }
}
