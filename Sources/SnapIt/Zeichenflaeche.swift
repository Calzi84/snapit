import AppKit

protocol ZeichenflaecheDelegat: AnyObject {
    func zustandGeaendert()
    func werkzeugZuruecksetzen()
}

/// Die Zeichenfläche: zeigt das Bild und nimmt alle Mauseingaben entgegen.
/// Sie ist geflippt, damit Bildkoordinaten (Ursprung oben links) direkt passen.
final class Zeichenflaeche: NSView {

    weak var delegat: ZeichenflaecheDelegat?
    var doc: Dokument
    var werkzeug: Werkzeug = .pfeil { didSet { auswahl = nil; cursorSetzen(); needsDisplay = true } }
    var farbe: NSColor = Theme.palette[0]
    var staerkeUI: CGFloat = 4

    /// Strichstärke in Bildpixeln — bei Retina-Aufnahmen doppelt so groß wie im Regler.
    private var staerke: CGFloat { staerkeUI * doc.faktor }

    private var aktuelle: Form?
    private var auswahl: Form? { didSet { needsDisplay = true } }
    private var zieheAb: CGPoint = .zero
    private var hatGemerkt = false
    private var textFeld: NSTextField?
    private var naechsteNummer = 1

    init(doc: Dokument) {
        self.doc = doc
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

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

    private func nachBild(_ p: CGPoint) -> CGPoint {
        let r = bildRect, s = max(skala, 0.0001)
        return CGPoint(x: (p.x - r.minX)/s, y: (p.y - r.minY)/s)
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
        for f in doc.formen { Render.zeichne(f, doc: doc) }
        if let a = aktuelle, a.werkzeug != .zuschnitt { Render.zeichne(a, doc: doc) }
        ctx.restoreGraphicsState()

        if let a = auswahl {
            let r = nachView(a.rahmen(schrift: Render.schriftFuer(a.staerke))).insetBy(dx: -3, dy: -3)
            Theme.gruen.withAlphaComponent(0.95).setStroke()
            let p = NSBezierPath(rect: r)
            p.lineWidth = 1.5
            p.setLineDash([5, 4], count: 2, phase: 0)
            p.stroke()
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
        let p = nachBild(roh)
        hatGemerkt = false

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
            naechsteNummer += 1
            doc.formen.append(f)
            delegat?.zustandGeaendert()
            needsDisplay = true

        case .stift, .marker:
            let f = Form(werkzeug: werkzeug, farbe: farbe, staerke: staerke, p1: p, p2: p)
            f.punkte = [p]
            aktuelle = f

        default:
            aktuelle = Form(werkzeug: werkzeug, farbe: farbe, staerke: staerke, p1: p, p2: p)
        }
    }

    override func mouseDragged(with e: NSEvent) {
        let p = nachBild(convert(e.locationInWindow, from: nil))

        if werkzeug == .auswahl {
            guard let a = auswahl else { return }
            if !hatGemerkt { doc.merken(); hatGemerkt = true }
            a.verschieben(dx: p.x - zieheAb.x, dy: p.y - zieheAb.y)
            zieheAb = p
            needsDisplay = true
            return
        }

        guard let f = aktuelle else { return }
        if f.werkzeug == .stift || f.werkzeug == .marker {
            f.punkte.append(p)
        } else {
            var ziel = p
            // Shift hält Linien und Pfeile auf 45°, Rechtecke und Ellipsen quadratisch
            if e.modifierFlags.contains(.shift) {
                if f.werkzeug == .linie || f.werkzeug == .pfeil {
                    let dx = p.x - f.p1.x, dy = p.y - f.p1.y
                    let w = (atan2(dy, dx) / (.pi/4)).rounded() * (.pi/4)
                    let l = sqrt(dx*dx + dy*dy)
                    ziel = CGPoint(x: f.p1.x + cos(w)*l, y: f.p1.y + sin(w)*l)
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
        defer { aktuelle = nil; needsDisplay = true }
        if werkzeug == .auswahl {
            if hatGemerkt { delegat?.zustandGeaendert() }
            return
        }
        guard let f = aktuelle else { return }

        if f.werkzeug == .zuschnitt {
            doc.zuschneiden(auf: f.rechteck)
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

    func nummernZuruecksetzen() { naechsteNummer = 1 }

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

    override func resetCursorRects() {
        let c: NSCursor
        switch werkzeug {
        case .auswahl: c = .arrow
        case .text:    c = .iBeam
        default:       c = .crosshair
        }
        addCursorRect(bounds, cursor: c)
    }
}
