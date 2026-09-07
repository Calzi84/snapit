import AppKit
import Carbon.HIToolbox

/// Systemweites Tastenkürzel über Carbon. Braucht keine Sonderrechte,
/// anders als ein Event-Tap.
final class Hotkey {

    private static var aktionen: [UInt32: () -> Void] = [:]
    private static var handlerSteht = false
    private static var naechsteID: UInt32 = 1

    private var referenz: EventHotKeyRef?
    private let id: UInt32

    init?(code: UInt32, modifier: UInt32, aktion: @escaping () -> Void) {
        Hotkey.handlerSicherstellen()
        id = Hotkey.naechsteID
        Hotkey.naechsteID += 1

        let hkID = EventHotKeyID(signature: OSType(0x534E4150), id: id)  // 'SNAP'
        let status = RegisterEventHotKey(code, modifier, hkID, GetApplicationEventTarget(), 0, &referenz)
        guard status == noErr, referenz != nil else { return nil }
        Hotkey.aktionen[id] = aktion
    }

    deinit {
        if let r = referenz { UnregisterEventHotKey(r) }
        Hotkey.aktionen[id] = nil
    }

    private static func handlerSicherstellen() {
        guard !handlerSteht else { return }
        handlerSteht = true
        var typ = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if let a = Hotkey.aktionen[hkID.id] {
                DispatchQueue.main.async { a() }
            }
            return noErr
        }, 1, &typ, nil, nil)
    }
}
