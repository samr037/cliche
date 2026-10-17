import AppKit
import ClicheCore
import UniformTypeIdentifiers

/// Fenêtre d'édition : barre d'outils en haut, toile au centre (zoom), barre d'état en bas (pixel, couleur, mesure).
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let shot: Shot
    let canvas: CanvasView
    private let scroll = NSScrollView()
    private let toolsControl = NSSegmentedControl()
    private let colorWell = NSColorWell()
    private let widthPopup = NSPopUpButton()
    private let stylePopup = NSPopUpButton()
    private let backdropPopup = NSPopUpButton()
    private let status = NSTextField(labelWithString: "")
    private let zoomLabel = NSTextField(labelWithString: "")
    private var lastHoverColor: RGBA?
    var onClose: ((EditorWindowController) -> Void)?
    static let widths: [CGFloat] = [2, 3, 4, 6, 8, 12]

    init(shot: Shot) {
        self.shot = shot
        canvas = CanvasView(shot: shot)
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 640),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Cliché"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.minSize = CGSize(width: 640, height: 360)
        super.init(window: w)
        w.delegate = self
        build()
        sizeWindowToFit()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Construction

    private func build() {
        guard let content = window?.contentView else { return }
        toolsControl.segmentCount = Tool.allCases.count
        toolsControl.trackingMode = .selectOne
        toolsControl.segmentStyle = .texturedRounded
        for (i, t) in Tool.allCases.enumerated() {
            toolsControl.setImage(NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.title), forSegment: i)
            toolsControl.setToolTip("\(t.title) (\(t.key.uppercased()))", forSegment: i)
            toolsControl.setWidth(30, forSegment: i)
        }
        toolsControl.target = self
        toolsControl.action = #selector(toolChanged)

        colorWell.color = canvas.color.nsColor
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        if #available(macOS 14, *) { colorWell.colorWellStyle = .minimal }

        for w in Self.widths { widthPopup.addItem(withTitle: "\(Int(w)) px") }
        widthPopup.selectItem(at: Self.widths.firstIndex(of: canvas.strokeWidth) ?? 2)
        widthPopup.target = self; widthPopup.action = #selector(widthChanged)
        stylePopup.target = self; stylePopup.action = #selector(styleChanged)

        backdropPopup.pullsDown = false
        backdropPopup.addItems(withTitles: [String(localized: "Sans fond"), String(localized: "Dégradé violet"),
                                            String(localized: "Dégradé corail"), String(localized: "Dégradé lagon"),
                                            String(localized: "Ardoise"), String(localized: "Mesh pastel"), String(localized: "Gris clair")])
        backdropPopup.toolTip = String(localized: "Fond décoratif (appliqué à l'export)")
        backdropPopup.target = self; backdropPopup.action = #selector(backdropChanged)

        func button(_ symbol: String, _ tip: String, _ sel: Selector) -> NSButton {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: sel)
            b.bezelStyle = .texturedRounded
            b.toolTip = tip
            return b
        }
        let actions = NSStackView(views: [
            button("text.viewfinder", String(localized: "Copier le texte (OCR)"), #selector(ocr)),
            button("pin", String(localized: "Épingler à l'écran (⌘P)"), #selector(pin)),
            button("square.and.arrow.down", String(localized: "Enregistrer (⌘S)"), #selector(save)),
            button("doc.on.doc", String(localized: "Copier (⌘C)"), #selector(copyImage)),
        ])
        actions.spacing = 4

        let top = NSStackView(views: [toolsControl, colorWell, widthPopup, stylePopup, backdropPopup, NSView(), actions])
        top.spacing = 8
        top.edgeInsets = NSEdgeInsets(top: 0, left: 80, bottom: 0, right: 10)
        top.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 38).isActive = true

        scroll.documentView = canvas
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.05
        scroll.maxMagnification = 16
        scroll.backgroundColor = NSColor(white: 0.16, alpha: 1)
        scroll.drawsBackground = true
        scroll.contentView = CenteringClipView()
        scroll.documentView = canvas
        scroll.translatesAutoresizingMaskIntoConstraints = false

        status.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        status.textColor = .secondaryLabelColor
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.textColor = .secondaryLabelColor
        let bottom = NSStackView(views: [status, NSView(), zoomLabel])
        bottom.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        bottom.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(top); content.addSubview(scroll); content.addSubview(bottom)
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
            top.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            top.heightAnchor.constraint(equalToConstant: 30),
            scroll.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottom.topAnchor),
            bottom.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bottom.heightAnchor.constraint(equalToConstant: 24),
        ])

        canvas.onSelectionChange = { [weak self] in self?.syncToolbar() }
        canvas.onChange = { [weak self] in self?.updateTitle() }
        canvas.onHover = { [weak self] p, c, ext in self?.hover(p, c, ext) }
        NotificationCenter.default.addObserver(self, selector: #selector(zoomChanged), name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        canvas.tool = .arrow
        syncToolbar()
        updateTitle()
    }

    private func sizeWindowToFit() {
        guard let w = window, let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame.insetBy(dx: 40, dy: 40)
        let img = canvas.frame.size
        let chrome = CGSize(width: 0, height: 70)
        let fit = min(1, (vis.width - chrome.width) / img.width, (vis.height - chrome.height) / img.height)
        let size = CGSize(width: max(760, img.width * fit + 2), height: max(420, img.height * fit + chrome.height + 2))
        w.setContentSize(size)
        w.center()
        // Le zoom ne tient qu'une fois la vue de défilement mise en page.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.contentView?.layoutSubtreeIfNeeded()
            self.scroll.magnification = fit
            self.zoomChanged()
        }
    }

    // MARK: Barre d'outils

    private func syncToolbar() {
        toolsControl.selectedSegment = Tool.allCases.firstIndex(of: canvas.tool) ?? 0
        stylePopup.removeAllItems()
        switch canvas.tool {
        case .arrow:
            stylePopup.addItems(withTitles: [String(localized: "Effilée"), String(localized: "Trait"), String(localized: "Double"), String(localized: "Ouverte")])
            stylePopup.selectItem(at: ArrowStyle.allCases.firstIndex(of: canvas.arrowStyle) ?? 0)
        case .rectangle, .oval, .spotlight:
            stylePopup.addItems(withTitles: [String(localized: "Contour"), String(localized: "Plein"), String(localized: "Contour sur blanc")])
            stylePopup.selectItem(at: ShapeFill.allCases.firstIndex(of: canvas.fill) ?? 0)
        case .conceal:
            stylePopup.addItems(withTitles: [String(localized: "Flou"), String(localized: "Pixels"), String(localized: "Effacer")])
            stylePopup.selectItem(at: ConcealStyle.allCases.firstIndex(of: canvas.concealStyle) ?? 1)
        case .text:
            stylePopup.addItems(withTitles: [String(localized: "Simple"), String(localized: "Pastille"), String(localized: "Contour")])
            stylePopup.selectItem(at: TextStyle.allCases.firstIndex(of: canvas.textStyle) ?? 1)
        case .freehand:
            stylePopup.addItems(withTitles: [String(localized: "Correction de forme"), String(localized: "Tracé libre")])
            stylePopup.selectItem(at: canvas.shapeCorrection ? 0 : 1)
        default:
            break
        }
        stylePopup.isHidden = stylePopup.numberOfItems == 0
    }

    @objc private func toolChanged() {
        canvas.tool = Tool.allCases[toolsControl.selectedSegment]
        syncToolbar()
        window?.makeFirstResponder(canvas)
    }

    @objc private func colorChanged() {
        canvas.color = RGBA(colorWell.color)
        Settings.shared.defaultColor = canvas.color
        canvas.applyStyleToSelection()
    }

    @objc private func widthChanged() {
        canvas.strokeWidth = Self.widths[widthPopup.indexOfSelectedItem]
        Settings.shared.strokeWidth = canvas.strokeWidth
        canvas.applyStyleToSelection()
    }

    @objc private func styleChanged() {
        let i = stylePopup.indexOfSelectedItem
        switch canvas.tool {
        case .arrow: canvas.arrowStyle = ArrowStyle.allCases[i]
        case .rectangle, .oval, .spotlight: canvas.fill = ShapeFill.allCases[i]
        case .conceal: canvas.concealStyle = ConcealStyle.allCases[i]
        case .text: canvas.textStyle = TextStyle.allCases[i]
        case .freehand: canvas.shapeCorrection = i == 0
        default: break
        }
        canvas.applyStyleToSelection()
    }

    @objc private func backdropChanged() {
        let i = backdropPopup.indexOfSelectedItem
        canvas.history.change { $0.backdrop = i == 0 ? nil : Backdrop(fill: Backdrop.presets[i - 1]) }
    }

    @objc private func zoomChanged() {
        zoomLabel.stringValue = "\(Int((scroll.magnification * 100).rounded())) %  ·  \(shot.image.width) × \(shot.image.height)"
    }

    private func hover(_ p: CGPoint, _ c: RGBA?, _ e: Ruler.Extents?) {
        lastHoverColor = c
        var s = "x \(Int(p.x))  y \(Int(p.y))"
        if let c { s += "   \(Settings.shared.colorFormat.string(c))" }
        if let e { s += "   ↔ \(e.width)  ↕ \(e.height)" }
        if let c, let fg = lastPickedColor {
            let r = ColorMath.contrastRatio(c, fg)
            s += String(format: "   contraste %.2f (%@)", r, ColorMath.wcagGrade(r))
        }
        status.stringValue = s
    }

    private var lastPickedColor: RGBA?

    private func updateTitle() {
        window?.title = canvas.doc.backdrop == nil ? "Cliché" : "Cliché — fond"
    }

    // MARK: Actions

    @objc func copyImage() {
        guard let img = canvas.renderFinal() else { return }
        Output.copy(img, scale: shot.scale)
        Toast.show(String(localized: "Copié dans le presse-papiers"))
    }

    @objc func save() {
        guard let img = canvas.renderFinal() else { return }
        if let url = Output.save(img, scale: shot.scale, date: shot.date) {
            Toast.show(String(localized: "Enregistré : \(url.lastPathComponent)"))
        }
    }

    @objc func saveAs() {
        guard let img = canvas.renderFinal(), let w = window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = Exporter.filename(date: shot.date, ext: "png")
        panel.directoryURL = Settings.shared.saveFolder
        panel.beginSheetModal(for: w) { r in
            guard r == .OK, let url = panel.url else { return }
            let type: UTType = url.pathExtension.lowercased().hasPrefix("jp") ? .jpeg : .png
            if let data = Exporter.encode(img, as: type, dpi: 72 * self.shot.scale) { try? data.write(to: url) }
        }
    }

    @objc func pin() {
        guard let img = canvas.renderFinal() else { return }
        PinWindow.pin(img, scale: shot.scale, near: window?.frame)
    }

    @objc func ocr() {
        let img = canvas.renderFinal() ?? shot.image
        OCR.recognize(img) { text in
            guard let text, !text.isEmpty else { Toast.show(String(localized: "Aucun texte détecté")); return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            Toast.show(String(localized: "Texte copié"))
        }
    }

    @objc func undo(_ sender: Any?) { canvas.endTextEditing(); canvas.history.undo() }
    @objc func redo(_ sender: Any?) { canvas.history.redo() }
    @objc func zoomIn(_ sender: Any?) { scroll.magnification *= 1.25; zoomChanged() }
    @objc func zoomOut(_ sender: Any?) { scroll.magnification /= 1.25; zoomChanged() }
    @objc func zoomActual(_ sender: Any?) { scroll.magnification = 1; zoomChanged() }
    @objc func zoomFit(_ sender: Any?) { scroll.magnify(toFit: canvas.bounds); zoomChanged() }
    @objc func copy(_ sender: Any?) { copyImage() }
    @objc func saveDocument(_ sender: Any?) { save() }
    @objc func saveDocumentAs(_ sender: Any?) { saveAs() }

    /// Échap : copie (réglage « copyOnEsc ») et ferme, comme Shottr.
    @objc override func cancelOperation(_ sender: Any?) {
        if canvas.tool == .crop { canvas.tool = .select; syncToolbar(); return }
        if canvas.selectedID != nil { canvas.selectedID = nil; return }
        if Settings.shared.copyOnEsc { copyImage() }
        window?.close()
    }

    func windowWillClose(_ notification: Notification) { onClose?(self) }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
    }
}

/// Garde l'image centrée quand elle est plus petite que la fenêtre.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposed: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposed)
        guard let doc = documentView else { return r }
        if r.width > doc.frame.width { r.origin.x = (doc.frame.width - r.width) / 2 }
        if r.height > doc.frame.height { r.origin.y = (doc.frame.height - r.height) / 2 }
        return r
    }
}
