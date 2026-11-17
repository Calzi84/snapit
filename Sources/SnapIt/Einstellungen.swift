import AppKit
import Carbon.HIToolbox

/// Alle Einstellungen liegen in den UserDefaults. Die Ordner werden beim
/// ersten Start unter ~/Pictures/Snap it angelegt.
final class Einstellungen {

    static let geteilt = Einstellungen()
    private let d = UserDefaults.standard

    static let geaendert = Notification.Name("SnapItEinstellungenGeaendert")

    private init() {
        d.register(defaults: [
            "hotkeyCode": Int(kVK_ANSI_2),
            "hotkeyModifier": Int(cmdKey | shiftKey),
            "nachSichernKopieren": true,
            "imFinderZeigen": false,
            "standardFarbe": 0,
            "standardStaerke": 4.0,
            "dateiMuster": "Snap it %d um %t",
        ])
        ordnerSicherstellen()
    }

    // MARK: – Ordner

    var basisOrdner: URL {
        let bilder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return bilder.appendingPathComponent("Snap it", isDirectory: true)
    }

    var bilderOrdner: URL {
        get {
            if let p = d.string(forKey: "bilderOrdner") { return URL(fileURLWithPath: p) }
            return basisOrdner.appendingPathComponent("Aufnahmen", isDirectory: true)
        }
        set { d.set(newValue.path, forKey: "bilderOrdner"); ordnerSicherstellen(); melden() }
    }

    var ideenOrdner: URL {
        get {
            if let p = d.string(forKey: "ideenOrdner") { return URL(fileURLWithPath: p) }
            return basisOrdner.appendingPathComponent("Ideen", isDirectory: true)
        }
        set { d.set(newValue.path, forKey: "ideenOrdner"); ordnerSicherstellen(); melden() }
    }

    func ordnerSicherstellen() {
        for o in [bilderOrdner, ideenOrdner] {
            try? FileManager.default.createDirectory(at: o, withIntermediateDirectories: true)
        }
    }

    // MARK: – Tastenkürzel

    var hotkeyCode: UInt32 {
        get { UInt32(d.integer(forKey: "hotkeyCode")) }
        set { d.set(Int(newValue), forKey: "hotkeyCode"); melden() }
    }

    var hotkeyModifier: UInt32 {
        get { UInt32(d.integer(forKey: "hotkeyModifier")) }
        set { d.set(Int(newValue), forKey: "hotkeyModifier"); melden() }
    }

    var hotkeyText: String { Tastatur.beschreibung(code: hotkeyCode, carbonModifier: hotkeyModifier) }

    // MARK: – Verhalten

    var nachSichernKopieren: Bool {
        get { d.bool(forKey: "nachSichernKopieren") }
        set { d.set(newValue, forKey: "nachSichernKopieren") }
    }

    var imFinderZeigen: Bool {
        get { d.bool(forKey: "imFinderZeigen") }
        set { d.set(newValue, forKey: "imFinderZeigen") }
    }

    var standardFarbe: Int {
        get { min(max(d.integer(forKey: "standardFarbe"), 0), Theme.palette.count - 1) }
        set { d.set(newValue, forKey: "standardFarbe") }
    }

    var standardStaerke: Double {
        get { d.double(forKey: "standardStaerke") }
        set { d.set(newValue, forKey: "standardStaerke") }
    }

    /// Dateiname mit Datum und Uhrzeit, so wie macOS es auch macht.
    func dateiname(praefix: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "yyyy-MM-dd 'um' HH.mm.ss"
        return "\(praefix) \(f.string(from: Date())).png"
    }

    /// Freier Dateiname im Bilder-Ordner — vorhandene Dateien werden nicht
    /// überschrieben, sondern es wird durchnummeriert.
    func freieDatei(_ name: String) -> URL {
        let ordner = bilderOrdner
        var ziel = ordner.appendingPathComponent("\(name).png")
        var zaehler = 2
        while FileManager.default.fileExists(atPath: ziel.path) {
            ziel = ordner.appendingPathComponent("\(name) \(zaehler).png")
            zaehler += 1
        }
        return ziel
    }

    private func melden() {
        NotificationCenter.default.post(name: Einstellungen.geaendert, object: nil)
    }
}

/// Umrechnung von Tastencodes in lesbare Kürzel — berücksichtigt das
/// aktuelle Tastaturlayout, damit auf einer deutschen Tastatur auch
/// deutsche Zeichen erscheinen.
enum Tastatur {

    static func beschreibung(code: UInt32, carbonModifier: UInt32) -> String {
        var s = ""
        if carbonModifier & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifier & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifier & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifier & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + zeichen(code)
    }

    static func zeichen(_ code: UInt32) -> String {
        let sonder: [UInt32: String] = [
            UInt32(kVK_Space): "Leertaste", UInt32(kVK_Return): "⏎", UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Escape): "⎋", UInt32(kVK_Delete): "⌫",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        ]
        if let s = sonder[code] { return s }

        guard let quelle = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let zeiger = TISGetInputSourceProperty(quelle, kTISPropertyUnicodeKeyLayoutData)
        else { return "?" }
        let daten = Unmanaged<CFData>.fromOpaque(zeiger).takeUnretainedValue() as Data

        var ergebnis = "?"
        daten.withUnsafeBytes { roh in
            guard let layout = roh.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            var totZustand: UInt32 = 0
            var laenge = 0
            var puffer = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                        UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                        &totZustand, puffer.count, &laenge, &puffer)
            if status == noErr, laenge > 0 {
                ergebnis = String(utf16CodeUnits: puffer, count: laenge).uppercased()
            }
        }
        return ergebnis
    }

    /// Nennt den Systemkurzbefehl, falls die Kombination von macOS belegt ist.
    ///
    /// Solche Kürzel lassen sich zwar registrieren — RegisterEventHotKey meldet
    /// sogar Erfolg —, das System bekommt die Taste aber zuerst. Ohne Hinweis
    /// sähe es für den Nutzer so aus, als sei die App defekt.
    static func systemkurzbefehl(code: UInt32, carbonModifier m: UInt32) -> String? {
        let cmdShift = UInt32(cmdKey | shiftKey)
        let cmdShiftCtrl = UInt32(cmdKey | shiftKey | controlKey)
        guard m == cmdShift || m == cmdShiftCtrl else { return nil }
        switch code {
        case UInt32(kVK_ANSI_3): return "Bildschirmfoto vom ganzen Bildschirm"
        case UInt32(kVK_ANSI_4): return "Bildschirmfoto von einem Ausschnitt"
        case UInt32(kVK_ANSI_5): return "Bildschirmfoto- und Aufnahmeoptionen"
        default: return nil
        }
    }

    /// Rechnet die Modifier eines NSEvent in Carbon-Flags um.
    static func carbonModifier(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }
}
