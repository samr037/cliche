import AppKit
import ClicheCore
import SwiftUI

/// `Cliche --snapshot <dossier> <image>` : rend les écrans de l'app en PNG (clair et sombre) pour le README.
enum Snapshots {
    static func run(out: URL, sample: URL) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for pane in SettingsModel.Pane.allCases where pane != .about {
                let m = SettingsModel()
                m.pane = pane
                let v = NSHostingView(rootView: SettingsView(m: m))
                v.frame = CGRect(x: 0, y: 0, width: 720, height: 520)
                write(v, to: out.appendingPathComponent("settings-\(pane.rawValue)-\(name).png"), appearance: appearance)
            }
            if let shot = Output.imageFromFile(sample) {
                let e = EditorWindowController(shot: shot)
                e.canvas.history.change { $0.annotations = demoAnnotations(shot.image) }
                e.canvas.tool = .arrow
                e.window?.appearance = NSAppearance(named: appearance)
                e.window?.setContentSize(CGSize(width: 1200, height: 760))
                e.show()
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
                e.zoomFit(nil)
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
                // Vraie capture de la fenêtre (les contrôles AppKit ne se rendent pas hors écran).
                if let n = e.window?.windowNumber {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    p.arguments = ["-x", "-o", "-l\(n)", out.appendingPathComponent("editor-\(name).png").path]
                    try? p.run(); p.waitUntilExit()
                }
                e.window?.close()
            }
        }
        if let shot = Output.imageFromFile(sample) {
            var doc = DocumentState()
            doc.annotations = demoAnnotations(shot.image)
            doc.backdrop = Backdrop()
            if let img = doc.render(base: shot.image), let data = Exporter.encode(img, as: .png) {
                try? data.write(to: out.appendingPathComponent("export-backdrop.png"))
            }
        }
    }

    /// Annotations de démonstration, placées en proportion de l'image.
    static func demoAnnotations(_ img: CGImage) -> [Annotation] {
        let w = CGFloat(img.width), h = CGFloat(img.height)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
        let s = max(3, w / 400)
        return [
            Annotation(kind: .arrow(from: p(0.72, 0.64), to: p(0.50, 0.41), style: .classic), color: RGBA(0.94, 0.2, 0.2), width: s * 1.6),
            Annotation(kind: .rectangle(CGRect(x: 0.27 * w, y: 0.30 * h, width: 0.22 * w, height: 0.11 * h), fill: .stroke, cornerRadius: s * 2),
                       color: RGBA(0.94, 0.2, 0.2), width: s),
            Annotation(kind: .counter(center: p(0.27, 0.30), number: 1), color: RGBA(0.94, 0.2, 0.2), width: s),
            Annotation(kind: .conceal(CGRect(x: 0.045 * w, y: 0.955 * h, width: 0.12 * w, height: 0.035 * h), style: .pixelate)),
            Annotation(kind: .text(origin: p(0.73, 0.645), string: "Latence ici", style: .box), color: RGBA(0.94, 0.2, 0.2), width: s * 1.4),
            Annotation(kind: .ruler(from: p(0.27, 0.46), to: p(0.49, 0.46)), color: RGBA(0.18, 0.5, 0.93)),
        ]
    }

    static func write(_ v: NSView, to url: URL, appearance: NSAppearance.Name) {
        v.appearance = NSAppearance(named: appearance)
        v.layoutSubtreeIfNeeded()
        v.display()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
