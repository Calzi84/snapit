import AppKit
import Carbon.HIToolbox

/// Feld, das ein Tastenkürzel aufnimmt: anklicken, Tasten drücken, fertig.
final class KuerzelFeld: NSView {

    var beiAenderung: ((UInt32, UInt32) -> Void)?
    private var code: UInt32
    private var modifier: UInt32
    private var lauscht = false { didSet { needsDisplay = true } }
    private var monitor: Any?

    init(code: UInt32, modifier: UInt32) {
        self.code = code
        self.modifier = modifier
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { if let m = monitor { NSEvent.removeMonitor(m) } }

    override func draw(_ dirty: NSRect) {
        let hg = lauscht ? Theme.gruen.withAlphaComponent(0.18) : NSColor.white.withAlphaComponent(0.07)
        hg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        (lauscht ? Theme.gruen : NSColor.white.withAlphaComponent(0.16)).setStroke()
        let rand = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        rand.lineWidth = 1
        rand.stroke()

        let text = lauscht ? "Tasten drücken …" : Tastatur.beschreibung(code: code, carbonModifier: modifier)
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: lauscht ? .regular : .semibold),
            .foregroundColor: lauscht ? Theme.gruen : NSColor.labelColor,
        ]
        let g = (text as NSString).size(withAttributes: attr)
        (text as NSString).draw(at: CGPoint(x: (bounds.width - g.width)/2,
                                            y: (bounds.height - g.height)/2), withAttributes: attr)
    }

    override func mouseDown(with e: NSEvent) { lauscht ? beenden() : starten() }

    private func starten() {
        lauscht = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] e in
            guard let self, self.lauscht else { return e }
            if e.type == .flagsChanged { return nil }
            if e.keyCode == 53 { self.beenden(); return nil }        // Esc bricht ab

            let m = Tastatur.carbonModifier(e.modifierFlags)
            guard m != 0 else {                                       // ohne Modifier zu riskant
                NSSound.beep(); return nil
            }
            self.code = UInt32(e.keyCode)
            self.modifier = m
            self.beiAenderung?(self.code, self.modifier)
            self.beenden()
            return nil
        }
    }

    private func beenden() {
        lauscht = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

final class EinstellungenFenster: NSWindowController, NSTextFieldDelegate {

    private let bilderPfad = NSTextField(labelWithString: "")
    private let ideenPfad = NSTextField(labelWithString: "")
    private let updateFeld = NSTextField()

    private static let breite: CGFloat = 580
    private static let hoehe: CGFloat = 470

    init() {
        let fenster = NSWindow(contentRect: NSRect(x: 0, y: 0,
                                                   width: EinstellungenFenster.breite,
                                                   height: EinstellungenFenster.hoehe),
                               styleMask: [.titled, .closable], backing: .buffered, defer: false)
        fenster.title = "Snap it – Einstellungen"
        fenster.center()
        fenster.appearance = NSAppearance(named: .darkAqua)
        super.init(window: fenster)
        aufbauen()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func aufbauen() {
        guard let inhalt = window?.contentView else { return }
        var y = EinstellungenFenster.hoehe - 42

        func ueberschrift(_ t: String) {
            let l = NSTextField(labelWithString: t)
            l.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            l.textColor = .secondaryLabelColor
            l.frame = NSRect(x: 24, y: y, width: 400, height: 16)
            inhalt.addSubview(l)
            y -= 28
        }

        func zeile(_ titel: String) {
            let l = NSTextField(labelWithString: titel)
            l.font = NSFont.systemFont(ofSize: 13)
            l.frame = NSRect(x: 24, y: y, width: 160, height: 18)
            inhalt.addSubview(l)
        }

        func ordnerZeile(_ titel: String, feld: NSTextField, wahl: Selector, standard: Selector) {
            zeile(titel)
            feld.font = NSFont.systemFont(ofSize: 11)
            feld.textColor = .secondaryLabelColor
            feld.lineBreakMode = .byTruncatingMiddle
            feld.frame = NSRect(x: 24, y: y - 20, width: 330, height: 16)
            inhalt.addSubview(feld)

            let waehlen = NSButton(title: "Wählen …", target: self, action: wahl)
            waehlen.bezelStyle = .rounded
            waehlen.controlSize = .small
            waehlen.frame = NSRect(x: 370, y: y - 8, width: 92, height: 24)
            inhalt.addSubview(waehlen)

            let zurueck = NSButton(title: "Standard", target: self, action: standard)
            zurueck.bezelStyle = .rounded
            zurueck.controlSize = .small
            zurueck.frame = NSRect(x: 468, y: y - 8, width: 88, height: 24)
            inhalt.addSubview(zurueck)
            y -= 48
        }

        func schalter(_ titel: String, an: Bool, aktion: Selector) {
            let s = NSButton(checkboxWithTitle: titel, target: self, action: aktion)
            s.state = an ? .on : .off
            s.frame = NSRect(x: 24, y: y, width: 500, height: 20)
            inhalt.addSubview(s)
            y -= 26
        }

        // — Ablage —
        ueberschrift("ABLAGE")
        ordnerZeile("Screenshots", feld: bilderPfad,
                    wahl: #selector(bilderWaehlen), standard: #selector(bilderStandard))
        ordnerZeile("Ideen", feld: ideenPfad,
                    wahl: #selector(ideenWaehlen), standard: #selector(ideenStandard))

        let notiz = NSTextField(labelWithString: "Standard ist „Bilder › Snap it“. Sichern legt die Datei ohne Rückfrage dort ab — ⇧⌘S fragt nach dem Ort.")
        notiz.font = NSFont.systemFont(ofSize: 11)
        notiz.textColor = .tertiaryLabelColor
        notiz.frame = NSRect(x: 24, y: y + 10, width: 532, height: 16)
        inhalt.addSubview(notiz)
        y -= 26

        // — Kürzel —
        ueberschrift("TASTENKÜRZEL")
        zeile("Ausschnitt aufnehmen")
        let feld = KuerzelFeld(code: Einstellungen.geteilt.hotkeyCode,
                               modifier: Einstellungen.geteilt.hotkeyModifier)
        feld.frame = NSRect(x: 200, y: y - 5, width: 150, height: 28)
        feld.beiAenderung = { code, mod in
            Einstellungen.geteilt.hotkeyCode = code
            Einstellungen.geteilt.hotkeyModifier = mod
        }
        inhalt.addSubview(feld)
        y -= 42

        // — Verhalten —
        ueberschrift("NACH DEM SICHERN")
        schalter("Bild zusätzlich in die Zwischenablage legen",
                 an: Einstellungen.geteilt.nachSichernKopieren, aktion: #selector(kopierenGeschaltet))
        schalter("Datei im Finder zeigen",
                 an: Einstellungen.geteilt.imFinderZeigen, aktion: #selector(finderGeschaltet))
        y -= 14

        // — Updates —
        ueberschrift("UPDATES")
        schalter("Täglich nach neuen Fassungen sehen", an: Aktualisierung.automatisch,
                 aktion: #selector(autoGeschaltet))
        y -= 6

        updateFeld.stringValue = UserDefaults.standard.string(forKey: "updateURL")
            ?? (Bundle.main.infoDictionary?["SnapItUpdateURL"] as? String ?? "")
        updateFeld.placeholderString = "https://raw.githubusercontent.com/…/version.json"
        updateFeld.font = NSFont.systemFont(ofSize: 11)
        updateFeld.frame = NSRect(x: 24, y: y, width: 400, height: 22)
        updateFeld.target = self
        updateFeld.action = #selector(updateURLGeaendert)
        updateFeld.delegate = self
        inhalt.addSubview(updateFeld)

        let jetzt = NSButton(title: "Jetzt prüfen", target: self, action: #selector(jetztPruefen))
        jetzt.frame = NSRect(x: 434, y: y - 3, width: 122, height: 28)
        jetzt.bezelStyle = .rounded
        inhalt.addSubview(jetzt)
        y -= 24

        let version = NSTextField(labelWithString: "Installiert: Version \(Aktualisierung.eigeneVersion)")
        version.font = NSFont.systemFont(ofSize: 11)
        version.textColor = .tertiaryLabelColor
        version.frame = NSRect(x: 24, y: y, width: 400, height: 16)
        inhalt.addSubview(version)

        pfadeAuffrischen()
    }

    private func pfadeAuffrischen() {
        bilderPfad.stringValue = kurz(Einstellungen.geteilt.bilderOrdner)
        ideenPfad.stringValue = kurz(Einstellungen.geteilt.ideenOrdner)
    }

    private func kurz(_ u: URL) -> String {
        let heim = FileManager.default.homeDirectoryForCurrentUser.path
        return u.path.hasPrefix(heim) ? "~" + u.path.dropFirst(heim.count) : u.path
    }

    private func ordnerWaehlen(_ start: URL, fertig: @escaping (URL) -> Void) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.directoryURL = start
        p.prompt = "Auswählen"
        p.beginSheetModal(for: window!) { a in
            if a == .OK, let u = p.url { fertig(u) }
        }
    }

    @objc private func bilderWaehlen() {
        ordnerWaehlen(Einstellungen.geteilt.bilderOrdner) { u in
            Einstellungen.geteilt.bilderOrdner = u
            self.pfadeAuffrischen()
        }
    }
    @objc private func ideenWaehlen() {
        ordnerWaehlen(Einstellungen.geteilt.ideenOrdner) { u in
            Einstellungen.geteilt.ideenOrdner = u
            self.pfadeAuffrischen()
        }
    }
    @objc private func bilderStandard() {
        UserDefaults.standard.removeObject(forKey: "bilderOrdner")
        Einstellungen.geteilt.ordnerSicherstellen()
        pfadeAuffrischen()
    }
    @objc private func ideenStandard() {
        UserDefaults.standard.removeObject(forKey: "ideenOrdner")
        Einstellungen.geteilt.ordnerSicherstellen()
        pfadeAuffrischen()
    }
    @objc private func kopierenGeschaltet(_ s: NSButton) { Einstellungen.geteilt.nachSichernKopieren = s.state == .on }
    @objc private func finderGeschaltet(_ s: NSButton) { Einstellungen.geteilt.imFinderZeigen = s.state == .on }
    @objc private func autoGeschaltet(_ s: NSButton) { Aktualisierung.automatisch = s.state == .on }
    /// Auch ohne Eingabetaste sichern — sonst geht die Adresse beim Schließen verloren.
    func controlTextDidChange(_ n: Notification) { updateURLGeaendert() }
    func controlTextDidEndEditing(_ n: Notification) { updateURLGeaendert() }

    @objc private func updateURLGeaendert() {
        UserDefaults.standard.set(updateFeld.stringValue.trimmingCharacters(in: .whitespaces), forKey: "updateURL")
    }
    @objc private func jetztPruefen() {
        updateURLGeaendert()
        Aktualisierung.pruefen(sichtbar: true)
    }
}
