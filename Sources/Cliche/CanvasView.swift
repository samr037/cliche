import AppKit
import ClicheCore

enum Tool: String, CaseIterable {
    case select, arrow, line, rectangle, oval, text, freehand, highlighter, conceal, spotlight, magnifier, counter, ruler, crop

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .oval: return "circle"
        case .text: return "textformat"
        case .freehand: return "scribble"
        case .highlighter: return "highlighter"
        case .conceal: return "eye.slash"
        case .spotlight: return "flashlight.on.fill"
        case .magnifier: return "plus.magnifyingglass"
        case .counter: return "1.circle"
        case .ruler: return "ruler"
        case .crop: return "crop"
        }
    }

    var key: String {
        switch self {
        case .select: return "v"
        case .arrow: return "a"
        case .line: return "l"
        case .rectangle: return "r"
        case .oval: return "o"
        case .text: return "t"
        case .freehand: return "d"
        case .highlighter: return "h"
        case .conceal: return "b"
        case .spotlight: return "s"
        case .magnifier: return "m"
        case .counter: return "n"
        case .ruler: return "1"
        case .crop: return "c"
        }
    }

    var title: String {
        switch self {
        case .select: return String(localized: "Sélection")
        case .arrow: return String(localized: "Flèche")
        case .line: return String(localized: "Ligne")
        case .rectangle: return String(localized: "Rectangle")
        case .oval: return String(localized: "Ovale")
        case .text: return String(localized: "Texte")
        case .freehand: return String(localized: "Main levée")
        case .highlighter: return String(localized: "Surligneur")
        case .conceal: return String(localized: "Masquer (flou, pixels, effacer)")
        case .spotlight: return String(localized: "Projecteur")
        case .magnifier: return String(localized: "Loupe")
        case .counter: return String(localized: "Compteur")
        case .ruler: return String(localized: "Règle")
        case .crop: return String(localized: "Recadrer")
        }
    }
}

/// Toile de l'éditeur : affiche la capture et ses objets, gère les gestes de dessin.
/// Repère interne : pixels image, origine haut-gauche. La vue mesure image / échelle (100 % = taille réelle).
final class CanvasView: NSView {
    let base: CGImage
    let scale: CGFloat
    let pixels: PixelBuffer?
    var history = History(DocumentState()) { didSet { needsDisplay = true; onChange?() } }
    var tool: Tool = .arrow { didSet { endTextEditing(); selectedID = nil; needsDisplay = true; window?.invalidateCursorRects(for: self) } }
    var color: RGBA = Settings.shared.defaultColor
    var strokeWidth: CGFloat = Settings.shared.strokeWidth
    var arrowStyle: ArrowStyle = .classic
    var fill: ShapeFill = .stroke
    var concealStyle: ConcealStyle = .pixelate
    var textStyle: TextStyle = .box
    var shapeCorrection = true
    var rulerSensitivity = Ruler.defaultTolerance
    var selectedID: UUID? { didSet { needsDisplay = true; onSelectionChange?() } }
    var onChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?
    var onHover: ((CGPoint, RGBA?, Ruler.Extents?) -> Void)?

    private var draft: Annotation?
    private var dragStart: CGPoint?
    private var gestureStartState: DocumentState?
    private var lastPoint: CGPoint = .zero
    private var hoverPoint: CGPoint?
    private var freehandPoints: [CGPoint] = []
    private var textView: NSTextView?
    private var editingTextID: UUID?

    init(shot: Shot) {
        base = shot.image
        scale = shot.scale
        pixels = PixelBuffer(shot.image)
        super.init(frame: CGRect(x: 0, y: 0, width: CGFloat(shot.image.width) / shot.scale,
                                 height: CGFloat(shot.image.height) / shot.scale))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var doc: DocumentState { history.current }

    // MARK: Dessin

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.scaleBy(x: 1 / scale, y: 1 / scale)
        let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        // Damier pour la transparence (captures de fenêtres).
        drawCheckers(ctx, full)
        ctx.interpolationQuality = (window?.backingScaleFactor ?? 2) >= scale ? .none : .high
        Renderer.drawImage(base, in: full, ctx: ctx)
        var objs = doc.annotations
        if let d = draft { objs.append(d) }
        if tool == .freehand, freehandPoints.count > 1 {
            objs.append(Annotation(kind: .freehand(points: freehandPoints), color: color, width: strokeWidth))
        }
        if let id = editingTextID { objs.removeAll { $0.id == id } }
        Renderer.draw(objs, base: base, ctx: ctx)
        // Recadrage : assombrit l'extérieur.
        if let crop = (tool == .crop ? (draft.map { $0.bounds } ?? doc.crop) : doc.crop) {
            let p = CGMutablePath(); p.addRect(full); p.addRect(crop)
            ctx.setFillColor(NSColor.black.withAlphaComponent(tool == .crop ? 0.55 : 0.85).cgColor)
            ctx.addPath(p); ctx.fillPath(using: .evenOdd)
            ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(scale); ctx.stroke(crop)
        }
        if let id = selectedID, let a = doc.annotations.first(where: { $0.id == id }) {
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1.5 * scale)
            ctx.setLineDash(phase: 0, lengths: [4 * scale, 3 * scale])
            ctx.stroke(a.bounds.insetBy(dx: -a.width - 4, dy: -a.width - 4))
            ctx.setLineDash(phase: 0, lengths: [])
        }
        if tool == .ruler, draft == nil, let hp = hoverPoint, let px = pixels {
            drawLiveRuler(ctx, px: px, at: hp)
        }
        ctx.restoreGState()
    }

    private func drawCheckers(_ ctx: CGContext, _ r: CGRect) {
        guard base.alphaInfo != .none, base.alphaInfo != .noneSkipFirst, base.alphaInfo != .noneSkipLast else { return }
        let s: CGFloat = 8 * scale
        ctx.setFillColor(NSColor(white: 0.92, alpha: 1).cgColor); ctx.fill(r)
        ctx.setFillColor(NSColor(white: 0.8, alpha: 1).cgColor)
        var y: CGFloat = 0
        while y < r.height {
            var x: CGFloat = (Int(y / s) % 2 == 0) ? 0 : s
            while x < r.width { ctx.fill(CGRect(x: x, y: y, width: s, height: s)); x += 2 * s }
            y += s
        }
    }

    /// Règle en croix sous le curseur : distances jusqu'aux bords dans les 4 directions.
    private func drawLiveRuler(_ ctx: CGContext, px: PixelBuffer, at p: CGPoint) {
        let x = Int(p.x), y = Int(p.y)
        let e = Ruler.measure(px, x: x, y: y, tolerance: rulerSensitivity)
        let h = Annotation(kind: .ruler(from: CGPoint(x: x - e.left, y: y), to: CGPoint(x: x + e.right + 1, y: y)), color: color)
        let v = Annotation(kind: .ruler(from: CGPoint(x: x, y: y - e.up), to: CGPoint(x: x, y: y + e.down + 1)), color: color)
        Renderer.draw([h, v], base: base, ctx: ctx)
    }

    // MARK: Coordonnées

    func imagePoint(_ e: NSEvent) -> CGPoint {
        let p = convert(e.locationInWindow, from: nil)
        let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        return CGPoint(x: max(full.minX, min(full.maxX, p.x * scale)), y: max(full.minY, min(full.maxY, p.y * scale)))
    }

    /// Maj : contraint à 45° (segments) ou au carré (rectangles).
    private func constrained(_ p: CGPoint, from s: CGPoint, _ e: NSEvent, square: Bool) -> CGPoint {
        guard e.modifierFlags.contains(.shift) else { return p }
        let dx = p.x - s.x, dy = p.y - s.y
        if square {
            let m = max(abs(dx), abs(dy))
            return CGPoint(x: s.x + (dx < 0 ? -m : m), y: s.y + (dy < 0 ? -m : m))
        }
        let ang = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        let len = hypot(dx, dy)
        return CGPoint(x: s.x + cos(ang) * len, y: s.y + sin(ang) * len)
    }

    // MARK: Souris

    override func cursorUpdate(with event: NSEvent) {
        (tool == .select ? NSCursor.arrow : tool == .text ? NSCursor.iBeam : NSCursor.crosshair).set()
    }

    override func mouseMoved(with e: NSEvent) {
        let p = imagePoint(e)
        hoverPoint = p
        let x = Int(p.x), y = Int(p.y)
        if let px = pixels, x < px.width, y < px.height {
            onHover?(p, px.rgba(x, y), Ruler.measure(px, x: x, y: y, tolerance: rulerSensitivity))
        }
        if tool == .ruler { needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) { hoverPoint = nil; needsDisplay = true }

    override func scrollWheel(with e: NSEvent) {
        // Règle : la molette (avec ⌥) ajuste la sensibilité, comme dans Shottr.
        if tool == .ruler && e.modifierFlags.contains(.option) {
            rulerSensitivity = max(0, min(20, rulerSensitivity + (e.scrollingDeltaY > 0 ? 1 : -1)))
            needsDisplay = true
            return
        }
        super.scrollWheel(with: e)
    }

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        let p = imagePoint(e)
        if textView != nil { endTextEditing(); if tool == .text { return } }
        dragStart = p; lastPoint = p
        gestureStartState = doc
        switch tool {
        case .select:
            if let hit = doc.topAnnotation(at: p, tolerance: 6 * scale) {
                selectedID = hit.id
                if e.clickCount == 2, case .text = hit.kind { beginTextEditing(hit) }
            } else { selectedID = nil }
        case .text:
            if let hit = doc.topAnnotation(at: p, tolerance: 4 * scale), case .text = hit.kind {
                beginTextEditing(hit)
            } else {
                let a = Annotation(kind: .text(origin: p, string: "", style: textStyle), color: color, width: strokeWidth)
                history.change { $0.annotations.append(a) }
                beginTextEditing(a)
            }
        case .counter:
            let n = doc.nextCounter
            history.change { $0.annotations.append(Annotation(kind: .counter(center: p, number: n), color: color, width: strokeWidth)) }
        case .freehand:
            freehandPoints = [p]
        case .ruler:
            break
        default:
            // Clic sur un objet existant en mode dessin : on le déplace plutôt que d'en créer un.
            if let hit = doc.topAnnotation(at: p, tolerance: 4 * scale), e.modifierFlags.contains(.command) {
                tool = .select; selectedID = hit.id
            }
        }
    }

    override func mouseDragged(with e: NSEvent) {
        guard let s = dragStart else { return }
        let raw = imagePoint(e)
        switch tool {
        case .select:
            guard let id = selectedID, var st = Optional(doc), let i = st.annotations.firstIndex(where: { $0.id == id }) else { return }
            st.annotations[i] = st.annotations[i].offset(by: CGVector(dx: raw.x - lastPoint.x, dy: raw.y - lastPoint.y))
            history.replace(st)
            lastPoint = raw
        case .freehand:
            freehandPoints.append(raw)
            needsDisplay = true
        case .arrow, .line, .ruler:
            let p = constrained(raw, from: s, e, square: false)
            switch tool {
            case .arrow: draft = Annotation(kind: .arrow(from: s, to: p, style: arrowStyle), color: color, width: strokeWidth)
            case .line: draft = Annotation(kind: .line(from: s, to: p, style: .solid), color: color, width: strokeWidth)
            default:
                var q = p
                if let px = pixels { q = Ruler.snap(px, point: p, tolerance: rulerSensitivity) }
                draft = Annotation(kind: .ruler(from: s, to: q), color: color, width: strokeWidth)
            }
            needsDisplay = true
        case .magnifier:
            let r = max(20, s.distance(to: raw))
            draft = Annotation(kind: .magnifier(center: s, radius: r, zoom: 2.5), color: color, width: strokeWidth)
            needsDisplay = true
        case .rectangle, .oval, .highlighter, .conceal, .spotlight, .crop:
            let p = constrained(raw, from: s, e, square: true)
            let r = CGRect.spanning(s, p)
            let kind: Annotation.Kind
            switch tool {
            case .rectangle: kind = .rectangle(r, fill: fill, cornerRadius: strokeWidth)
            case .oval: kind = .oval(r, fill: fill)
            case .highlighter: kind = .highlighter(r)
            case .conceal: kind = .conceal(r, style: concealStyle)
            case .spotlight: kind = .spotlight(r, oval: fill == .fill)
            default: kind = .highlighter(r)   // recadrage : on ne garde que le rectangle
            }
            draft = Annotation(kind: kind, color: tool == .highlighter ? RGBA.yellow : color, width: strokeWidth)
            needsDisplay = true
        default: break
        }
    }

    override func mouseUp(with e: NSEvent) {
        defer { dragStart = nil; draft = nil; freehandPoints = []; needsDisplay = true }
        switch tool {
        case .select:
            if let start = gestureStartState { history.commit(from: start) }
        case .freehand:
            guard freehandPoints.count > 1 else { return }
            var kind: Annotation.Kind = .freehand(points: ShapeRecognizer.simplify(freehandPoints, epsilon: 0.6 * scale))
            if shapeCorrection {
                switch ShapeRecognizer.recognize(freehandPoints) {
                case let .line(a, b): kind = .line(from: a, to: b, style: .solid)
                case let .rectangle(r): kind = .rectangle(r, fill: .stroke, cornerRadius: strokeWidth)
                case let .ellipse(r): kind = .oval(r, fill: .stroke)
                case .none: break
                }
            }
            let a = Annotation(kind: kind, color: color, width: strokeWidth)
            history.change { $0.annotations.append(a) }
        case .ruler where draft == nil:
            // Simple clic : on fige les deux mesures de la croix.
            guard let s = dragStart, let px = pixels else { return }
            let x = Int(s.x), y = Int(s.y)
            let ex = Ruler.measure(px, x: x, y: y, tolerance: rulerSensitivity)
            let h = Annotation(kind: .ruler(from: CGPoint(x: x - ex.left, y: y), to: CGPoint(x: x + ex.right + 1, y: y)), color: color)
            let v = Annotation(kind: .ruler(from: CGPoint(x: x, y: y - ex.up), to: CGPoint(x: x, y: y + ex.down + 1)), color: color)
            history.change { $0.annotations += [h, v] }
        case .crop:
            guard let d = draft, d.bounds.width > 4, d.bounds.height > 4 else { return }
            history.change { $0.crop = d.bounds.integral }
            tool = .select
        default:
            guard let d = draft, d.bounds.width + d.bounds.height > 3 else { return }
            history.change { $0.annotations.append(d) }
        }
    }

    // MARK: Clavier

    override func keyDown(with e: NSEvent) {
        if Int(e.keyCode) == 51 || Int(e.keyCode) == 117, let id = selectedID {   // Retour arrière / Suppr
            history.change { $0.annotations.removeAll { $0.id == id } }
            selectedID = nil
            return
        }
        if e.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let ch = e.charactersIgnoringModifiers?.lowercased(), let t = Tool.allCases.first(where: { $0.key == ch }) {
            tool = t
            onSelectionChange?()
            return
        }
        // Flèches : déplacer l'objet sélectionné d'un pixel (×10 avec Maj).
        if let id = selectedID, let arrow = [123: (-1, 0), 124: (1, 0), 125: (0, 1), 126: (0, -1)][Int(e.keyCode)] {
            let step: CGFloat = e.modifierFlags.contains(.shift) ? 10 : 1
            history.change { st in
                if let i = st.annotations.firstIndex(where: { $0.id == id }) {
                    st.annotations[i] = st.annotations[i].offset(by: CGVector(dx: CGFloat(arrow.0) * step, dy: CGFloat(arrow.1) * step))
                }
            }
            return
        }
        super.keyDown(with: e)
    }

    /// Applique couleur / épaisseur à l'objet sélectionné.
    func applyStyleToSelection() {
        guard let id = selectedID else { return }
        history.change { st in
            guard let i = st.annotations.firstIndex(where: { $0.id == id }) else { return }
            st.annotations[i].color = color
            st.annotations[i].width = strokeWidth
            switch st.annotations[i].kind {
            case let .arrow(a, b, _): st.annotations[i].kind = .arrow(from: a, to: b, style: arrowStyle)
            case let .rectangle(r, _, c): st.annotations[i].kind = .rectangle(r, fill: fill, cornerRadius: c)
            case let .oval(r, _): st.annotations[i].kind = .oval(r, fill: fill)
            case let .conceal(r, _): st.annotations[i].kind = .conceal(r, style: concealStyle)
            case let .text(o, s, _): st.annotations[i].kind = .text(origin: o, string: s, style: textStyle)
            default: break
            }
        }
    }

    // MARK: Texte

    private func beginTextEditing(_ a: Annotation) {
        guard case let .text(origin, string, _) = a.kind else { return }
        editingTextID = a.id
        selectedID = a.id
        let fontSize = a.fontSize / scale
        let tv = NSTextView(frame: CGRect(x: origin.x / scale, y: origin.y / scale, width: 400, height: fontSize * 1.4))
        tv.string = string
        tv.font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        tv.textColor = a.color.nsColor
        tv.drawsBackground = true
        tv.backgroundColor = NSColor.white.withAlphaComponent(0.6)
        tv.isRichText = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.delegate = self
        addSubview(tv)
        textView = tv
        window?.makeFirstResponder(tv)
        needsDisplay = true
    }

    func endTextEditing() {
        guard let tv = textView, let id = editingTextID else { return }
        let s = tv.string
        tv.removeFromSuperview()
        textView = nil; editingTextID = nil
        history.change { st in
            guard let i = st.annotations.firstIndex(where: { $0.id == id }) else { return }
            if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { st.annotations.remove(at: i); return }
            if case let .text(o, _, style) = st.annotations[i].kind { st.annotations[i].kind = .text(origin: o, string: s, style: style) }
        }
        window?.makeFirstResponder(self)
    }

    // MARK: Export

    func renderFinal() -> CGImage? { doc.render(base: base) }
}

extension CanvasView: NSTextViewDelegate {
    func textView(_ textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(cancelOperation(_:)) { endTextEditing(); return true }
        return false
    }
}

extension RGBA {
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    init(_ c: NSColor) {
        let s = c.usingColorSpace(.sRGB) ?? .black
        self.init(Double(s.redComponent), Double(s.greenComponent), Double(s.blueComponent), Double(s.alphaComponent))
    }
}
