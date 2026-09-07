import AppKit

// Sonderlauf fürs Build-Skript: erzeugt das Icon-Set und beendet sich.
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--iconset" {
    let ziel = URL(fileURLWithPath: CommandLine.arguments[2])
    do {
        try Symbolbild.iconsetSchreiben(nach: ziel)
        print("Iconset geschrieben: \(ziel.path)")
        exit(0)
    } catch {
        FileHandle.standardError.write("Icon fehlgeschlagen: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// Entwicklungshilfe: öffnet den Editor mit einem Bild und legt eine
// Fensteraufnahme ab. So lässt sich das Layout prüfen, ohne den Bildschirm
// aufzunehmen.
if CommandLine.arguments.count >= 4, CommandLine.arguments[1] == "--vorschau" {
    let quelle = URL(fileURLWithPath: CommandLine.arguments[2])
    let ziel = URL(fileURLWithPath: CommandLine.arguments[3])
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    guard let doc = Aufnahme.laden(quelle) else {
        FileHandle.standardError.write("Bild nicht lesbar\n".data(using: .utf8)!)
        exit(1)
    }
    let fenster = EditorFenster(doc: doc)
    fenster.zeigen()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
        guard let inhalt = fenster.window?.contentView,
              let rep = inhalt.bitmapImageRepForCachingDisplay(in: inhalt.bounds) else { exit(1) }
        inhalt.cacheDisplay(in: inhalt.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: ziel)
        print("Vorschau: \(ziel.path)")
        exit(0)
    }
    app.run()
}

// Aufnahme des Einstellungsfensters, zur Layoutpruefung
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--vorschau-einstellungen" {
    let ziel = URL(fileURLWithPath: CommandLine.arguments[2])
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let f = EinstellungenFenster()
    f.showWindow(nil)
    f.window?.makeKeyAndOrderFront(nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
        guard let inhalt = f.window?.contentView else { exit(1) }
        // Ohne eigenen Grund bleibt die Aufnahme weiss - und die helle Schrift
        // des Dunkelmodus damit unsichtbar.
        inhalt.wantsLayer = true
        inhalt.layer?.backgroundColor = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.135, alpha: 1).cgColor
        inhalt.displayIfNeeded()
        guard let rep = inhalt.bitmapImageRepForCachingDisplay(in: inhalt.bounds) else { exit(1) }
        inhalt.cacheDisplay(in: inhalt.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: ziel)
        print("Vorschau: \(ziel.path)")
        exit(0)
    }
    app.run()
}

if CommandLine.arguments.count >= 4, CommandLine.arguments[1] == "--selbsttest" {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let code = Selbsttest.starten(URL(fileURLWithPath: CommandLine.arguments[2]),
                                  ziel: URL(fileURLWithPath: CommandLine.arguments[3]))
    exit(Int32(code))
}

let app = NSApplication.shared
let delegat = AppDelegate()
app.delegate = delegat
// Kein Dock-Symbol: Snap it lebt in der Menüleiste.
app.setActivationPolicy(.accessory)
app.run()
