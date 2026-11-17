import AppKit

enum Werkzeug: String, CaseIterable {
    case auswahl, pfeil, linie, rechteck, ellipse, stift, marker, text, pixel, weichzeichnen, nummer, zuschnitt

    var symbol: String {
        switch self {
        case .auswahl:   return "cursorarrow"
        case .pfeil:     return "arrow.up.right"
        case .linie:     return "line.diagonal"
        case .rechteck:  return "rectangle"
        case .ellipse:   return "circle"
        case .stift:     return "pencil.tip"
        case .marker:    return "highlighter"
        case .text:      return "textformat"
        case .pixel:     return "squareshape.split.3x3"
        case .weichzeichnen: return "drop.fill"
        case .nummer:    return "1.circle"
        case .zuschnitt: return "crop"
        }
    }

    var titel: String {
        switch self {
        case .auswahl:   return "Auswählen und verschieben (V)"
        case .pfeil:     return "Pfeil (A)"
        case .linie:     return "Linie (L)"
        case .rechteck:  return "Rechteck (R)"
        case .ellipse:   return "Ellipse (E)"
        case .stift:     return "Freihand (P)"
        case .marker:    return "Marker (H)"
        case .text:      return "Text (T)"
        case .pixel:     return "Verpixeln (B) — Größe über den Regler"
        case .weichzeichnen: return "Weichzeichnen (U) — Stärke über den Regler"
        case .nummer:    return "Nummer (N)"
        case .zuschnitt: return "Zuschneiden (C)"
        }
    }

    /// Werkzeuge, die beim Ziehen einen Rahmen aufspannen.
    var istRahmen: Bool {
        self == .rechteck || self == .ellipse || istEffekt || self == .zuschnitt
    }

    /// Werkzeuge, die den Bildinhalt unkenntlich machen.
    var istEffekt: Bool { self == .pixel || self == .weichzeichnen }
}

/// Eine einzelne Annotation. Alle Koordinaten liegen in Bildpixeln,
/// Ursprung oben links.
final class Form {
    var werkzeug: Werkzeug
    var farbe: NSColor
    var staerke: CGFloat
    var p1: CGPoint
    var p2: CGPoint
    var punkte: [CGPoint] = []      // nur Stift/Marker
    var text: String = ""           // nur Text
    var nummer: Int = 0             // nur Nummer

    init(werkzeug: Werkzeug, farbe: NSColor, staerke: CGFloat, p1: CGPoint, p2: CGPoint) {
        self.werkzeug = werkzeug
        self.farbe = farbe
        self.staerke = staerke
        self.p1 = p1
        self.p2 = p2
    }

    func kopie() -> Form {
        let f = Form(werkzeug: werkzeug, farbe: farbe, staerke: staerke, p1: p1, p2: p2)
        f.punkte = punkte
        f.text = text
        f.nummer = nummer
        return f
    }

    /// Achsparalleler Rahmen aus p1/p2.
    var rechteck: CGRect {
        CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
               width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
    }

    /// Trefferfläche für die Auswahl.
    func rahmen(schrift: NSFont) -> CGRect {
        switch werkzeug {
        case .stift, .marker:
            guard !punkte.isEmpty else { return .zero }
            var minX = punkte[0].x, maxX = punkte[0].x
            var minY = punkte[0].y, maxY = punkte[0].y
            for p in punkte {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                .insetBy(dx: -staerke, dy: -staerke)
        case .text:
            let groesse = (text as NSString).size(withAttributes: [.font: schrift])
            return CGRect(x: p1.x, y: p1.y, width: max(groesse.width, 12), height: groesse.height)
        case .nummer:
            let r = radiusNummer
            return CGRect(x: p1.x - r, y: p1.y - r, width: r * 2, height: r * 2)
        case .pfeil, .linie:
            return rechteck.insetBy(dx: -max(8, staerke), dy: -max(8, staerke))
        default:
            // Bei Effekten ist staerke die Filterstärke, kein Strich — ein
            // Zuschlag darauf würde die Trefferfläche sinnlos aufblähen.
            let zuschlag = werkzeug.istEffekt ? 2 : staerke
            return rechteck.insetBy(dx: -zuschlag, dy: -zuschlag)
        }
    }

    var radiusNummer: CGFloat { max(14, staerke * 2.6) }

    func verschieben(dx: CGFloat, dy: CGFloat) {
        p1.x += dx; p1.y += dy
        p2.x += dx; p2.y += dy
        for i in punkte.indices {
            punkte[i].x += dx
            punkte[i].y += dy
        }
    }
}

/// Zustand des Dokuments für Undo/Redo. Das Bild wandert mit,
/// damit auch ein Zuschnitt zurücknehmbar ist.
struct Zustand {
    var bild: NSImage
    var formen: [Form]
}

final class Dokument {
    private(set) var bild: NSImage
    var formen: [Form] = []

    /// Fertig gefilterte Fassungen des Bildes, je Effekt und Stärke.
    /// Ohne diesen Zwischenspeicher liefe der Filter bei jedem Mausschritt
    /// neu über das ganze Bild.
    private var effekte: [String: NSImage] = [:]

    /// Pixel je Punkt der Aufnahme: auf Retina-Bildschirmen 2.
    /// Alle Strichstärken werden damit multipliziert, sonst wirken sie halb so dick.
    let faktor: CGFloat

    private var zurueck: [Zustand] = []
    private var vor: [Zustand] = []

    init(bild: NSImage, faktor: CGFloat = 2) {
        self.bild = bild
        self.faktor = max(1, faktor)
    }

    var groesse: CGSize { bild.size }
    var kannZurueck: Bool { !zurueck.isEmpty }
    var kannVor: Bool { !vor.isEmpty }

    private var momentaufnahme: Zustand {
        Zustand(bild: bild, formen: formen.map { $0.kopie() })
    }

    /// Vor jeder verändernden Aktion aufrufen.
    func merken() {
        zurueck.append(momentaufnahme)
        vor.removeAll()
        if zurueck.count > 60 { zurueck.removeFirst() }
    }

    func zurueckNehmen() {
        guard let z = zurueck.popLast() else { return }
        vor.append(momentaufnahme)
        anwenden(z)
    }

    func vorNehmen() {
        guard let z = vor.popLast() else { return }
        zurueck.append(momentaufnahme)
        anwenden(z)
    }

    private func anwenden(_ z: Zustand) {
        if bild !== z.bild { effekte.removeAll() }
        bild = z.bild
        formen = z.formen
    }

    /// Schneidet das Bild zu und verschiebt alle Formen mit.
    func zuschneiden(auf r: CGRect) {
        let ganz = CGRect(origin: .zero, size: bild.size)
        let ziel = r.intersection(ganz).integral
        guard ziel.width >= 8, ziel.height >= 8 else { return }
        merken()
        bild = Render.ausschnitt(bild, ziel)
        effekte.removeAll()
        for f in formen { f.verschieben(dx: -ziel.minX, dy: -ziel.minY) }
    }

    /// Gefilterte Fassung des ganzen Bildes. Die Effektform blendet daraus nur
    /// ihren Ausschnitt ein — so bleiben die Kanten des Rahmens sauber, und
    /// mehrere Formen gleicher Stärke teilen sich dieselbe Rechnung.
    func effektBild(_ art: Werkzeug, staerke: CGFloat) -> NSImage? {
        let stufe = max(1, staerke.rounded())
        let schluessel = "\(art.rawValue)-\(Int(stufe))"
        if let fertig = effekte[schluessel] { return fertig }
        guard let neu = Dokument.filtern(bild, art: art, staerke: stufe, faktor: faktor) else { return nil }
        if effekte.count > 12 { effekte.removeAll() }   // Stärkeregler nicht endlos sammeln
        effekte[schluessel] = neu
        return neu
    }

    /// Umrechnung Reglerwert → Filterstärke, beides in Bildpixeln.
    ///
    /// Der Sockel ist gemessen, nicht geschätzt: `--lesbarkeit` verpixelt
    /// Bildschirmtext und lässt ihn von der Texterkennung lesen. Ohne Sockel
    /// las sie auf Stufe 1 noch Namen und Vertragsnummern vollständig mit.
    /// Der Sockel wächst mit dem Faktor, damit eine Stufe auf jedem Bildschirm
    /// gleich wirkt.
    static func pixelKante(_ staerke: CGFloat, faktor: CGFloat) -> CGFloat {
        3.5 * faktor + staerke * 1.5
    }
    /// Weichzeichnen braucht mehr Sockel als Verpixeln: Es erhält Umrisse.
    /// Mit 3 × Faktor las die Texterkennung zwar kein Wort mehr, Wortlängen und
    /// Großbuchstaben blieben fürs Auge aber erkennbar — eine Vertragsnummer
    /// ließ sich erraten.
    static func unschaerfeRadius(_ staerke: CGFloat, faktor: CGFloat) -> CGFloat {
        6 * faktor + staerke * 1.2
    }

    private static func filtern(_ bild: NSImage, art: Werkzeug, staerke: CGFloat,
                                faktor: CGFloat) -> NSImage? {
        guard let tiff = bild.tiffRepresentation,
              let ci = CIImage(data: tiff) else { return nil }
        let ausdehnung = ci.extent
        var ergebnisBild: CIImage?

        switch art {
        case .pixel:
            guard let filter = CIFilter(name: "CIPixellate") else { return nil }
            filter.setValue(ci, forKey: kCIInputImageKey)
            filter.setValue(CIVector(x: ausdehnung.midX, y: ausdehnung.midY), forKey: kCIInputCenterKey)
            filter.setValue(pixelKante(staerke, faktor: faktor), forKey: kCIInputScaleKey)
            ergebnisBild = filter.outputImage

        case .weichzeichnen:
            // Ohne clampedToExtent zieht der Weichzeichner die Ränder ins
            // Transparente und das Bild bekommt einen hellen Saum.
            guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
            filter.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
            filter.setValue(unschaerfeRadius(staerke, faktor: faktor), forKey: kCIInputRadiusKey)
            ergebnisBild = filter.outputImage

        default:
            return nil
        }

        guard let out = ergebnisBild?.cropped(to: ausdehnung) else { return nil }
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(out, from: ausdehnung) else { return nil }
        let ergebnis = NSImage(size: bild.size)
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = bild.size
        ergebnis.addRepresentation(rep)
        return ergebnis
    }
}
