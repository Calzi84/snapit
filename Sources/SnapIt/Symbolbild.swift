import AppKit

/// Zeichnet das App-Symbol und das Menüleisten-Symbol im Code.
/// So gibt es keine Bilddateien, die beim Umbenennen verloren gehen,
/// und das Icon lässt sich in jeder Größe scharf erzeugen.
enum Symbolbild {

    /// Apple-artige abgerundete Form (Superellipse), deutlich weicher als ein
    /// einfaches Rechteck mit Eckradius.
    static func superellipse(in r: CGRect, n: CGFloat = 5) -> NSBezierPath {
        let p = NSBezierPath()
        let a = r.width/2, b = r.height/2
        let cx = r.midX, cy = r.midY
        let schritte = 240
        for i in 0...schritte {
            let t = CGFloat(i) / CGFloat(schritte) * 2 * .pi
            let ct = cos(t), st = sin(t)
            let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2/n)
            let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2/n)
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.line(to: CGPoint(x: x, y: y)) }
        }
        p.close()
        return p
    }

    /// Blitz als Pfad in einem Einheitsquadrat, y zeigt nach unten.
    private static func blitz(in r: CGRect) -> NSBezierPath {
        let punkte: [(CGFloat, CGFloat)] = [
            (0.605, 0.030), (0.235, 0.560), (0.455, 0.560),
            (0.395, 0.970), (0.775, 0.430), (0.545, 0.430),
        ]
        let p = NSBezierPath()
        for (i, pt) in punkte.enumerated() {
            let q = CGPoint(x: r.minX + pt.0 * r.width, y: r.minY + pt.1 * r.height)
            if i == 0 { p.move(to: q) } else { p.line(to: q) }
        }
        p.close()
        return p
    }

    /// Vier Ecken eines Auswahlrahmens.
    private static func ecken(in r: CGRect, laenge: CGFloat, breite: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        let l = laenge
        // oben links
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.line(to: CGPoint(x: r.minX, y: r.minY)); p.line(to: CGPoint(x: r.minX + l, y: r.minY))
        // oben rechts
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.line(to: CGPoint(x: r.maxX, y: r.minY)); p.line(to: CGPoint(x: r.maxX, y: r.minY + l))
        // unten rechts
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.line(to: CGPoint(x: r.maxX, y: r.maxY)); p.line(to: CGPoint(x: r.maxX - l, y: r.maxY))
        // unten links
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.line(to: CGPoint(x: r.minX, y: r.maxY)); p.line(to: CGPoint(x: r.minX, y: r.maxY - l))
        p.lineWidth = breite
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        return p
    }

    /// Legt eine Form als Glaskörper an: Schlagschatten, Verlaufsfüllung,
    /// heller Glanz oben und ein feiner Innenrand — der Aufbau, den macOS 26
    /// für seine Symbole benutzt.
    ///
    /// Der Innenrand wird als Kontur auf der eigenen Form gezeichnet und auf
    /// sie beschnitten. Eine versetzte Kontur wäre einfacher, hinterlässt an
    /// eckigen Formen aber Kerben.
    private static func glasKoerper(_ pfad: NSBezierPath, kante: CGFloat, farbe: NSColor) {
        let r = pfad.bounds

        NSGraphicsContext.saveGraphicsState()
        let schatten = NSShadow()
        schatten.shadowColor = NSColor.black.withAlphaComponent(0.40)
        schatten.shadowOffset = NSSize(width: 0, height: -kante*0.013)
        schatten.shadowBlurRadius = kante*0.034
        schatten.set()
        farbe.setFill()
        pfad.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        pfad.setClip()

        // Körperverlauf: oben etwas Licht, unten etwas Tiefe
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.26),
            NSColor.white.withAlphaComponent(0.02),
            NSColor.black.withAlphaComponent(0.16),
        ])?.draw(from: CGPoint(x: r.midX, y: r.minY),
                 to: CGPoint(x: r.midX, y: r.maxY), options: [])

        // Glanzlicht, das von oben in den Körper fällt
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.34),
            NSColor.white.withAlphaComponent(0),
        ])?.draw(fromCenter: CGPoint(x: r.midX, y: r.minY - r.height*0.30), radius: 0,
                 toCenter: CGPoint(x: r.midX, y: r.minY - r.height*0.30),
                 radius: r.height*0.92, options: [])

        // Feiner Innenrand rundum
        NSColor.white.withAlphaComponent(0.50).setStroke()
        let saum = pfad.copy() as! NSBezierPath
        saum.lineWidth = kante*0.009
        saum.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Glaskörper für Strichformen (die Auswahlecken). Hier wird der Saum als
    /// zweite, breitere Kontur unter die erste gelegt. Den Umriss zu füllen und
    /// zu stroken wäre naheliegender, hinterlässt an den Knicken aber Kerben,
    /// weil sich die Kontur dort selbst überschneidet.
    private static func glasStrich(_ pfad: NSBezierPath, kante: CGFloat,
                                   breite: CGFloat, farbe: NSColor) {
        let saum = kante * 0.011

        NSGraphicsContext.saveGraphicsState()
        let schatten = NSShadow()
        schatten.shadowColor = NSColor.black.withAlphaComponent(0.40)
        schatten.shadowOffset = NSSize(width: 0, height: -kante*0.013)
        schatten.shadowBlurRadius = kante*0.034
        schatten.set()
        NSColor.white.withAlphaComponent(0.55).setStroke()
        pfad.lineWidth = breite + saum
        pfad.stroke()
        NSGraphicsContext.restoreGraphicsState()

        farbe.setStroke()
        pfad.lineWidth = breite
        pfad.stroke()

        // Verlauf und Glanz nur innerhalb der Strichfläche
        let umriss = NSBezierPath(cgPath: pfad.cgPath.copy(
            strokingWithWidth: breite, lineCap: .round, lineJoin: .round, miterLimit: 10))
        let r = umriss.bounds
        NSGraphicsContext.saveGraphicsState()
        umriss.setClip()
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.30),
            NSColor.white.withAlphaComponent(0.02),
            NSColor.black.withAlphaComponent(0.18),
        ])?.draw(from: CGPoint(x: r.midX, y: r.minY),
                 to: CGPoint(x: r.midX, y: r.maxY), options: [])
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.30),
            NSColor.white.withAlphaComponent(0),
        ])?.draw(fromCenter: CGPoint(x: r.midX, y: r.minY - r.height*0.28), radius: 0,
                 toCenter: CGPoint(x: r.midX, y: r.minY - r.height*0.28),
                 radius: r.height*0.85, options: [])
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Das App-Symbol in beliebiger Kantenlänge, im Glasstil von macOS 26.
    ///
    /// Verläufe werden mit ausdrücklichen Start- und Endpunkten gezeichnet.
    /// Über einen Winkel ginge es auch, aber im geflippten Kontext zeigt der
    /// in die andere Richtung — das hinterlässt eine harte Kante.
    static func app(_ kante: CGFloat) -> NSImage {
        let bild = NSImage(size: NSSize(width: kante, height: kante))
        bild.lockFocusFlipped(true)

        let rand = kante * 0.094                        // Apples Icons sitzen nicht randbündig
        let flaeche = CGRect(x: rand, y: rand, width: kante - 2*rand, height: kante - 2*rand)
        let form = superellipse(in: flaeche)
        let oben = CGPoint(x: flaeche.midX, y: flaeche.minY)
        let unten = CGPoint(x: flaeche.midX, y: flaeche.maxY)

        // Grundkörper
        NSGraphicsContext.saveGraphicsState()
        form.setClip()
        NSGradient(colors: [
            NSColor(srgbRed: 0.212, green: 0.231, blue: 0.220, alpha: 1),
            NSColor(srgbRed: 0.047, green: 0.059, blue: 0.055, alpha: 1),
        ])?.draw(from: oben, to: unten, options: [])

        // Grüner Schein, der den Blitz hinterlegt
        NSGradient(colors: [
            Theme.gruen.withAlphaComponent(0.40),
            Theme.gruen.withAlphaComponent(0.12),
            Theme.gruen.withAlphaComponent(0),
        ])?.draw(fromCenter: CGPoint(x: flaeche.midX, y: flaeche.midY + flaeche.height*0.05),
                 radius: 0,
                 toCenter: CGPoint(x: flaeche.midX, y: flaeche.midY + flaeche.height*0.05),
                 radius: flaeche.width * 0.62, options: [])

        // Lichtbogen am oberen Rand, wie bei einer gewölbten Glasplatte
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.20),
            NSColor.white.withAlphaComponent(0.04),
            NSColor.white.withAlphaComponent(0),
        ])?.draw(fromCenter: CGPoint(x: flaeche.midX, y: flaeche.minY - flaeche.height*0.35),
                 radius: 0,
                 toCenter: CGPoint(x: flaeche.midX, y: flaeche.minY - flaeche.height*0.35),
                 radius: flaeche.width * 1.05, options: [])
        NSGraphicsContext.restoreGraphicsState()

        // Feine Glaskante rundherum
        NSGraphicsContext.saveGraphicsState()
        form.setClip()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        let glasKante = superellipse(in: flaeche.insetBy(dx: kante*0.005, dy: kante*0.005))
        glasKante.lineWidth = kante * 0.010
        glasKante.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // Auswahlecken als grüner Glaskörper
        let rahmen = flaeche.insetBy(dx: flaeche.width*0.168, dy: flaeche.height*0.168)
        let staerke = kante*0.046
        glasStrich(ecken(in: rahmen, laenge: rahmen.width*0.30, breite: staerke),
                   kante: kante, breite: staerke, farbe: Theme.gruen)

        // Blitz als weißer Glaskörper
        let blitzRect = CGRect(x: flaeche.midX - flaeche.width*0.175,
                               y: flaeche.midY - flaeche.height*0.245,
                               width: flaeche.width*0.35, height: flaeche.height*0.49)
        glasKoerper(blitz(in: blitzRect), kante: kante,
                    farbe: NSColor(srgbRed: 0.965, green: 0.98, blue: 0.972, alpha: 1))

        bild.unlockFocus()
        return bild
    }

    /// Schwarzes Template-Symbol für die Menüleiste — das System färbt es
    /// je nach Hintergrund selbst hell oder dunkel ein.
    static func menueleiste() -> NSImage {
        let kante: CGFloat = 18
        let bild = NSImage(size: NSSize(width: kante, height: kante))
        bild.lockFocusFlipped(true)
        NSColor.black.setStroke()
        NSColor.black.setFill()
        let rahmen = CGRect(x: 1.6, y: 1.6, width: kante - 3.2, height: kante - 3.2)
        ecken(in: rahmen, laenge: 4.1, breite: 1.7).stroke()
        blitz(in: CGRect(x: kante/2 - 3.1, y: kante/2 - 4.4, width: 6.2, height: 8.8)).fill()
        bild.unlockFocus()
        bild.isTemplate = true
        return bild
    }

    /// Schreibt alle Größen für ein .iconset. Wird vom Build-Skript aufgerufen.
    static func iconsetSchreiben(nach ordner: URL) throws {
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let groessen: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
        for (pt, faktor) in groessen {
            let px = CGFloat(pt * faktor)
            let bild = app(px)
            guard let daten = Render.png(bild) else { continue }
            let name = faktor == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
            try daten.write(to: ordner.appendingPathComponent(name))
        }
    }
}
