import AppKit

/// Zeichnet Formen. Wird von der Zeichenfläche und vom Export benutzt,
/// damit Vorschau und Ergebnis garantiert identisch aussehen.
/// Koordinatensystem: Bildpixel, Ursprung oben links.
enum Render {

    static func schriftFuer(_ staerke: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: max(13, staerke * 4.2), weight: .semibold)
    }

    static func zeichne(_ f: Form, doc: Dokument) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        defer { ctx.restoreGraphicsState() }

        switch f.werkzeug {

        case .linie:
            f.farbe.setStroke()
            let p = NSBezierPath()
            p.move(to: f.p1); p.line(to: f.p2)
            p.lineWidth = f.staerke
            p.lineCapStyle = .round
            p.stroke()

        case .pfeil:
            f.farbe.setStroke()
            f.farbe.setFill()
            let winkel = atan2(f.p2.y - f.p1.y, f.p2.x - f.p1.x)
            let spitze = max(14, f.staerke * 3.8)
            let spreiz = CGFloat.pi / 7
            // Linie kurz vor der Spitze enden lassen, sonst steht sie über
            let ende = CGPoint(x: f.p2.x - cos(winkel) * spitze * 0.55,
                               y: f.p2.y - sin(winkel) * spitze * 0.55)
            let linie = NSBezierPath()
            linie.move(to: f.p1); linie.line(to: ende)
            linie.lineWidth = f.staerke
            linie.lineCapStyle = .round
            linie.stroke()

            let kopf = NSBezierPath()
            kopf.move(to: f.p2)
            kopf.line(to: CGPoint(x: f.p2.x - spitze * cos(winkel - spreiz),
                                  y: f.p2.y - spitze * sin(winkel - spreiz)))
            kopf.line(to: CGPoint(x: f.p2.x - spitze * cos(winkel + spreiz),
                                  y: f.p2.y - spitze * sin(winkel + spreiz)))
            kopf.close()
            kopf.fill()

        case .rechteck:
            f.farbe.setStroke()
            let p = NSBezierPath(roundedRect: f.rechteck.insetBy(dx: f.staerke/2, dy: f.staerke/2),
                                 xRadius: f.staerke, yRadius: f.staerke)
            p.lineWidth = f.staerke
            p.stroke()

        case .ellipse:
            f.farbe.setStroke()
            let p = NSBezierPath(ovalIn: f.rechteck.insetBy(dx: f.staerke/2, dy: f.staerke/2))
            p.lineWidth = f.staerke
            p.stroke()

        case .stift:
            guard f.punkte.count > 1 else { return }
            f.farbe.setStroke()
            glaettung(f.punkte, breite: f.staerke).stroke()

        case .marker:
            guard f.punkte.count > 1 else { return }
            ctx.compositingOperation = .multiply
            f.farbe.withAlphaComponent(0.38).setStroke()
            let p = glaettung(f.punkte, breite: f.staerke * 4.5)
            p.lineCapStyle = .butt
            p.lineJoinStyle = .round
            p.stroke()

        case .text:
            guard !f.text.isEmpty else { return }
            let schatten = NSShadow()
            schatten.shadowColor = NSColor.black.withAlphaComponent(0.55)
            schatten.shadowOffset = NSSize(width: 0, height: -1)
            schatten.shadowBlurRadius = 3
            let attr: [NSAttributedString.Key: Any] = [
                .font: schriftFuer(f.staerke),
                .foregroundColor: f.farbe,
                .shadow: schatten,
            ]
            (f.text as NSString).draw(at: f.p1, withAttributes: attr)

        case .pixel:
            guard let px = doc.pixelBild else { return }
            let r = f.rechteck
            guard r.width > 2, r.height > 2 else { return }
            NSBezierPath(rect: r).setClip()
            px.draw(in: CGRect(origin: .zero, size: doc.groesse))

        case .nummer:
            let r = f.radiusNummer
            let kreis = CGRect(x: f.p1.x - r, y: f.p1.y - r, width: r*2, height: r*2)
            let schatten = NSShadow()
            schatten.shadowColor = NSColor.black.withAlphaComponent(0.45)
            schatten.shadowOffset = NSSize(width: 0, height: -1)
            schatten.shadowBlurRadius = 4
            schatten.set()
            f.farbe.setFill()
            NSBezierPath(ovalIn: kreis).fill()
            let text = "\(f.nummer)" as NSString
            let schrift = NSFont.systemFont(ofSize: r * 1.18, weight: .bold)
            let farbe = kontrastfarbe(zu: f.farbe)
            let groesse = text.size(withAttributes: [.font: schrift])
            text.draw(at: CGPoint(x: f.p1.x - groesse.width/2, y: f.p1.y - groesse.height/2),
                      withAttributes: [.font: schrift, .foregroundColor: farbe])

        case .auswahl, .zuschnitt:
            break
        }
    }

    /// Freihandlinie über Mittelpunkte glätten, sonst wirkt der Strich eckig.
    private static func glaettung(_ punkte: [CGPoint], breite: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        p.lineWidth = breite
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.move(to: punkte[0])
        if punkte.count == 2 {
            p.line(to: punkte[1])
            return p
        }
        for i in 1..<(punkte.count - 1) {
            let mitte = CGPoint(x: (punkte[i].x + punkte[i+1].x)/2,
                                y: (punkte[i].y + punkte[i+1].y)/2)
            p.curve(to: mitte, controlPoint1: punkte[i], controlPoint2: punkte[i])
        }
        p.line(to: punkte[punkte.count - 1])
        return p
    }

    static func kontrastfarbe(zu farbe: NSColor) -> NSColor {
        guard let c = farbe.usingColorSpace(.sRGB) else { return .white }
        let l = 0.299*c.redComponent + 0.587*c.greenComponent + 0.114*c.blueComponent
        return l > 0.62 ? NSColor(white: 0.10, alpha: 1) : .white
    }

    /// Bild plus alle Formen in voller Auflösung.
    static func rendern(_ doc: Dokument) -> NSImage? {
        let w = Int(doc.groesse.width.rounded()), h = Int(doc.groesse.height.rounded())
        guard w > 0, h > 0,
              let raum = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = CGContext(data: nil, width: w, height: h,
                                 bitsPerComponent: 8, bytesPerRow: 0, space: raum,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        cg.translateBy(x: 0, y: CGFloat(h))
        cg.scaleBy(x: 1, y: -1)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        let ganz = CGRect(origin: .zero, size: doc.groesse)
        doc.bild.draw(in: ganz)
        NSBezierPath(rect: ganz).setClip()
        for f in doc.formen { zeichne(f, doc: doc) }
        NSGraphicsContext.restoreGraphicsState()

        guard let bild = cg.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: bild)
        rep.size = doc.groesse
        let out = NSImage(size: doc.groesse)
        out.addRepresentation(rep)
        return out
    }

    static func ausschnitt(_ bild: NSImage, _ r: CGRect) -> NSImage {
        let w = Int(r.width.rounded()), h = Int(r.height.rounded())
        guard w > 0, h > 0,
              let raum = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = CGContext(data: nil, width: w, height: h,
                                 bitsPerComponent: 8, bytesPerRow: 0, space: raum,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return bild }

        cg.translateBy(x: 0, y: CGFloat(h))
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        bild.draw(in: CGRect(x: -r.minX, y: -r.minY,
                             width: bild.size.width, height: bild.size.height))
        NSGraphicsContext.restoreGraphicsState()

        guard let neu = cg.makeImage() else { return bild }
        let rep = NSBitmapImageRep(cgImage: neu)
        let groesse = CGSize(width: CGFloat(w), height: CGFloat(h))
        rep.size = groesse
        let out = NSImage(size: groesse)
        out.addRepresentation(rep)
        return out
    }

    static func png(_ bild: NSImage) -> Data? {
        guard let tiff = bild.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
