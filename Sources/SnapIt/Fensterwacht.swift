import AppKit

/// Schaltet das Dock-Symbol je nachdem, ob Fenster offen sind.
///
/// Snap it lebt in der Menüleiste und taucht deshalb normalerweise nicht im
/// Dock auf. Sobald ein Fenster offen ist, fehlt damit aber der Weg zurück,
/// wenn es hinter andere Fenster rutscht — also wird die App für diese Zeit
/// zu einer gewöhnlichen App mit Dock-Symbol.
enum Fensterwacht {

    private static var offen = 0

    static func geoeffnet() {
        offen += 1
        anpassen()
    }

    static func geschlossen() {
        offen = max(0, offen - 1)
        // Kurz warten: Wird ein Fenster geschlossen und sofort ein neues
        // geöffnet, soll das Dock-Symbol nicht flackern.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { anpassen() }
    }

    private static func anpassen() {
        let ziel: NSApplication.ActivationPolicy = offen > 0 ? .regular : .accessory
        guard NSApp.activationPolicy() != ziel else { return }
        NSApp.setActivationPolicy(ziel)
        if ziel == .regular {
            NSApp.activate(ignoringOtherApps: true)
            // Der Wechsel schiebt Fenster gelegentlich nach hinten
            NSApp.windows.filter { $0.isVisible }.forEach { $0.orderFrontRegardless() }
        }
    }

    /// Schlankes Hauptmenü für die Zeit, in der die App im Dock steht.
    static func menueAufbauen() {
        let haupt = NSMenu()

        let appEintrag = NSMenuItem()
        haupt.addItem(appEintrag)
        let appMenue = NSMenu(title: "Snap it")
        appMenue.addItem(withTitle: "Über Snap it", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenue.addItem(.separator())
        appMenue.addItem(withTitle: "Snap it ausblenden", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenue.addItem(withTitle: "Andere ausblenden", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "H")
        appMenue.addItem(.separator())
        appMenue.addItem(withTitle: "Snap it beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appEintrag.submenu = appMenue

        let fensterEintrag = NSMenuItem()
        haupt.addItem(fensterEintrag)
        let fensterMenue = NSMenu(title: "Fenster")
        fensterMenue.addItem(withTitle: "Zoomen", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        fensterMenue.addItem(withTitle: "Im Dock ablegen", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        fensterMenue.addItem(.separator())
        fensterMenue.addItem(withTitle: "Alle nach vorne bringen", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        fensterEintrag.submenu = fensterMenue
        NSApp.windowsMenu = fensterMenue

        NSApp.mainMenu = haupt
    }
}
