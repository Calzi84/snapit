import AppKit

/// Symbol mit Ausweichnamen laden — SF-Symbole heißen je nach
/// Systemversion unterschiedlich.
func symbol(_ namen: [String], groesse: CGFloat = 15, gewicht: NSFont.Weight = .medium) -> NSImage? {
    for n in namen {
        if let b = NSImage(systemSymbolName: n, accessibilityDescription: nil) {
            let k = NSImage.SymbolConfiguration(pointSize: groesse, weight: gewicht)
            return b.withSymbolConfiguration(k)
        }
    }
    return nil
}

/// Werkzeugknopf im Stil von macOS 26: rund, ohne Rahmen, aktiv als
/// gefüllte Kapsel.
final class WerkzeugKnopf: NSButton {
    var aktiv = false { didSet { needsDisplay = true } }
    private var unterMaus = false { didSet { needsDisplay = true } }

    init(bild: NSImage?, hinweis: String) {
        super.init(frame: .zero)
        image = bild
        imagePosition = .imageOnly
        isBordered = false
        wantsLayer = true
        toolTip = hinweis
        contentTintColor = Theme.schriftMatt
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirty: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 3)
        if aktiv {
            Theme.gruen.setFill()
            NSBezierPath(roundedRect: r, xRadius: r.height/2, yRadius: r.height/2).fill()
        } else if unterMaus && isEnabled {
            NSColor.white.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: r, xRadius: r.height/2, yRadius: r.height/2).fill()
        }
        contentTintColor = aktiv ? Render.kontrastfarbe(zu: Theme.gruen)
                                 : (unterMaus ? Theme.schrift : Theme.schriftMatt)
        super.draw(dirty)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInActiveApp],
                                       owner: self))
    }
    override func mouseEntered(with e: NSEvent) { unterMaus = true }
    override func mouseExited(with e: NSEvent) { unterMaus = false }
}

final class FarbKnopf: NSButton {
    let farbe: NSColor
    var aktiv = false { didSet { needsDisplay = true } }

    init(farbe: NSColor) {
        self.farbe = farbe
        super.init(frame: .zero)
        isBordered = false
        title = ""
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirty: NSRect) {
        let r = bounds.insetBy(dx: aktiv ? 5 : 4.5, dy: aktiv ? 5 : 4.5)
        let schatten = NSShadow()
        schatten.shadowColor = NSColor.black.withAlphaComponent(0.35)
        schatten.shadowOffset = NSSize(width: 0, height: -1)
        schatten.shadowBlurRadius = 2
        NSGraphicsContext.saveGraphicsState()
        schatten.set()
        farbe.setFill()
        NSBezierPath(ovalIn: r).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.28).setStroke()
        let glanz = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
        glanz.lineWidth = 1
        glanz.stroke()

        if aktiv {
            Theme.schrift.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
            ring.lineWidth = 1.8
            ring.stroke()
        }
    }
}

/// Beschrifteter Knopf in Kapselform.
final class AktionsKnopf: NSButton {
    enum Stil { case still, betont }
    private let stil: Stil
    private var unterMaus = false { didSet { needsDisplay = true } }

    init(titel: String, symbolName: [String] = [], stil: Stil = .still) {
        self.stil = stil
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        if let b = symbol(symbolName, groesse: 12) { image = b; imagePosition = .imageLeading }
        let farbe: NSColor = stil == .betont ? Render.kontrastfarbe(zu: Theme.gruen) : Theme.schrift
        attributedTitle = NSAttributedString(string: titel, attributes: [
            .foregroundColor: farbe,
            .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
        ])
        contentTintColor = farbe
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirty: NSRect) {
        let r = bounds
        let fuellung: NSColor
        switch stil {
        case .betont: fuellung = unterMaus ? Theme.gruen.blended(withFraction: 0.12, of: .white) ?? Theme.gruen : Theme.gruen
        case .still:  fuellung = NSColor.white.withAlphaComponent(unterMaus ? 0.18 : 0.10)
        }
        fuellung.setFill()
        NSBezierPath(roundedRect: r, xRadius: r.height/2, yRadius: r.height/2).fill()
        if stil == .still {
            NSColor.white.withAlphaComponent(0.14).setStroke()
            let rand = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5),
                                    xRadius: r.height/2, yRadius: r.height/2)
            rand.lineWidth = 1
            rand.stroke()
        }
        super.draw(dirty)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self))
    }
    override func mouseEntered(with e: NSEvent) { unterMaus = true }
    override func mouseExited(with e: NSEvent) { unterMaus = false }
}

/// Schwebende Glasleiste am unteren Rand des Editors.
final class Leiste: NSView {

    enum Aktion { case zurueck, vor, text, idee, verwerfen, kopieren, sichern }

    var beiWerkzeug: ((Werkzeug) -> Void)?
    var beiFarbe: ((Int) -> Void)?
    var beiStaerke: ((CGFloat, Bool) -> Void)?
    var beiAktion: ((Aktion) -> Void)?

    private let glas: NSView
    private var werkzeugKnoepfe: [Werkzeug: WerkzeugKnopf] = [:]
    private var farbKnoepfe: [FarbKnopf] = []
    private let regler = NSSlider()
    private let staerkeZahl = NSTextField(labelWithString: "4")
    private let zurueckKnopf: WerkzeugKnopf
    private let vorKnopf: WerkzeugKnopf
    private let textKnopf: WerkzeugKnopf
    private let ideeKnopf: WerkzeugKnopf
    private let verwerfenKnopf: WerkzeugKnopf
    private let kopierenKnopf: AktionsKnopf
    private let sichernKnopf: AktionsKnopf

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    override init(frame: NSRect) {
        glas = Theme.glas(radius: Theme.leisteHoehe/2)
        zurueckKnopf = WerkzeugKnopf(bild: symbol(["arrow.uturn.backward"]), hinweis: "Zurücknehmen (⌘Z)")
        vorKnopf = WerkzeugKnopf(bild: symbol(["arrow.uturn.forward"]), hinweis: "Wiederholen (⇧⌘Z)")
        textKnopf = WerkzeugKnopf(bild: symbol(["doc.text.viewfinder", "text.viewfinder"]),
                                  hinweis: "Text im Bild erkennen und kopieren (⌘L)")
        ideeKnopf = WerkzeugKnopf(bild: symbol(["lightbulb"]), hinweis: "Als Idee merken (⌘D)")
        verwerfenKnopf = WerkzeugKnopf(bild: symbol(["trash"]), hinweis: "Verwerfen (Esc)")
        kopierenKnopf = AktionsKnopf(titel: "Kopieren")
        sichernKnopf = AktionsKnopf(titel: "Sichern", stil: .betont)
        super.init(frame: frame)
        wantsLayer = true
        addSubview(glas)
        aufbauen()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func aufbauen() {
        for w in Werkzeug.allCases {
            let k = WerkzeugKnopf(bild: symbol(symbolListe(w)), hinweis: w.titel)
            k.target = self
            k.action = #selector(werkzeugGewaehlt(_:))
            k.tag = Werkzeug.allCases.firstIndex(of: w)!
            addSubview(k)
            werkzeugKnoepfe[w] = k
        }
        for (i, f) in Theme.palette.enumerated() {
            let k = FarbKnopf(farbe: f)
            k.target = self
            k.action = #selector(farbeGewaehlt(_:))
            k.tag = i
            addSubview(k)
            farbKnoepfe.append(k)
        }

        regler.minValue = Theme.staerken.lowerBound
        regler.maxValue = Theme.staerken.upperBound
        regler.doubleValue = Einstellungen.geteilt.standardStaerke
        regler.target = self
        regler.action = #selector(staerkeGeaendert)
        regler.controlSize = .small
        regler.toolTip = "Strichstärke"
        addSubview(regler)

        staerkeZahl.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        staerkeZahl.textColor = Theme.schriftMatt
        staerkeZahl.alignment = .center
        addSubview(staerkeZahl)

        for (k, a) in [(zurueckKnopf, Aktion.zurueck), (vorKnopf, .vor), (textKnopf, .text),
                       (ideeKnopf, .idee), (verwerfenKnopf, .verwerfen)] {
            k.target = self
            k.action = #selector(aktionGewaehlt(_:))
            k.tag = kennung(a)
            addSubview(k)
        }
        for (k, a) in [(kopierenKnopf, Aktion.kopieren), (sichernKnopf, .sichern)] {
            k.target = self
            k.action = #selector(aktionGewaehlt(_:))
            k.tag = kennung(a)
            addSubview(k)
        }

        werkzeugSetzen(.pfeil)
        farbeSetzen(Einstellungen.geteilt.standardFarbe)
        staerkeZahl.stringValue = "\(Int(Einstellungen.geteilt.standardStaerke))"
    }

    private func symbolListe(_ w: Werkzeug) -> [String] {
        switch w {
        case .pixel:  return ["squareshape.split.3x3", "square.grid.3x3.fill", "mosaic"]
        case .weichzeichnen: return ["drop.halffull", "drop.fill", "aqi.medium"]
        case .stift:  return ["pencil.tip", "pencil"]
        case .nummer: return ["1.circle", "number.circle"]
        default:      return [w.symbol]
        }
    }

    private func kennung(_ a: Aktion) -> Int {
        switch a {
        case .zurueck: return 100
        case .vor: return 101
        case .text: return 102
        case .idee: return 103
        case .verwerfen: return 104
        case .kopieren: return 105
        case .sichern: return 106
        }
    }

    private func aktion(_ tag: Int) -> Aktion? {
        switch tag {
        case 100: return .zurueck
        case 101: return .vor
        case 102: return .text
        case 103: return .idee
        case 104: return .verwerfen
        case 105: return .kopieren
        case 106: return .sichern
        default: return nil
        }
    }

    @objc private func werkzeugGewaehlt(_ s: WerkzeugKnopf) {
        let w = Werkzeug.allCases[s.tag]
        werkzeugSetzen(w)
        beiWerkzeug?(w)
    }

    @objc private func farbeGewaehlt(_ s: FarbKnopf) {
        farbeSetzen(s.tag)
        beiFarbe?(s.tag)
    }

    @objc private func staerkeGeaendert() {
        let v = regler.doubleValue.rounded()
        staerkeZahl.stringValue = "\(Int(v))"
        // Der erste Schritt eines Zugs kommt mit dem Mausklick. Daran erkennt
        // die Zeichenfläche, wann sie für die Rücknahme merken muss.
        let beginn = NSApp.currentEvent?.type == .leftMouseDown
        beiStaerke?(CGFloat(v), beginn)
    }

    /// Regler auf einen Wert stellen, etwa wenn eine Form ausgewählt wird.
    func staerkeAnzeigen(_ wert: CGFloat) {
        regler.doubleValue = Double(wert)
        staerkeZahl.stringValue = "\(Int(wert.rounded()))"
    }

    @objc private func aktionGewaehlt(_ s: NSButton) {
        if let a = aktion(s.tag) { beiAktion?(a) }
    }

    func werkzeugSetzen(_ w: Werkzeug) {
        for (t, k) in werkzeugKnoepfe { k.aktiv = (t == w) }
    }

    func farbeSetzen(_ i: Int) {
        for (j, k) in farbKnoepfe.enumerated() { k.aktiv = (j == i) }
    }

    func verlaufSetzen(zurueck: Bool, vor: Bool) {
        zurueckKnopf.isEnabled = zurueck
        vorKnopf.isEnabled = vor
        zurueckKnopf.alphaValue = zurueck ? 1 : 0.3
        vorKnopf.alphaValue = vor ? 1 : 0.3
    }

    /// Kleinste Breite, bei der sich nichts überlappt.
    static let mindestBreite: CGFloat = 1158

    override func layout() {
        super.layout()
        glas.frame = bounds
        let mitte = bounds.height / 2
        let knopf: CGFloat = 32
        var x: CGFloat = 10

        for w in Werkzeug.allCases {
            werkzeugKnoepfe[w]?.frame = CGRect(x: x, y: mitte - knopf/2, width: knopf, height: knopf)
            x += knopf
        }
        x += 14

        for k in farbKnoepfe {
            k.frame = CGRect(x: x, y: mitte - 12, width: 24, height: 24)
            x += 23
        }
        x += 12

        regler.frame = CGRect(x: x, y: mitte - 10, width: 84, height: 20)
        x += 88
        staerkeZahl.frame = CGRect(x: x, y: mitte - 8, width: 18, height: 16)

        // Rechte Gruppe von außen nach innen setzen
        var rechts = bounds.width - 10
        for k in [sichernKnopf, kopierenKnopf] {
            let breite = k.intrinsicContentSize.width + 28
            rechts -= breite
            k.frame = CGRect(x: rechts, y: mitte - 15, width: breite, height: 30)
            rechts -= 7
        }
        rechts -= 4
        for k in [ideeKnopf, verwerfenKnopf, textKnopf, vorKnopf, zurueckKnopf] {
            rechts -= knopf
            k.frame = CGRect(x: rechts, y: mitte - knopf/2, width: knopf, height: knopf)
        }
        needsDisplay = true
    }

    /// Dunkle Fläche unter dem Glas: sie wird mitgeblurrt und hält die Leiste
    /// auch über hellen Screenshots dunkel genug für helle Symbole.
    override func draw(_ dirty: NSRect) {
        NSColor(srgbRed: 0.09, green: 0.10, blue: 0.095, alpha: 0.62).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height/2, yRadius: bounds.height/2).fill()
        super.draw(dirty)
    }
}
