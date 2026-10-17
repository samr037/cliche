import AppKit
import ClicheCore
import ScreenCaptureKit

/// Écran figé plein cadre sur lequel on choisit une zone (glisser) ou une fenêtre (clic).
/// Comme Shottr : l'image est capturée d'abord, la sélection se fait sur cette image gelée.
final class AreaSelector: NSWindow {
    enum Mode { case area, window }
    enum Result { case area(CGRect), window(SCWindow), cancelled }

    private let selView: SelectionView
    private var completion: ((Result) -> Void)?

    init(screen: NSScreen, frozen: Shot, mode: Mode, windows: [SCWindow], completion: @escaping (Result) -> Void) {
        selView = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), frozen: frozen, mode: mode,
                                windows: windows, screen: screen)
        self.completion = completion
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = selView
        setFrame(screen.frame, display: false)
        selView.onDone = { [weak self] r in self?.finish(r) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(selView)
        NSCursor.crosshair.push()
    }

    private func finish(_ r: Result) {
        NSCursor.pop()
        orderOut(nil)
        let c = completion
        completion = nil
        c?(r)
    }
}

final class SelectionView: NSView {
    let frozen: Shot
    let mode: AreaSelector.Mode
    let screen: NSScreen
    let windows: [(SCWindow, CGRect)]   // cadre en points, repère de la vue
    var onDone: ((AreaSelector.Result) -> Void)?
    private let pixels: PixelBuffer?
    private var start: CGPoint?
    private var current: CGPoint = .zero
    private var selection: CGRect?
    private var hoverWindow: Int?

    init(frame: CGRect, frozen: Shot, mode: AreaSelector.Mode, windows: [SCWindow], screen: NSScreen) {
        self.frozen = frozen; self.mode = mode; self.screen = screen
        let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        // SCWindow.frame : repère Quartz global (haut-gauche) → repère de la vue (bas-gauche, local à l'écran).
        self.windows = windows.map { w in
            let f = w.frame
            let cocoa = CGRect(x: f.minX, y: primaryH - f.maxY, width: f.width, height: f.height)
            return (w, cocoa.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY))
        }
        pixels = PixelBuffer(frozen.image)
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
        current = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none
        ctx.draw(frozen.image, in: bounds)
        let dim = NSColor.black.withAlphaComponent(0.35)
        let hole: CGRect? = mode == .area ? selection : hoverWindow.map { windows[$0].1 }
        let p = CGMutablePath()
        p.addRect(bounds)
        if let h = hole { p.addRect(h) }
        ctx.addPath(p); ctx.setFillColor(dim.cgColor); ctx.fillPath(using: .evenOdd)
        if let h = hole {
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(h.insetBy(dx: -0.5, dy: -0.5))
            if mode == .area { drawSizeLabel(for: h) }
        }
        if mode == .area {
            if selection == nil { drawCrosshair(ctx) }
            drawLoupe(ctx)
        }
    }

    private func drawCrosshair(_ ctx: CGContext) {
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.move(to: CGPoint(x: 0, y: current.y.rounded() + 0.5)); ctx.addLine(to: CGPoint(x: bounds.maxX, y: current.y.rounded() + 0.5))
        ctx.move(to: CGPoint(x: current.x.rounded() + 0.5, y: 0)); ctx.addLine(to: CGPoint(x: current.x.rounded() + 0.5, y: bounds.maxY))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
    }

    private func drawSizeLabel(for r: CGRect) {
        let s = frozen.scale
        let text = "\(Int((r.width * s).rounded())) × \(Int((r.height * s).rounded()))"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                                                    .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        var o = CGPoint(x: r.minX, y: r.minY - size.height - 8)
        if o.y < 4 { o.y = r.minY + 6; o.x += 6 }
        let box = CGRect(x: o.x, y: o.y, width: size.width + 12, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 6, y: box.minY + 2), withAttributes: attrs)
    }

    /// Loupe ×8 sur les pixels sous le curseur, avec coordonnées et couleur (sélection au pixel près).
    private func drawLoupe(_ ctx: CGContext) {
        guard let px = pixels else { return }
        let s = frozen.scale
        let ix = Int(current.x * s), iy = Int((bounds.height - current.y) * s)
        guard ix >= 0, iy >= 0, ix < px.width, iy < px.height else { return }
        let cells = 15, cell: CGFloat = 8
        let side = CGFloat(cells) * cell
        var origin = CGPoint(x: current.x + 24, y: current.y - side - 24)
        if origin.x + side > bounds.maxX { origin.x = current.x - side - 24 }
        if origin.y < 0 { origin.y = current.y + 24 }
        let loupe = CGRect(origin: origin, size: CGSize(width: side, height: side))
        let src = CGRect(x: ix - cells / 2, y: iy - cells / 2, width: cells, height: cells)
        ctx.saveGState()
        let clip = NSBezierPath(roundedRect: loupe, xRadius: 8, yRadius: 8)
        clip.addClip()
        NSColor.black.setFill(); loupe.fill()
        if let crop = frozen.image.cropping(to: src) {
            ctx.interpolationQuality = .none
            let dx = CGFloat(src.minX - CGFloat(ix - cells / 2)) * cell
            ctx.draw(crop, in: CGRect(x: loupe.minX + dx, y: loupe.minY, width: CGFloat(crop.width) * cell, height: CGFloat(crop.height) * cell))
        }
        let mid = CGRect(x: loupe.minX + CGFloat(cells / 2) * cell, y: loupe.minY + CGFloat(cells / 2) * cell, width: cell, height: cell)
        ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(1); ctx.stroke(mid)
        ctx.restoreGState()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        clip.lineWidth = 1.5; clip.stroke()
        let c = px.rgba(ix, iy)
        let info = "\(ix), \(iy)  \(ColorFormat.hex.string(c))"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                                                    .foregroundColor: NSColor.white]
        let box = CGRect(x: loupe.minX, y: loupe.minY - 20, width: side, height: 18)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (info as NSString).draw(at: CGPoint(x: box.minX + 6, y: box.minY + 2), withAttributes: attrs)
    }

    override func mouseMoved(with e: NSEvent) {
        current = convert(e.locationInWindow, from: nil)
        if mode == .window { hoverWindow = windows.firstIndex { $0.1.contains(current) } }
        needsDisplay = true
    }

    override func mouseDown(with e: NSEvent) {
        current = convert(e.locationInWindow, from: nil)
        if mode == .area { start = snapToPixel(current); selection = nil }
    }

    override func mouseDragged(with e: NSEvent) {
        current = convert(e.locationInWindow, from: nil)
        guard mode == .area, let s = start else { return }
        selection = CGRect.spanning(s, snapToPixel(current)).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        switch mode {
        case .area:
            guard let r = selection, r.width >= 2, r.height >= 2 else {
                // Simple clic : on prend la zone uniforme sous le curseur si elle est nette (comme la règle), sinon l'écran.
                onDone?(.area(toGlobal(bounds)))
                return
            }
            onDone?(.area(toGlobal(r)))
        case .window:
            if let i = hoverWindow { onDone?(.window(windows[i].0)) } else { onDone?(.cancelled) }
        }
    }

    override func keyDown(with e: NSEvent) {
        switch Int(e.keyCode) {
        case 53: onDone?(.cancelled)                         // Échap
        case 36, 76: onDone?(.area(toGlobal(selection ?? bounds)))   // Entrée : sélection ou écran entier
        case 49:                                             // Espace : bascule zone ↔ fenêtre non gérée, on ignore
            break
        default: super.keyDown(with: e)
        }
    }

    private func snapToPixel(_ p: CGPoint) -> CGPoint {
        let s = frozen.scale
        return CGPoint(x: (p.x * s).rounded() / s, y: (p.y * s).rounded() / s)
    }

    private func toGlobal(_ r: CGRect) -> CGRect { r.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY) }
}
