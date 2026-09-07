import AppKit

enum Werkzeug: String, CaseIterable {
    case auswahl, pfeil, linie, rechteck, ellipse, stift, marker, text, pixel, nummer, zuschnitt

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
        case .pixel:     return "Verpixeln (B)"
        case .nummer:    return "Nummer (N)"
        case .zuschnitt: return "Zuschneiden (C)"
        }
    }

    /// Werkzeuge, die beim Ziehen einen Rahmen aufspannen.
    var istRahmen: Bool {
        self == .rechteck || self == .ellipse || self == .pixel || self == .zuschnitt
    }
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
            return rechteck.insetBy(dx: -staerke, dy: -staerke)
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
    var pixelBild: NSImage?
    var formen: [Form]
}

final class Dokument {
    private(set) var bild: NSImage
    private(set) var pixelBild: NSImage?
    var formen: [Form] = []

    /// Pixel je Punkt der Aufnahme: auf Retina-Bildschirmen 2.
    /// Alle Strichstärken werden damit multipliziert, sonst wirken sie halb so dick.
    let faktor: CGFloat

    private var zurueck: [Zustand] = []
    private var vor: [Zustand] = []

    init(bild: NSImage, faktor: CGFloat = 2) {
        self.bild = bild
        self.faktor = max(1, faktor)
        self.pixelBild = Dokument.verpixeln(bild)
    }

    var groesse: CGSize { bild.size }
    var kannZurueck: Bool { !zurueck.isEmpty }
    var kannVor: Bool { !vor.isEmpty }

    private var momentaufnahme: Zustand {
        Zustand(bild: bild, pixelBild: pixelBild, formen: formen.map { $0.kopie() })
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
        bild = z.bild
        pixelBild = z.pixelBild
        formen = z.formen
    }

    /// Schneidet das Bild zu und verschiebt alle Formen mit.
    func zuschneiden(auf r: CGRect) {
        let ganz = CGRect(origin: .zero, size: bild.size)
        let ziel = r.intersection(ganz).integral
        guard ziel.width >= 8, ziel.height >= 8 else { return }
        merken()
        bild = Render.ausschnitt(bild, ziel)
        pixelBild = Dokument.verpixeln(bild)
        for f in formen { f.verschieben(dx: -ziel.minX, dy: -ziel.minY) }
    }

    /// Einmalig verpixelte Fassung des Bildes; die Pixel-Form blendet daraus nur ihren Ausschnitt ein.
    static func verpixeln(_ bild: NSImage) -> NSImage? {
        guard let tiff = bild.tiffRepresentation,
              let ci = CIImage(data: tiff) else { return nil }
        let kantenlaenge = max(10, min(bild.size.width, bild.size.height) / 55)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: ci.extent.midX, y: ci.extent.midY), forKey: kCIInputCenterKey)
        filter.setValue(kantenlaenge, forKey: kCIInputScaleKey)
        guard let out = filter.outputImage?.cropped(to: ci.extent) else { return nil }
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(out, from: ci.extent) else { return nil }
        let ergebnis = NSImage(size: bild.size)
        ergebnis.addRepresentation(NSBitmapImageRep(cgImage: cg))
        ergebnis.size = bild.size
        return ergebnis
    }
}
