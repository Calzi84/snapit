import AppKit
import Vision

/// Prüft, ob verdeckter Bildschirmtext noch maschinell lesbar ist.
///
/// Gedacht für Kundendaten in Screenshots: Liest die Texterkennung nach dem
/// Verpixeln noch den Namen, kann es ein Mensch erst recht.
enum Lesbarkeit {

    /// Probezeile in typischer Bildschirmgröße, Retina-Auflösung.
    static let probetext = "Kundin Petra Brandstetter, Vertrag 4711-0815"

    static func probebild(punktgroesse: CGFloat, faktor: CGFloat = 2) -> NSImage {
        let schrift = NSFont.systemFont(ofSize: punktgroesse * faktor)
        let attr: [NSAttributedString.Key: Any] = [.font: schrift, .foregroundColor: NSColor.black]
        let g = (probetext as NSString).size(withAttributes: attr)
        let rand = 24 * faktor
        let groesse = CGSize(width: (g.width + 2 * rand).rounded(), height: (g.height + 2 * rand).rounded())
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(groesse.width),
                                   pixelsHigh: Int(groesse.height), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: groesse).fill()
        (probetext as NSString).draw(at: CGPoint(x: rand, y: rand), withAttributes: attr)
        NSGraphicsContext.restoreGraphicsState()
        rep.size = groesse
        let bild = NSImage(size: groesse)
        bild.addRepresentation(rep)
        return bild
    }

    /// Erkannter Text, synchron — für Prüfläufe ohne laufende Ereignisschleife.
    static func lesen(_ bild: NSImage) -> String {
        guard let tiff = bild.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else { return "" }
        let anfrage = VNRecognizeTextRequest()
        anfrage.recognitionLevel = .accurate
        anfrage.usesLanguageCorrection = true
        anfrage.recognitionLanguages = ["de-DE", "en-US"]
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([anfrage])
        return (anfrage.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
    }

    /// Wie viele der Wörter mit mindestens drei Buchstaben wiedererkannt wurden.
    static func treffer(_ erkannt: String) -> (gefunden: Int, von: Int) {
        let woerter = probetext.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init).filter { $0.count >= 3 }
        let klein = erkannt.lowercased()
        return (woerter.filter { klein.contains($0.lowercased()) }.count, woerter.count)
    }

    /// Bild verdecken wie die App es tut: Effektform über die ganze Fläche.
    static func verdeckt(_ bild: NSImage, art: Werkzeug, stufe: CGFloat, faktor: CGFloat = 2) -> NSImage? {
        let doc = Dokument(bild: bild, faktor: faktor)
        doc.formen = [Form(werkzeug: art, farbe: .clear, staerke: stufe * faktor,
                           p1: .zero, p2: CGPoint(x: doc.groesse.width, y: doc.groesse.height))]
        return Render.rendern(doc)
    }

    /// Vergleichstafel für das Auge: offen, dann je Effekt Stufe 1, 4 und 12.
    static func tafel(nach ziel: URL) {
        let offen = probebild(punktgroesse: 15)
        var zeilen: [(String, NSImage)] = [("offen", offen)]
        for (art, name) in [(Werkzeug.pixel, "verpixelt"), (.weichzeichnen, "weichgezeichnet")] {
            for stufe in [1, 4, 12] as [CGFloat] {
                if let v = verdeckt(offen, art: art, stufe: stufe) {
                    zeilen.append(("\(name), Stufe \(Int(stufe))", v))
                }
            }
        }
        let beschriftung: CGFloat = 420
        let b = offen.size.width + beschriftung, h = offen.size.height * CGFloat(zeilen.count)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(b), pixelsHigh: Int(h),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.93, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: b, height: h).fill()
        let attr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26, weight: .semibold),
                                                   .foregroundColor: NSColor(white: 0.25, alpha: 1)]
        for (i, (name, bild)) in zeilen.enumerated() {
            let y = h - CGFloat(i + 1) * offen.size.height
            (name as NSString).draw(at: CGPoint(x: 24, y: y + offen.size.height / 2 - 16), withAttributes: attr)
            bild.draw(in: NSRect(x: beschriftung, y: y, width: offen.size.width, height: offen.size.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: ziel)
    }

    static func bericht() -> String {
        var zeilen: [String] = []
        for pt in [11.0, 13.0, 17.0, 24.0, 32.0] as [CGFloat] {
            let bild = probebild(punktgroesse: pt)
            let roh = treffer(lesen(bild))
            zeilen.append("Schrift \(Int(pt)) pt — unverdeckt erkannt: \(roh.gefunden)/\(roh.von) Wörter")
            for art in [Werkzeug.pixel, .weichzeichnen] {
                var teile: [String] = []
                for stufe in [1, 2, 3, 4, 6, 8, 12, 16] as [CGFloat] {
                    guard let v = verdeckt(bild, art: art, stufe: stufe) else { continue }
                    let t = treffer(lesen(v))
                    teile.append("S\(Int(stufe)):\(t.gefunden)")
                }
                let name = art == .pixel ? "verpixelt " : "weichgez. "
                zeilen.append("   \(name) " + teile.joined(separator: "  "))
            }
        }
        return zeilen.joined(separator: "\n")
    }
}
