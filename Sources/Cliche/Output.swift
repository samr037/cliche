import AppKit
import ClicheCore
import Vision

/// Presse-papiers et fichiers.
enum Output {
    static func copy(_ img: CGImage, scale: CGFloat) {
        let rep = NSBitmapImageRep(cgImage: img)
        rep.size = CGSize(width: CGFloat(img.width) / scale, height: CGFloat(img.height) / scale)   // 144 dpi sur Retina
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
    }

    @discardableResult
    static func save(_ img: CGImage, scale: CGFloat, date: Date = Date()) -> URL? {
        let s = Settings.shared
        var out = img, dpiScale = scale
        if s.downscaleOnSave, scale > 1, let d = Exporter.downscale(img, by: scale) { out = d; dpiScale = 1 }
        guard let (data, type) = Exporter.encode(out, format: s.saveFormat, dpi: 72 * dpiScale) else { return nil }
        let folder = s.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var url = folder.appendingPathComponent(Exporter.filename(date: date, ext: type.preferredFilenameExtension ?? "png"))
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(Exporter.filename(date: date, ext: "").dropLast() + " \(n).\(type.preferredFilenameExtension ?? "png")")
            n += 1
        }
        guard SafeFilename.isInside(url, folder: folder) else { return nil }
        do { try data.write(to: url, options: .withoutOverwriting); return url } catch {
            Toast.show(String(localized: "Échec de l'enregistrement : \(error.localizedDescription)"))
            return nil
        }
    }

    static func imageFromClipboard() -> Shot? {
        let pb = NSPasteboard.general
        guard let img = NSImage(pasteboard: pb), let rep = img.representations.first,
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = rep.size.width > 0 ? CGFloat(rep.pixelsWide) / rep.size.width : 1
        return Shot(image: cg, scale: max(1, scale.rounded()))
    }

    static func imageFromFile(_ url: URL) -> Shot? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let dpi = props?[kCGImagePropertyDPIWidth] as? Double ?? 72
        return Shot(image: cg, scale: max(1, (dpi / 72).rounded()))
    }
}

/// OCR (Vision) avec repli sur la lecture de QR code (CIDetector), comme « Instant Text/QR Recognition ».
enum OCR {
    static func recognize(_ img: CGImage, completion: @escaping (String?) -> Void) {
        if let qr = qrCode(img) { completion(qr); return }
        let req = VNRecognizeTextRequest { req, _ in
            let lines = (req.results as? [VNRecognizedTextObservation] ?? []).compactMap { $0.topCandidates(1).first?.string }
            let joiner = Settings.shared.ocrRemoveBreaks ? " " : "\n"
            DispatchQueue.main.async { completion(lines.isEmpty ? nil : lines.joined(separator: joiner)) }
        }
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.automaticallyDetectsLanguage = true
        DispatchQueue.global(qos: .userInitiated).async {
            do { try VNImageRequestHandler(cgImage: img).perform([req]) } catch { DispatchQueue.main.async { completion(nil) } }
        }
    }

    static func qrCode(_ img: CGImage) -> String? {
        let det = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let msgs = det?.features(in: CIImage(cgImage: img)).compactMap { ($0 as? CIQRCodeFeature)?.messageString } ?? []
        return msgs.isEmpty ? nil : msgs.joined(separator: "\n")
    }
}

/// Petit message flottant en bas de l'écran (remplace les notifications système).
enum Toast {
    private static var panel: NSPanel?
    private static var timer: Timer?

    static func show(_ text: String) {
        panel?.orderOut(nil)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        let size = label.intrinsicContentSize
        let w = size.width + 32, h: CGFloat = 34
        let screen = Capturer.activeScreen.visibleFrame
        let p = NSPanel(contentRect: CGRect(x: screen.midX - w / 2, y: screen.minY + 60, width: w, height: h),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient]
        let bg = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: w, height: h))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = h / 2
        bg.appearance = NSAppearance(named: .darkAqua)
        label.frame = CGRect(x: 16, y: (h - size.height) / 2, width: size.width, height: size.height)
        bg.addSubview(label)
        p.contentView = bg
        p.orderFrontRegardless()
        panel = p
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { _ in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel?.animator().alphaValue = 0 }) {
                panel?.orderOut(nil)
            }
        }
    }
}
