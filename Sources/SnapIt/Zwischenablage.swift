import AppKit

enum Zwischenablage {

    /// Legt ein Bild als *einen* Eintrag ab, der PNG und TIFF zugleich trägt.
    ///
    /// Zwei getrennte Einträge — etwa setData(.png) und danach writeObjects —
    /// fügt WhatsApp als zwei Bilder ein. Apps, die nur eines der Formate
    /// lesen, finden es trotzdem im selben Eintrag.
    @discardableResult
    static func bild(_ bild: NSImage, auf pb: NSPasteboard = .general) -> Bool {
        guard let png = Render.png(bild) else { return false }
        let eintrag = NSPasteboardItem()
        eintrag.setData(png, forType: .png)
        if let tiff = bild.tiffRepresentation { eintrag.setData(tiff, forType: .tiff) }
        pb.clearContents()
        return pb.writeObjects([eintrag])
    }
}
