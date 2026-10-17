import AppKit
import ClicheCore
import ScreenCaptureKit

/// Capture défilante automatique, sur le principe de Shottr : on place le curseur dans la zone, on poste
/// des événements de molette (CGEventCreateScrollWheelEvent en pixels), on capture la zone à chaque pas
/// et on recolle les images par empreinte de lignes (ScrollStitcher). Échap ou clic arrête.
final class ScrollCapture {
    private let rect: CGRect          // points, écran global (bas-gauche)
    private let screen: NSScreen
    private let stitcher: ScrollStitcher
    private let completion: (Shot?) -> Void
    private var running = true
    private var stillCount = 0
    private var monitor: Any?
    private var localMonitor: Any?
    private var border: NSPanel?

    init(rect: CGRect, screen: NSScreen, completion: @escaping (Shot?) -> Void) {
        self.rect = rect
        self.screen = screen
        stitcher = ScrollStitcher(direction: .down, maxHeight: Settings.shared.scrollingMax)
        self.completion = completion
    }

    static func needsAccessibility() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return !AXIsProcessTrustedWithOptions(opts)
    }

    func start() {
        showBorder()
        let stop: (NSEvent) -> Void = { [weak self] _ in self?.running = false }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown], handler: stop)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { e in stop(e); return nil }
        // Curseur au centre de la zone : les événements de molette vont à la vue sous le curseur.
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: rect.midX, y: primaryH - rect.midY))
        Task { await loop() }
    }

    @MainActor private func loop() async {
        let step = Double(rect.height) * (0.25 + 0.1 * Double(max(1, min(5, Settings.shared.scrollingSpeed))))
        let interval: UInt64 = 180_000_000
        while running {
            guard let frame = await grab() else { break }
            switch stitcher.add(frame) {
            case .first, .appended: stillCount = 0
            case .noShift: stillCount += 1
            case .noMatch: stillCount += 1
            case .limitReached:
                Toast.show(String(localized: "Hauteur maximale atteinte"))
                running = false
            }
            if stillCount >= 3 { break }   // la page ne bouge plus : fin
            postScroll(pixels: Int32(step))
            try? await Task.sleep(nanoseconds: interval)
        }
        finish()
    }

    private func grab() async -> PixelBuffer? {
        guard let shot = try? await Capturer.captureScreen(screen), let crop = Capturer.crop(shot, to: rect) else { return nil }
        return PixelBuffer(crop.image)
    }

    private func postScroll(pixels: Int32) {
        let dir: Int32 = Settings.shared.reverseScroll ? 1 : -1
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dir * pixels, wheel2: 0, wheel3: 0)
        e?.post(tap: .cghidEventTap)
    }

    private func showBorder() {
        let p = NSPanel(contentRect: rect.insetBy(dx: -3, dy: -3), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        let v = NSView(frame: CGRect(origin: .zero, size: p.frame.size))
        v.wantsLayer = true
        v.layer?.borderColor = NSColor.systemRed.cgColor
        v.layer?.borderWidth = 2
        p.contentView = v
        // Exclue de la capture : SCContentFilter retire les fenêtres de notre app.
        p.orderFrontRegardless()
        border = p
        Toast.show(String(localized: "Capture défilante… Échap ou clic pour arrêter"))
    }

    private func finish() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        border?.orderOut(nil)
        guard let img = stitcher.makeImage() else { completion(nil); return }
        completion(Shot(image: img, scale: screen.backingScaleFactor))
    }
}
