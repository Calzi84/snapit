import AppKit
import Vision

/// Texterkennung im Bild. Läuft lokal über das Vision-Framework,
/// kostet nichts und braucht keine Verbindung nach außen.
enum Texterkennung {

    /// Rechtecke der erkannten Textzeilen, in Bildpixeln mit Ursprung oben
    /// links — dasselbe System, in dem auch gezeichnet wird. Damit kann der
    /// Marker auf eine Zeile einrasten, statt dem Wackeln der Hand zu folgen.
    static func zeilen(_ bild: NSImage, fertig: @escaping ([CGRect]) -> Void) {
        guard let tiff = bild.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else { fertig([]); return }
        let b = CGFloat(cg.width), h = CGFloat(cg.height)

        let anfrage = VNRecognizeTextRequest { antwort, _ in
            let treffer = (antwort.results as? [VNRecognizedTextObservation]) ?? []
            // Vision misst normalisiert von unten links, hier wird auf Pixel
            // von oben links umgerechnet.
            let rechtecke = treffer.map { o -> CGRect in
                let r = o.boundingBox
                return CGRect(x: r.minX * b, y: (1 - r.maxY) * h,
                              width: r.width * b, height: r.height * h)
            }
            DispatchQueue.main.async { fertig(rechtecke) }
        }
        anfrage.recognitionLevel = .fast          // Für Zeilenlagen reicht das
        anfrage.usesLanguageCorrection = false
        anfrage.recognitionLanguages = ["de-DE", "en-US"]

        DispatchQueue.global(qos: .userInitiated).async {
            let griff = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try griff.perform([anfrage]) }
            catch { DispatchQueue.main.async { fertig([]) } }
        }
    }

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
