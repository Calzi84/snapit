import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusEintrag: NSStatusItem?
    private var hotkey: Hotkey?
    private var einstellungenFenster: EinstellungenFenster?
    private var ideenFenster: IdeenFenster?

    func applicationDidFinishLaunching(_ n: Notification) {
        Einstellungen.geteilt.ordnerSicherstellen()
        menueleisteAufbauen()
        hotkeySetzen()
        NotificationCenter.default.addObserver(self, selector: #selector(hotkeySetzen),
                                              name: Einstellungen.geaendert, object: nil)
        Aktualisierung.beimStartPruefen()
    }

    // MARK: – Menüleiste

    private func menueleisteAufbauen() {
        let eintrag = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        eintrag.button?.image = Symbolbild.menueleiste()
        eintrag.button?.toolTip = "Snap it"

        let menue = NSMenu()
        menue.addItem(punkt("Ausschnitt aufnehmen", #selector(bereich), kuerzel: Einstellungen.geteilt.hotkeyText))
        menue.addItem(punkt("Fenster aufnehmen", #selector(fenster)))
        menue.addItem(punkt("Ganzer Bildschirm", #selector(vollbild)))
        menue.addItem(.separator())
        menue.addItem(punkt("Aus Zwischenablage öffnen", #selector(ausZwischenablage)))
        menue.addItem(punkt("Ideen …", #selector(ideenZeigen)))
        menue.addItem(punkt("Ideen-Ordner öffnen", #selector(ideenOrdnerOeffnen)))
        menue.addItem(punkt("Bilder-Ordner öffnen", #selector(bilderOrdnerOeffnen)))
        menue.addItem(.separator())
        menue.addItem(punkt("Einstellungen …", #selector(einstellungenZeigen)))
        menue.addItem(punkt("Nach Updates suchen …", #selector(updatePruefen)))
        menue.addItem(.separator())
        menue.addItem(punkt("Snap it beenden", #selector(beenden)))
        eintrag.menu = menue
        statusEintrag = eintrag
    }

    private func punkt(_ titel: String, _ aktion: Selector, kuerzel: String = "") -> NSMenuItem {
        let p = NSMenuItem(title: titel, action: aktion, keyEquivalent: "")
        p.target = self
        if !kuerzel.isEmpty {
            // Nur zur Anzeige — ausgelöst wird über das systemweite Kürzel
            let attr = NSMutableAttributedString(string: titel + "   ")
            attr.append(NSAttributedString(string: kuerzel, attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            ]))
            p.attributedTitle = attr
        }
        return p
    }

    /// Menüpunkt-Beschriftung neu setzen, wenn sich das Kürzel geändert hat.
    private func menueAuffrischen() {
        guard let erster = statusEintrag?.menu?.item(at: 0) else { return }
        let attr = NSMutableAttributedString(string: "Ausschnitt aufnehmen   ")
        attr.append(NSAttributedString(string: Einstellungen.geteilt.hotkeyText, attributes: [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        ]))
        erster.attributedTitle = attr
    }

    // MARK: – Tastenkürzel

    @objc private func hotkeySetzen() {
        hotkey = nil
        let e = Einstellungen.geteilt
        hotkey = Hotkey(code: e.hotkeyCode, modifier: e.hotkeyModifier) { [weak self] in
            self?.bereich()
        }
        menueAuffrischen()
        if hotkey == nil {
            hinweis("Kürzel \(e.hotkeyText) ist belegt",
                    "Ein anderes Programm oder macOS selbst nutzt diese Tastenkombination schon. "
                    + "Wähle in den Einstellungen eine andere — aufnehmen lässt sich weiterhin über dieses Menü.")
        }
    }

    // MARK: – Aufnahme

    @objc private func bereich()   { aufnehmen(.bereich) }
    @objc private func fenster()   { aufnehmen(.fenster) }
    @objc private func vollbild()  { aufnehmen(.vollbild) }

    private func aufnehmen(_ art: Aufnahme.Art) {
        Aufnahme.starten(art) { doc in
            guard let doc else { return }   // Esc gedrückt oder nichts ausgewählt
            EditorFenster(doc: doc).zeigen()
        }
    }

    @objc private func ausZwischenablage() {
        guard let doc = Aufnahme.ausZwischenablage() else {
            hinweis("Kein Bild in der Zwischenablage",
                    "Kopiere zuerst ein Bild, dann öffnet Snap it es hier zum Bearbeiten.")
            return
        }
        EditorFenster(doc: doc).zeigen()
    }

    // MARK: – Fenster

    @objc private func einstellungenZeigen() {
        if einstellungenFenster == nil { einstellungenFenster = EinstellungenFenster() }
        NSApp.activate(ignoringOtherApps: true)
        einstellungenFenster?.showWindow(nil)
        einstellungenFenster?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func ideenZeigen() {
        if ideenFenster == nil { ideenFenster = IdeenFenster() }
        NSApp.activate(ignoringOtherApps: true)
        ideenFenster?.showWindow(nil)
        ideenFenster?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func ideenOrdnerOeffnen() {
        NSWorkspace.shared.open(Einstellungen.geteilt.ideenOrdner)
    }

    @objc private func bilderOrdnerOeffnen() {
        NSWorkspace.shared.open(Einstellungen.geteilt.bilderOrdner)
    }

    @objc private func updatePruefen() { Aktualisierung.pruefen(sichtbar: true) }

    @objc private func beenden() { NSApp.terminate(nil) }

    private func hinweis(_ titel: String, _ text: String) {
        let a = NSAlert()
        a.messageText = titel
        a.informativeText = text
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
