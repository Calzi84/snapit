import AppKit
import CoreGraphics

/// Bildschirmaufnahme über das Systemwerkzeug screencapture. Das erspart
/// eigene Overlay-Fenster und liefert die vertraute Auswahl mit Lupe,
/// Leertaste für Fenster und Esc zum Abbrechen.
enum Aufnahme {

    enum Art { case bereich, fenster, vollbild }

    /// Prüft die Freigabe zur Bildschirmaufnahme, bevor screencapture startet.
    /// Ohne sie liefert screencapture kommentarlos nichts, und der Nutzer sieht
    /// nur, dass „nichts passiert".
    @discardableResult
    static func berechtigungPruefen() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        // Löst beim ersten Mal den Systemdialog aus; danach nur noch false.
        if CGRequestScreenCaptureAccess() { return true }

        let a = NSAlert()
        a.messageText = "Snap it darf den Bildschirm nicht aufnehmen"
        a.informativeText = """
            Die Freigabe fehlt oder gehört noch zu einer früheren Fassung der App.

            Setze in den Systemeinstellungen unter „Bildschirm- & Systemaudioaufnahme"             den Haken bei Snap it. Steht dort bereits ein Haken, nimm ihn einmal weg             und setze ihn neu — dann verbindet macOS ihn mit der laufenden Fassung.
            """
        a.addButton(withTitle: "Einstellungen öffnen")
        a.addButton(withTitle: "Später")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn,
           let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(u)
        }
        return false
    }

    static func starten(_ art: Art, fertig: @escaping (Dokument?) -> Void) {
        guard berechtigungPruefen() else { fertig(nil); return }
        let ziel = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snapit-\(UUID().uuidString).png")

        var argumente = ["-x"]                      // ohne Auslöseton
        switch art {
        case .bereich:  argumente += ["-i", "-o"]   // interaktiv, ohne Fensterschatten
        case .fenster:  argumente += ["-i", "-w", "-o"]
        case .vollbild: argumente += []
        }
        argumente.append(ziel.path)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = argumente
        p.terminationHandler = { _ in
            DispatchQueue.main.async {
                defer { try? FileManager.default.removeItem(at: ziel) }
                guard FileManager.default.fileExists(atPath: ziel.path),
                      let doc = laden(ziel) else { fertig(nil); return }
                fertig(doc)
            }
        }
        do { try p.run() } catch { fertig(nil) }
    }

    /// Lädt ein PNG und merkt sich, wie viele Pixel auf einen Punkt kommen.
    static func laden(_ url: URL) -> Dokument? {
        guard let daten = try? Data(contentsOf: url),
              let rep = NSBitmapImageRep(data: daten) else { return nil }
        return ausRep(rep)
    }

    static func ausZwischenablage() -> Dokument? {
        let pb = NSPasteboard.general
        guard let daten = pb.data(forType: .png) ?? pb.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: daten) else { return nil }
        return ausRep(rep)
    }

    private static func ausRep(_ rep: NSBitmapImageRep) -> Dokument? {
        let pw = CGFloat(rep.pixelsWide), ph = CGFloat(rep.pixelsHigh)
        guard pw > 0, ph > 0 else { return nil }
        let faktor = rep.size.width > 0 ? (pw / rep.size.width).rounded() : 2
        rep.size = NSSize(width: pw, height: ph)
        let bild = NSImage(size: NSSize(width: pw, height: ph))
        bild.addRepresentation(rep)
        return Dokument(bild: bild, faktor: max(1, faktor))
    }
}
