import AppKit

/// Farben und Maße der Oberfläche. Dunkles UI, Navion-Grün als Akzent.
enum Theme {

    // Markenfarben
    static let gruen = NSColor(srgbRed: 21/255, green: 193/255, blue: 131/255, alpha: 1)

    // Oberfläche
    static let fensterBG = NSColor(srgbRed: 0.086, green: 0.094, blue: 0.090, alpha: 1)
    static let leisteBG  = NSColor(srgbRed: 0.125, green: 0.133, blue: 0.129, alpha: 1)
    static let leisteRand = NSColor(white: 1, alpha: 0.10)
    static let knopfAktiv = NSColor(srgbRed: 0.22, green: 0.24, blue: 0.23, alpha: 1)
    static let schrift   = NSColor(srgbRed: 0.97, green: 0.98, blue: 0.976, alpha: 1)
    static let schriftMatt = NSColor(srgbRed: 0.61, green: 0.66, blue: 0.64, alpha: 1)

    /// Zeichenfarben in der Leiste, von links nach rechts.
    static let palette: [NSColor] = [
        NSColor(srgbRed: 0.90, green: 0.22, blue: 0.20, alpha: 1),   // Rot
        NSColor(srgbRed: 0.97, green: 0.58, blue: 0.12, alpha: 1),   // Orange
        NSColor(srgbRed: 0.98, green: 0.82, blue: 0.20, alpha: 1),   // Gelb
        gruen,                                                        // Navion-Grün
        NSColor(srgbRed: 0.20, green: 0.55, blue: 0.95, alpha: 1),   // Blau
        NSColor(srgbRed: 0.65, green: 0.35, blue: 0.90, alpha: 1),   // Violett
        NSColor.white,                                                // Weiß
        NSColor(srgbRed: 0.10, green: 0.10, blue: 0.10, alpha: 1),   // Schwarz
    ]

    static let leisteHoehe: CGFloat = 60
    static let leisteAbstand: CGFloat = 16        // Luft zwischen Glasleiste und Fensterrand
    static let titelHoehe: CGFloat = 30           // Platz für die Fensterknöpfe
    static let staerken: ClosedRange<Double> = 1...16

    /// Glasmaterial nach dem Vorbild von macOS 26. Auf älteren Systemen
    /// tritt das bisherige Unschärfe-Material an seine Stelle.
    static func glas(radius: CGFloat, getoent: NSColor? = nil) -> NSView {
        // Für Layoutprüfungen ohne echten Fensterhintergrund
        if ProcessInfo.processInfo.environment["SNAPIT_KEIN_GLAS"] == "1" {
            let v = NSView()
            v.wantsLayer = true
            v.layer?.backgroundColor = NSColor(srgbRed: 0.13, green: 0.145, blue: 0.138, alpha: 0.96).cgColor
            v.layer?.cornerRadius = radius
            return v
        }
        if #available(macOS 26.0, *) {
            let g = NSGlassEffectView()
            g.cornerRadius = radius
            if let t = getoent { g.tintColor = t }
            return g
        }
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .withinWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = radius
        v.layer?.masksToBounds = true
        return v
    }
}
