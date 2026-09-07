import AppKit

/// Ein gemerkter Screenshot. Der Name der Datei ist zugleich die Notiz —
/// es gibt keine Begleitdatei, der Ordner bleibt für sich allein lesbar.
struct Idee {
    var datei: String          // Dateiname samt Endung
    var datum: Date
    var notiz: String          // Dateiname ohne Endung

    var url: URL { Einstellungen.geteilt.ideenOrdner.appendingPathComponent(datei) }
}

/// Ablage für Screenshots, die als Inspiration taugen. Sie besteht nur aus
/// Bilddateien in einem Ordner: umbenennen im Finder benennt die Idee um,
/// löschen dort löscht sie.
enum Ideenablage {

    static let geaendert = Notification.Name("SnapItIdeenGeaendert")

    private static let endungen: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]

    static func alle() -> [Idee] {
        aufraeumen()
        let ordner = Einstellungen.geteilt.ideenOrdner
        let inhalt = (try? FileManager.default.contentsOfDirectory(
            at: ordner, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []

        return inhalt
            .filter { endungen.contains($0.pathExtension.lowercased()) }
            .map { u in
                let werte = try? u.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let datum = werte?.creationDate ?? werte?.contentModificationDate ?? Date.distantPast
                return Idee(datei: u.lastPathComponent, datum: datum,
                            notiz: u.deletingPathExtension().lastPathComponent)
            }
            .sorted { $0.datum > $1.datum }
    }

    @discardableResult
    static func sichern(_ bild: NSImage, notiz: String) -> Idee? {
        Einstellungen.geteilt.ordnerSicherstellen()
        guard let daten = Render.png(bild) else { return nil }
        let ziel = freierName(fuer: notiz)
        do { try daten.write(to: ziel) } catch { return nil }
        NotificationCenter.default.post(name: geaendert, object: nil)
        return Idee(datei: ziel.lastPathComponent, datum: Date(),
                    notiz: ziel.deletingPathExtension().lastPathComponent)
    }

    static func loeschen(_ idee: Idee) {
        try? FileManager.default.trashItem(at: idee.url, resultingItemURL: nil)
        NotificationCenter.default.post(name: geaendert, object: nil)
    }

    /// Die Notiz zu ändern heißt, die Datei umzubenennen.
    static func notizAendern(_ idee: Idee, auf text: String) {
        let neu = freierName(fuer: text, endung: idee.url.pathExtension)
        guard neu != idee.url else { return }
        try? FileManager.default.moveItem(at: idee.url, to: neu)
        NotificationCenter.default.post(name: geaendert, object: nil)
    }

    /// Freier Dateiname aus dem Wunschnamen. Zeichen, die im Dateisystem
    /// stören, werden ersetzt; bei Namensgleichheit wird durchnummeriert.
    private static func freierName(fuer wunsch: String, endung: String = "png") -> URL {
        let ordner = Einstellungen.geteilt.ideenOrdner
        var name = saeubern(wunsch)
        if name.isEmpty {
            let f = DateFormatter()
            f.locale = Locale(identifier: "de_DE")
            f.dateFormat = "yyyy-MM-dd 'um' HH.mm.ss"
            name = "Idee \(f.string(from: Date()))"
        }
        var ziel = ordner.appendingPathComponent("\(name).\(endung)")
        var zaehler = 2
        while FileManager.default.fileExists(atPath: ziel.path) {
            ziel = ordner.appendingPathComponent("\(name) \(zaehler).\(endung)")
            zaehler += 1
        }
        return ziel
    }

    private static func saeubern(_ text: String) -> String {
        let verboten = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let sauber = text.components(separatedBy: verboten).joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Ein führender Punkt würde die Datei unsichtbar machen
        let ohnePunkt = sauber.hasPrefix(".") ? String(sauber.dropFirst()) : sauber
        return String(ohnePunkt.prefix(120))
    }

    /// Räumt die Begleitdatei früherer Fassungen weg — die Notizen stecken
    /// jetzt in den Dateinamen.
    private static func aufraeumen() {
        let alt = Einstellungen.geteilt.ideenOrdner.appendingPathComponent("ideen.json")
        if FileManager.default.fileExists(atPath: alt.path) {
            try? FileManager.default.trashItem(at: alt, resultingItemURL: nil)
        }
    }
}
