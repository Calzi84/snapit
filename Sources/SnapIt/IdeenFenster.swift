import AppKit

/// Eine Kachel in der Ideen-Übersicht.
final class IdeeKachel: NSView {
    let idee: Idee
    private var vorschau: NSImage?
    private var unterMaus = false { didSet { needsDisplay = true } }
    var beiOeffnen: ((Idee) -> Void)?
    var beiAenderung: (() -> Void)?

    static let breite: CGFloat = 250
    static let hoehe: CGFloat = 200

    init(idee: Idee) {
        self.idee = idee
        super.init(frame: .zero)
        wantsLayer = true
        vorschau = NSImage(contentsOf: idee.url)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirty: NSRect) {
        let karte = bounds.insetBy(dx: 6, dy: 6)
        (unterMaus ? NSColor.white.withAlphaComponent(0.10) : NSColor.white.withAlphaComponent(0.05)).setFill()
        NSBezierPath(roundedRect: karte, xRadius: 10, yRadius: 10).fill()
        (unterMaus ? Theme.gruen.withAlphaComponent(0.7) : NSColor.white.withAlphaComponent(0.10)).setStroke()
        let rand = NSBezierPath(roundedRect: karte.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        rand.lineWidth = 1
        rand.stroke()

        // Bild einpassen
        let bildFeld = CGRect(x: karte.minX + 8, y: karte.minY + 8,
                              width: karte.width - 16, height: karte.height - 62)
        if let b = vorschau, b.size.width > 0, b.size.height > 0 {
            let s = min(bildFeld.width / b.size.width, bildFeld.height / b.size.height)
            let z = CGRect(x: bildFeld.midX - b.size.width*s/2, y: bildFeld.midY - b.size.height*s/2,
                           width: b.size.width*s, height: b.size.height*s)
            NSGraphicsContext.current?.imageInterpolation = .high
            NSBezierPath(roundedRect: z, xRadius: 5, yRadius: 5).setClip()
            b.draw(in: z)
            NSGraphicsContext.current?.saveGraphicsState()
            NSGraphicsContext.current?.restoreGraphicsState()
        }
        NSBezierPath(rect: bounds).setClip()

        let notiz = idee.notiz.isEmpty ? "Ohne Notiz" : idee.notiz
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: idee.notiz.isEmpty ? NSColor.tertiaryLabelColor : NSColor.labelColor,
        ]
        (notiz as NSString).draw(in: CGRect(x: karte.minX + 10, y: karte.maxY - 46,
                                            width: karte.width - 20, height: 17), withAttributes: attr)

        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d. MMM yyyy, HH:mm"
        (f.string(from: idee.datum) as NSString).draw(
            at: CGPoint(x: karte.minX + 10, y: karte.maxY - 26),
            withAttributes: [.font: NSFont.systemFont(ofSize: 10),
                             .foregroundColor: NSColor.tertiaryLabelColor])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }
    override func mouseEntered(with e: NSEvent) { unterMaus = true }
    override func mouseExited(with e: NSEvent) { unterMaus = false }
    override func mouseDown(with e: NSEvent) { if e.clickCount >= 1 { beiOeffnen?(idee) } }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: "Öffnen", action: #selector(oeffnen), keyEquivalent: "").target = self
        m.addItem(withTitle: "Im Finder zeigen", action: #selector(imFinder), keyEquivalent: "").target = self
        m.addItem(withTitle: "Notiz ändern …", action: #selector(notizAendern), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "In den Papierkorb", action: #selector(loeschen), keyEquivalent: "").target = self
        return m
    }

    @objc private func oeffnen() { beiOeffnen?(idee) }
    @objc private func imFinder() { NSWorkspace.shared.activateFileViewerSelecting([idee.url]) }
    @objc private func loeschen() {
        Ideenablage.loeschen(idee)
        beiAenderung?()
    }
    @objc private func notizAendern() {
        let feld = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        feld.stringValue = idee.notiz
        let a = NSAlert()
        a.messageText = "Notiz ändern"
        a.accessoryView = feld
        a.addButton(withTitle: "Sichern")
        a.addButton(withTitle: "Abbrechen")
        if a.runModal() == .alertFirstButtonReturn {
            Ideenablage.notizAendern(idee, auf: feld.stringValue)
            beiAenderung?()
        }
    }
}

/// Übersicht aller gemerkten Ideen.
final class IdeenFenster: NSWindowController {

    private let scroll = NSScrollView()
    private let raster = NSView()
    private let leer = NSTextField(labelWithString: "")

    init() {
        let fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable],
                               backing: .buffered, defer: false)
        fenster.title = "Snap it – Ideen"
        fenster.center()
        fenster.appearance = NSAppearance(named: .darkAqua)
        fenster.backgroundColor = Theme.fensterBG
        super.init(window: fenster)

        raster.autoresizingMask = [.width]
        scroll.documentView = raster
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        scroll.frame = fenster.contentLayoutRect

        leer.font = NSFont.systemFont(ofSize: 13)
        leer.textColor = .tertiaryLabelColor
        leer.alignment = .center
        leer.stringValue = "Noch keine Ideen gemerkt.\n\nIm Editor sichert der Knopf „Idee“ einen Screenshot hierher."
        leer.maximumNumberOfLines = 4

        let inhalt = NSView(frame: fenster.contentLayoutRect)
        inhalt.autoresizingMask = [.width, .height]
        inhalt.addSubview(scroll)
        inhalt.addSubview(leer)
        fenster.contentView = inhalt

        NotificationCenter.default.addObserver(self, selector: #selector(auffrischen),
                                              name: Ideenablage.geaendert, object: nil)
        auffrischen()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        auffrischen()
    }

    @objc private func auffrischen() {
        raster.subviews.forEach { $0.removeFromSuperview() }
        let ideen = Ideenablage.alle()
        leer.isHidden = !ideen.isEmpty
        if let inhalt = window?.contentView {
            leer.frame = NSRect(x: 40, y: inhalt.bounds.midY - 40,
                                width: inhalt.bounds.width - 80, height: 80)
            leer.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        }

        let breite = max(scroll.contentSize.width, IdeeKachel.breite)
        let spalten = max(1, Int(breite / IdeeKachel.breite))
        let zeilen = Int(ceil(Double(ideen.count) / Double(spalten)))
        raster.frame = NSRect(x: 0, y: 0, width: breite,
                              height: max(CGFloat(zeilen) * IdeeKachel.hoehe + 16, scroll.contentSize.height))

        for (i, idee) in ideen.enumerated() {
            let sp = i % spalten, ze = i / spalten
            let k = IdeeKachel(idee: idee)
            k.frame = NSRect(x: CGFloat(sp) * IdeeKachel.breite + 8,
                             y: raster.frame.height - CGFloat(ze + 1) * IdeeKachel.hoehe - 8,
                             width: IdeeKachel.breite, height: IdeeKachel.hoehe)
            k.beiOeffnen = { [weak self] i in self?.oeffnen(i) }
            k.beiAenderung = { [weak self] in self?.auffrischen() }
            raster.addSubview(k)
        }
    }

    private func oeffnen(_ idee: Idee) {
        guard let doc = Aufnahme.laden(idee.url) else { return }
        let fenster = EditorFenster(doc: doc)
        fenster.herkunft = idee.url
        fenster.zeigen()
    }

    func windowDidResize(_ n: Notification) { auffrischen() }
}
