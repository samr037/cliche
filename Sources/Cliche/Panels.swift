import AppKit
import ClicheCore

/// Image épinglée au-dessus de tout : glisser pour déplacer, molette pour zoomer, ⌥molette pour l'opacité,
/// double-clic ou Échap pour fermer, clic droit pour copier.
final class PinWindow: NSPanel {
    private static var pins: [PinWindow] = []
    private let image: CGImage
    private let baseSize: CGSize
    private var zoom: CGFloat = 1

    static func pin(_ img: CGImage, scale: CGFloat, near frame: CGRect?) {
        let p = PinWindow(img, scale: scale, near: frame)
        pins.append(p)
        p.orderFrontRegardless()
        p.makeKey()
    }

    init(_ img: CGImage, scale: CGFloat, near frame: CGRect?) {
        image = img
        baseSize = CGSize(width: CGFloat(img.width) / scale, height: CGFloat(img.height) / scale)
        let screen = Capturer.activeScreen.visibleFrame
        var size = baseSize
        let fit = min(1, screen.width * 0.8 / size.width, screen.height * 0.8 / size.height)
        size = CGSize(width: size.width * fit, height: size.height * fit)
        zoom = fit
        let origin = frame.map { CGPoint(x: $0.midX - size.width / 2, y: $0.midY - size.height / 2) }
            ?? CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        super.init(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        isMovableByWindowBackground = true
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let v = NSImageView(frame: CGRect(origin: .zero, size: size))
        v.image = NSImage(cgImage: img, size: baseSize)
        v.imageScaling = .scaleProportionallyUpOrDown
        v.autoresizingMask = [.width, .height]
        v.wantsLayer = true
        v.layer?.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
        v.layer?.borderWidth = 1
        contentView = v
    }

    override var canBecomeKey: Bool { true }

    override func scrollWheel(with e: NSEvent) {
        let d = e.scrollingDeltaY
        if e.modifierFlags.contains(.option) {
            alphaValue = max(0.15, min(1, alphaValue + (d > 0 ? 0.05 : -0.05)))
            return
        }
        let old = frame
        zoom = max(0.1, min(8, zoom * (d > 0 ? 1.06 : 1 / 1.06)))
        let size = CGSize(width: baseSize.width * zoom, height: baseSize.height * zoom)
        setFrame(CGRect(x: old.midX - size.width / 2, y: old.midY - size.height / 2, width: size.width, height: size.height), display: true)
    }

    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { close(); return }
        super.mouseDown(with: e)
    }

    override func rightMouseDown(with e: NSEvent) {
        let m = NSMenu()
        m.addItem(withTitle: String(localized: "Copier"), action: #selector(copyPin), keyEquivalent: "").target = self
        m.addItem(withTitle: String(localized: "Taille réelle"), action: #selector(actualSize), keyEquivalent: "").target = self
        m.addItem(withTitle: String(localized: "Fermer"), action: #selector(closePin), keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(m, with: e, for: contentView!)
    }

    @objc private func copyPin() { Output.copy(image, scale: CGFloat(image.width) / baseSize.width) }
    @objc private func actualSize() {
        zoom = 1
        setFrame(CGRect(origin: frame.origin, size: baseSize), display: true)
    }
    @objc private func closePin() { close() }
    override func cancelOperation(_ sender: Any?) { close() }

    override func close() {
        super.close()
        Self.pins.removeAll { $0 === self }
    }
}

/// Vignette en bas à droite après une capture : clic = éditeur, boutons copier / enregistrer / épingler,
/// glisser = déposer le fichier ailleurs. Disparaît seule après quelques secondes (sauf survol).
final class PreviewPanel: NSPanel {
    private static var current: PreviewPanel?
    private let shot: Shot
    private var hideTimer: Timer?
    var onOpen: ((Shot) -> Void)?

    static func show(_ shot: Shot, onOpen: @escaping (Shot) -> Void) {
        current?.dismiss()
        let p = PreviewPanel(shot)
        p.onOpen = onOpen
        current = p
        p.orderFrontRegardless()
        p.scheduleHide()
    }

    init(_ shot: Shot) {
        self.shot = shot
        let maxSide: CGFloat = 220
        let aspect = CGFloat(shot.image.width) / CGFloat(max(1, shot.image.height))
        let size = aspect >= 1 ? CGSize(width: maxSide, height: max(60, maxSide / aspect))
                               : CGSize(width: max(80, maxSide * aspect), height: maxSide)
        let vis = Capturer.activeScreen.visibleFrame
        super.init(contentRect: CGRect(x: vis.maxX - size.width - 20, y: vis.minY + 20, width: size.width, height: size.height),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let v = PreviewContentView(shot: shot, frame: CGRect(origin: .zero, size: size))
        v.panel = self
        contentView = v
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; animator().alphaValue = 1 }
    }

    func scheduleHide() {
        hideTimer?.invalidate()
        let s = Settings.shared.thumbnailSeconds
        guard s > 0 else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: s, repeats: false) { [weak self] _ in self?.dismiss() }
    }
    func pauseHide() { hideTimer?.invalidate() }

    func open() { dismiss(); onOpen?(shot) }

    func dismiss() {
        hideTimer?.invalidate()
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; animator().alphaValue = 0 }) { [weak self] in
            self?.orderOut(nil)
            if PreviewPanel.current === self { PreviewPanel.current = nil }
        }
    }
}

final class PreviewContentView: NSView, NSDraggingSource {
    let shot: Shot
    weak var panel: PreviewPanel?
    private var buttons: NSStackView!
    private var downPoint: CGPoint?

    init(shot: Shot, frame: CGRect) {
        self.shot = shot
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        let iv = NSImageView(frame: bounds)
        iv.image = NSImage(cgImage: shot.image, size: .zero)
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.autoresizingMask = [.width, .height]
        addSubview(iv)
        func b(_ sym: String, _ tip: String, _ sel: Selector) -> NSButton {
            let x = NSButton(image: NSImage(systemSymbolName: sym, accessibilityDescription: tip)!, target: self, action: sel)
            x.bezelStyle = .circular
            x.toolTip = tip
            return x
        }
        buttons = NSStackView(views: [b("doc.on.doc", String(localized: "Copier"), #selector(copyShot)),
                                      b("square.and.arrow.down", String(localized: "Enregistrer"), #selector(saveShot)),
                                      b("pin", String(localized: "Épingler"), #selector(pinShot)),
                                      b("xmark", String(localized: "Fermer"), #selector(closeShot))])
        buttons.spacing = 4
        buttons.frame = CGRect(x: 0, y: 6, width: bounds.width, height: 28)
        buttons.alignment = .centerY
        buttons.distribution = .equalCentering
        buttons.isHidden = true
        buttons.autoresizingMask = [.width]
        addSubview(buttons)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with e: NSEvent) { buttons.isHidden = false; panel?.pauseHide() }
    override func mouseExited(with e: NSEvent) { buttons.isHidden = true; panel?.scheduleHide() }
    override func mouseDown(with e: NSEvent) { downPoint = e.locationInWindow }
    override func mouseUp(with e: NSEvent) { if downPoint != nil { panel?.open() }; downPoint = nil }

    override func mouseDragged(with e: NSEvent) {
        guard let d = downPoint, hypot(e.locationInWindow.x - d.x, e.locationInWindow.y - d.y) > 4 else { return }
        downPoint = nil
        // Glisser-déposer : on écrit un PNG temporaire et on le propose comme fichier.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(Exporter.filename(date: shot.date, ext: "png"))
        guard let data = Exporter.encode(shot.image, as: .png, dpi: 72 * shot.scale), (try? data.write(to: tmp)) != nil else { return }
        let item = NSDraggingItem(pasteboardWriter: tmp as NSURL)
        item.setDraggingFrame(bounds, contents: NSImage(cgImage: shot.image, size: bounds.size))
        beginDraggingSession(with: [item], event: e, source: self)
    }

    func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint, operation: NSDragOperation) {
        if operation != [] { panel?.dismiss() }
    }

    @objc private func copyShot() { Output.copy(shot.image, scale: shot.scale); Toast.show(String(localized: "Copié")); panel?.dismiss() }
    @objc private func saveShot() {
        if let u = Output.save(shot.image, scale: shot.scale, date: shot.date) { Toast.show(String(localized: "Enregistré : \(u.lastPathComponent)")) }
        panel?.dismiss()
    }
    @objc private func pinShot() { PinWindow.pin(shot.image, scale: shot.scale, near: window?.frame); panel?.dismiss() }
    @objc private func closeShot() { panel?.dismiss() }
}
