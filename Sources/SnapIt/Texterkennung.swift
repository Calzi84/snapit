import AppKit
import Vision

/// Texterkennung im Bild. Läuft lokal über das Vision-Framework,
/// kostet nichts und braucht keine Verbindung nach außen.
enum Texterkennung {

    static func lesen(_ bild: NSImage, fertig: @escaping (String?) -> Void) {
        guard let tiff = bild.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else { fertig(nil); return }

        let anfrage = VNRecognizeTextRequest { antwort, _ in
            guard let treffer = antwort.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async { fertig(nil) }; return
            }
            // Von oben nach unten, innerhalb einer Zeile von links nach rechts.
            let zeilen = treffer
                .sorted { a, b in
                    let dy = abs(a.boundingBox.midY - b.boundingBox.midY)
                    if dy > 0.012 { return a.boundingBox.midY > b.boundingBox.midY }
                    return a.boundingBox.minX < b.boundingBox.minX
                }
                .compactMap { $0.topCandidates(1).first?.string }
            let text = zeilen.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { fertig(text.isEmpty ? nil : text) }
        }
        anfrage.recognitionLevel = .accurate
        anfrage.usesLanguageCorrection = true
        anfrage.recognitionLanguages = ["de-DE", "en-US"]

        DispatchQueue.global(qos: .userInitiated).async {
            let griff = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try griff.perform([anfrage]) }
            catch { DispatchQueue.main.async { fertig(nil) } }
        }
    }
}
