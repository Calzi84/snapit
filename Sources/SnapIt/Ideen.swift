import AppKit

/// Ein gemerkter Screenshot samt Notiz.
struct Idee: Codable {
    var datei: String
    var datum: Date
    var notiz: String

    var url: URL { Einstellungen.geteilt.ideenOrdner.appendingPathComponent(datei) }
}

/// Kleine Ablage für Screenshots, die als Inspiration taugen.
/// Die Bilder liegen als normale PNG im Ideen-Ordner, der Index
/// daneben als JSON — so bleibt alles auch ohne die App lesbar.
enum Ideenablage {

    static let geaendert = Notification.Name("SnapItIdeenGeaendert")

    private static var indexURL: URL {
        Einstellungen.geteilt.ideenOrdner.appendingPathComponent("ideen.json")
    }

    static func alle() -> [Idee] {
        guard let daten = try? Data(contentsOf: indexURL) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let liste = (try? dec.decode([Idee].self, from: daten)) ?? []
        // Einträge ohne Datei aussortieren, falls jemand im Finder aufgeräumt hat
        return liste.filter { FileManager.default.fileExists(atPath: $0.url.path) }
            .sorted { $0.datum > $1.datum }
    }

    @discardableResult
    static func sichern(_ bild: NSImage, notiz: String) -> Idee? {
        Einstellungen.geteilt.ordnerSicherstellen()
        guard let daten = Render.png(bild) else { return nil }
        let name = Einstellungen.geteilt.dateiname(praefix: "Idee")
        let ziel = Einstellungen.geteilt.ideenOrdner.appendingPathComponent(name)
        do { try daten.write(to: ziel) } catch { return nil }

        let idee = Idee(datei: name, datum: Date(), notiz: notiz)
        var liste = alle()
        liste.insert(idee, at: 0)
        schreiben(liste)
        NotificationCenter.default.post(name: geaendert, object: nil)
        return idee
    }

    static func loeschen(_ idee: Idee) {
        try? FileManager.default.trashItem(at: idee.url, resultingItemURL: nil)
        schreiben(alle().filter { $0.datei != idee.datei })
        NotificationCenter.default.post(name: geaendert, object: nil)
    }

    static func notizAendern(_ idee: Idee, auf text: String) {
        var liste = alle()
        if let i = liste.firstIndex(where: { $0.datei == idee.datei }) {
            liste[i].notiz = text
            schreiben(liste)
            NotificationCenter.default.post(name: geaendert, object: nil)
        }
    }

    private static func schreiben(_ liste: [Idee]) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let daten = try? enc.encode(liste) else { return }
        try? daten.write(to: indexURL)
    }
}
