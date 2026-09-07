import AppKit

/// Update-Prüfung über eine Datei im Git-Repo.
///
/// Im Repo liegt `version.json`:
///     { "version": "1.1.0", "notizen": "Was neu ist", "download": "https://…/SnapIt.zip" }
///
/// Die App vergleicht diese Version mit der eigenen. Ist eine neuere da,
/// wird gefragt, ob sie geladen und installiert werden soll. Die Adresse
/// steht in der Info.plist unter `SnapItUpdateURL` und lässt sich damit
/// pro Verteilung ändern, ohne den Code anzufassen.
enum Aktualisierung {

    struct Stand: Decodable {
        let version: String
        let notizen: String?
        let download: String?
    }

    static var eigeneVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static var quelle: URL? {
        if let s = UserDefaults.standard.string(forKey: "updateURL"), !s.isEmpty {
            return URL(string: s)
        }
        if let s = Bundle.main.infoDictionary?["SnapItUpdateURL"] as? String,
           !s.isEmpty, !s.hasPrefix("HIER") {
            return URL(string: s)
        }
        return nil
    }

    static var automatisch: Bool {
        get { UserDefaults.standard.object(forKey: "updateAutomatisch") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "updateAutomatisch") }
    }

    static func beimStartPruefen() {
        guard automatisch else { return }
        // Höchstens einmal am Tag, und nicht sofort beim Anmelden
        let letzte = UserDefaults.standard.double(forKey: "updateZuletzt")
        guard Date().timeIntervalSince1970 - letzte > 20*3600 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { pruefen(sichtbar: false) }
    }

    static func pruefen(sichtbar: Bool) {
        guard let url = quelle else {
            if sichtbar {
                melden("Kein Update-Kanal eingerichtet",
                       "In den Einstellungen lässt sich die Adresse der version.json aus dem Repo eintragen.")
            }
            return
        }
        var anfrage = URLRequest(url: url)
        anfrage.cachePolicy = .reloadIgnoringLocalCacheData
        anfrage.timeoutInterval = 12

        URLSession.shared.dataTask(with: anfrage) { daten, _, fehler in
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "updateZuletzt")
            DispatchQueue.main.async {
                guard let daten, fehler == nil,
                      let stand = try? JSONDecoder().decode(Stand.self, from: daten) else {
                    if sichtbar { melden("Konnte nicht nachsehen", fehler?.localizedDescription ?? "Die Datei war nicht lesbar.") }
                    return
                }
                if neuer(stand.version, als: eigeneVersion) {
                    anbieten(stand)
                } else if sichtbar {
                    melden("Snap it ist aktuell", "Installiert ist Version \(eigeneVersion).")
                }
            }
        }.resume()
    }

    /// Versionsvergleich Stück für Stück, damit 1.10.0 über 1.9.0 liegt.
    static func neuer(_ a: String, als b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func anbieten(_ stand: Stand) {
        let a = NSAlert()
        a.messageText = "Snap it \(stand.version) ist da"
        a.informativeText = (stand.notizen ?? "") + "\n\nInstalliert ist \(eigeneVersion)."
        if stand.download != nil { a.addButton(withTitle: "Laden und installieren") }
        a.addButton(withTitle: "Später")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn,
              let d = stand.download, let url = URL(string: d) else { return }
        installieren(von: url)
    }

    private static func installieren(von url: URL) {
        let fortschritt = NSAlert()
        fortschritt.messageText = "Snap it wird geladen …"
        fortschritt.informativeText = "Danach startet die App neu."
        let balken = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 300, height: 20))
        balken.style = .bar
        balken.isIndeterminate = true
        balken.startAnimation(nil)
        fortschritt.accessoryView = balken
        fortschritt.addButton(withTitle: "Abbrechen")

        let aufgabe = URLSession.shared.downloadTask(with: url) { ort, _, fehler in
            DispatchQueue.main.async {
                NSApp.stopModal()
                fortschritt.window.orderOut(nil)
                guard let ort, fehler == nil else {
                    melden("Download fehlgeschlagen", fehler?.localizedDescription ?? "Unbekannter Fehler")
                    return
                }
                austauschen(zip: ort)
            }
        }
        aufgabe.resume()
        NSApp.activate(ignoringOtherApps: true)
        if fortschritt.runModal() == .alertFirstButtonReturn { aufgabe.cancel() }
    }

    /// Entpackt das Archiv und ersetzt die laufende App durch die neue Fassung.
    private static func austauschen(zip: URL) {
        let fm = FileManager.default
        let arbeit = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snapit-update-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: arbeit) }

        do {
            try fm.createDirectory(at: arbeit, withIntermediateDirectories: true)
            let archiv = arbeit.appendingPathComponent("neu.zip")
            try fm.moveItem(at: zip, to: archiv)

            let entpacken = Process()
            entpacken.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            entpacken.arguments = ["-x", "-k", archiv.path, arbeit.path]
            try entpacken.run()
            entpacken.waitUntilExit()
            guard entpacken.terminationStatus == 0 else {
                melden("Archiv ließ sich nicht öffnen", "ditto meldete Fehler \(entpacken.terminationStatus)."); return
            }

            let inhalt = try fm.contentsOfDirectory(at: arbeit, includingPropertiesForKeys: nil)
            guard let neueApp = inhalt.first(where: { $0.pathExtension == "app" }) else {
                melden("Keine App im Archiv", "Erwartet wurde eine Datei Snap it.app."); return
            }

            let eigenerOrt = Bundle.main.bundleURL
            let ersatz = eigenerOrt.deletingLastPathComponent()
                .appendingPathComponent(neueApp.lastPathComponent)
            // Alte Fassung in den Papierkorb, neue an ihren Platz
            if fm.fileExists(atPath: ersatz.path) {
                try fm.trashItem(at: ersatz, resultingItemURL: nil)
            }
            try fm.copyItem(at: neueApp, to: ersatz)

            let neustart = Process()
            neustart.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            neustart.arguments = ["-n", ersatz.path]
            try neustart.run()
            NSApp.terminate(nil)

        } catch {
            melden("Update fehlgeschlagen", "\(error.localizedDescription)\n\nDie neue Fassung lässt sich auch von Hand austauschen.")
        }
    }

    private static func melden(_ titel: String, _ text: String) {
        let a = NSAlert()
        a.messageText = titel
        a.informativeText = text
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
