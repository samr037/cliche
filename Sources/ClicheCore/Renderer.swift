import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// Rend une capture et ses annotations. Tout se fait en CoreGraphics, sans AppKit :
/// l'éditeur s'en sert pour l'affichage, l'export pour le fichier final.
public enum Renderer {
    /// Image finale aux dimensions de `base` (après recadrage éventuel).
    public static func render(base: CGImage, annotations: [Annotation], crop: CGRect? = nil) -> CGImage? {
        let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let area = (crop ?? full).integral.intersection(full)
        guard area.width >= 1, area.height >= 1,
              let ctx = makeContext(width: Int(area.width), height: Int(area.height)) else { return nil }
        // Repère « haut-gauche » en pixels image, décalé par le recadrage.
        ctx.translateBy(x: 0, y: area.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -area.minX, y: -area.minY)
        drawImage(base, in: full, ctx: ctx)
        draw(annotations, base: base, ctx: ctx)
        return ctx.makeImage()
    }

    public static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// Dessine une image dans un contexte déjà retourné (haut-gauche) sans qu'elle apparaisse à l'envers.
    public static func drawImage(_ img: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// Dessine les annotations dans un contexte en repère haut-gauche, pixels image.
    public static func draw(_ annotations: [Annotation], base: CGImage, ctx: CGContext) {
        // Les masquages se dessinent d'abord : ils doivent cacher la capture, pas les flèches posées dessus.
        for a in annotations { if case .conceal = a.kind { drawOne(a, base: base, ctx: ctx) } }
        for a in annotations {
            switch a.kind {
            case .conceal, .spotlight: continue
            default: drawOne(a, base: base, ctx: ctx)
            }
        }
        let spots = annotations.compactMap { a -> (CGRect, Bool)? in
            if case let .spotlight(r, oval) = a.kind { return (r.standardized, oval) }
            return nil
        }
        if !spots.isEmpty { drawSpotlights(spots, size: CGSize(width: base.width, height: base.height), ctx: ctx) }
    }

    public static func drawOne(_ a: Annotation, base: CGImage, ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setFillColor(a.color.cgColor)
        ctx.setLineWidth(a.width)
        switch a.kind {
        case let .arrow(from, to, style):
            drawArrow(from: from, to: to, style: style, width: a.width, ctx: ctx)
        case let .line(from, to, style):
            applyDash(style, width: a.width, ctx: ctx)
            ctx.move(to: from); ctx.addLine(to: to); ctx.strokePath()
        case let .rectangle(r, fill, radius):
            let rr = r.standardized
            let cr = max(0, min(radius, rr.width / 2, rr.height / 2))
            let path = CGPath(roundedRect: rr, cornerWidth: cr, cornerHeight: cr, transform: nil)
            drawShape(path, fill: fill, color: a.color, ctx: ctx)
        case let .oval(r, fill):
            drawShape(CGPath(ellipseIn: r.standardized, transform: nil), fill: fill, color: a.color, ctx: ctx)
        case let .text(origin, string, style):
            drawText(string, at: origin, size: a.fontSize, color: a.color, style: style, ctx: ctx)
        case let .freehand(points):
            guard points.count > 1 else { return }
            ctx.addPath(smoothPath(points)); ctx.strokePath()
        case let .highlighter(r):
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(a.color.with(alpha: 0.45).cgColor)
            ctx.fill(r.standardized)
        case let .conceal(r, style):
            drawConceal(r.standardized.integral, style: style, base: base, ctx: ctx)
        case .spotlight:
            break
        case let .magnifier(center, radius, zoom):
            drawMagnifier(center: center, radius: radius, zoom: zoom, base: base, color: a.color, width: a.width, ctx: ctx)
        case let .counter(center, number):
            let r = a.counterRadius
            ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            drawCentered("\(number)", center: center, size: r * 1.15, color: a.color.contrastingInk, bold: true, ctx: ctx)
        case let .ruler(from, to):
            drawRuler(from: from, to: to, color: a.color, ctx: ctx)
        case let .image(r, data):
            if let src = CGImageSourceCreateWithData(data as CFData, nil),
               let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                drawImage(img, in: r.standardized, ctx: ctx)
            }
        }
    }

    // MARK: - Flèches et formes

    static func drawArrow(from: CGPoint, to: CGPoint, style: ArrowStyle, width w: CGFloat, ctx: CGContext) {
        let len = from.distance(to: to)
        guard len > 1 else { return }
        let ux = (to.x - from.x) / len, uy = (to.y - from.y) / len
        let nx = -uy, ny = ux
        let headLen = min(len * 0.6, max(12, w * 4.5))
        let headHalf = max(7, w * 2.6)
        func pt(_ base: CGPoint, along: CGFloat, across: CGFloat) -> CGPoint {
            CGPoint(x: base.x + ux * along + nx * across, y: base.y + uy * along + ny * across)
        }
        switch style {
        case .classic:
            // Tige effilée (tail ~25 % de la largeur), tête triangulaire légèrement creusée.
            let neck = pt(to, along: -headLen * 0.82, across: 0)
            let p = CGMutablePath()
            p.move(to: pt(from, along: 0, across: w * 0.15))
            p.addLine(to: pt(neck, along: 0, across: w * 0.6))
            p.addLine(to: pt(to, along: -headLen, across: headHalf))
            p.addLine(to: to)
            p.addLine(to: pt(to, along: -headLen, across: -headHalf))
            p.addLine(to: pt(neck, along: 0, across: -w * 0.6))
            p.addLine(to: pt(from, along: 0, across: -w * 0.15))
            p.closeSubpath()
            ctx.addPath(p); ctx.fillPath()
        case .line, .double:
            let tail = style == .double ? pt(from, along: headLen * 0.8, across: 0) : from
            ctx.move(to: tail); ctx.addLine(to: pt(to, along: -headLen * 0.8, across: 0)); ctx.strokePath()
            fillHead(at: to, ux: ux, uy: uy, len: headLen, half: headHalf, ctx: ctx)
            if style == .double { fillHead(at: from, ux: -ux, uy: -uy, len: headLen, half: headHalf, ctx: ctx) }
        case .open:
            ctx.move(to: from); ctx.addLine(to: to); ctx.strokePath()
            ctx.move(to: pt(to, along: -headLen, across: headHalf))
            ctx.addLine(to: to)
            ctx.addLine(to: pt(to, along: -headLen, across: -headHalf))
            ctx.strokePath()
        }
    }

    static func fillHead(at tip: CGPoint, ux: CGFloat, uy: CGFloat, len: CGFloat, half: CGFloat, ctx: CGContext) {
        let nx = -uy, ny = ux
        ctx.move(to: tip)
        ctx.addLine(to: CGPoint(x: tip.x - ux * len + nx * half, y: tip.y - uy * len + ny * half))
        ctx.addLine(to: CGPoint(x: tip.x - ux * len - nx * half, y: tip.y - uy * len - ny * half))
        ctx.closePath(); ctx.fillPath()
    }

    static func applyDash(_ style: LineStyle, width w: CGFloat, ctx: CGContext) {
        switch style {
        case .solid: break
        case .dashed: ctx.setLineCap(.butt); ctx.setLineDash(phase: 0, lengths: [w * 3, w * 2])
        case .dotted: ctx.setLineDash(phase: 0, lengths: [0.01, w * 2])
        }
    }

    static func drawShape(_ path: CGPath, fill: ShapeFill, color: RGBA, ctx: CGContext) {
        switch fill {
        case .stroke:
            ctx.addPath(path); ctx.strokePath()
        case .fill:
            ctx.addPath(path); ctx.fillPath()
        case .strokeOnWhite:
            ctx.setFillColor(RGBA.white.with(alpha: 0.85).cgColor)
            ctx.addPath(path); ctx.fillPath()
            ctx.addPath(path); ctx.strokePath()
        }
    }

    /// Courbe lissée passant par les milieux des segments (quadratiques), sans dépassement.
    public static func smoothPath(_ pts: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        guard let first = pts.first else { return p }
        p.move(to: first)
        if pts.count < 3 { pts.dropFirst().forEach { p.addLine(to: $0) }; return p }
        for i in 1..<(pts.count - 1) {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
            p.addQuadCurve(to: mid, control: pts[i])
        }
        p.addLine(to: pts[pts.count - 1])
        return p
    }

    // MARK: - Texte

    static func font(size: CGFloat, bold: Bool) -> CTFont {
        let f = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
        return f ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    static func attributed(_ s: String, size: CGFloat, color: RGBA, bold: Bool) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size: size, bold: bold),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ])
    }

    /// Taille du bloc de texte (multi-ligne) pour la mise en page et le hit-test.
    public static func textSize(_ s: String, size: CGFloat) -> CGSize {
        let lines = s.components(separatedBy: "\n")
        var w: CGFloat = 0
        for l in lines {
            let line = CTLineCreateWithAttributedString(attributed(l.isEmpty ? " " : l, size: size, color: .black, bold: true))
            w = max(w, CTLineGetTypographicBounds(line, nil, nil, nil))
        }
        return CGSize(width: ceil(w), height: ceil(CGFloat(lines.count) * size * 1.25))
    }

    static func drawText(_ s: String, at origin: CGPoint, size: CGFloat, color: RGBA, style: TextStyle, ctx: CGContext) {
        let sz = textSize(s, size: size)
        let pad = size * 0.3
        switch style {
        case .box:
            let box = CGRect(x: origin.x - pad, y: origin.y - pad * 0.6, width: sz.width + 2 * pad, height: sz.height + pad * 1.2)
            ctx.setFillColor(color.cgColor)
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: pad, cornerHeight: pad, transform: nil)); ctx.fillPath()
            drawLines(s, at: origin, size: size, color: color.contrastingInk, stroke: nil, ctx: ctx)
        case .outline:
            drawLines(s, at: origin, size: size, color: color, stroke: (color.contrastingInk, size * 0.18), ctx: ctx)
        case .plain:
            drawLines(s, at: origin, size: size, color: color, stroke: nil, ctx: ctx)
        }
    }

    static func drawLines(_ s: String, at origin: CGPoint, size: CGFloat, color: RGBA,
                          stroke: (RGBA, CGFloat)?, ctx: CGContext) {
        let lineH = size * 1.25
        for (i, l) in s.components(separatedBy: "\n").enumerated() where !l.isEmpty {
            let baseline = CGPoint(x: origin.x, y: origin.y + CGFloat(i) * lineH + size * 0.95)
            if let (sc, sw) = stroke {
                let a = NSMutableAttributedString(attributedString: attributed(l, size: size, color: sc, bold: true))
                a.addAttributes([NSAttributedString.Key(kCTStrokeWidthAttributeName as String): sw / size * 100,
                                 NSAttributedString.Key(kCTStrokeColorAttributeName as String): sc.cgColor],
                                range: NSRange(location: 0, length: a.length))
                drawLine(CTLineCreateWithAttributedString(a), baseline: baseline, ctx: ctx)
            }
            drawLine(CTLineCreateWithAttributedString(attributed(l, size: size, color: color, bold: true)), baseline: baseline, ctx: ctx)
        }
    }

    static func drawLine(_ line: CTLine, baseline: CGPoint, ctx: CGContext) {
        ctx.saveGState()
        // Le contexte est retourné : on remet le texte à l'endroit autour de sa ligne de base.
        ctx.textMatrix = .identity
        ctx.translateBy(x: baseline.x, y: baseline.y)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    static func drawCentered(_ s: String, center: CGPoint, size: CGFloat, color: RGBA, bold: Bool, ctx: CGContext) {
        let line = CTLineCreateWithAttributedString(attributed(s, size: size, color: color, bold: bold))
        var asc: CGFloat = 0, desc: CGFloat = 0
        let w = CTLineGetTypographicBounds(line, &asc, &desc, nil)
        drawLine(line, baseline: CGPoint(x: center.x - w / 2, y: center.y + (asc - desc) / 2), ctx: ctx)
    }

    // MARK: - Masquage, projecteur, loupe, règle

    static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func drawConceal(_ r: CGRect, style: ConcealStyle, base: CGImage, ctx: CGContext) {
        let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let rect = r.intersection(full)
        guard rect.width >= 1, rect.height >= 1 else { return }
        switch style {
        case .erase:
            ctx.setFillColor(dominantEdgeColor(base, rect: rect).cgColor)
            ctx.fill(rect)
        case .blur, .pixelate:
            // CoreImage travaille en repère bas-gauche.
            let ciRect = CGRect(x: rect.minX, y: full.height - rect.maxY, width: rect.width, height: rect.height)
            let input = CIImage(cgImage: base).clampedToExtent().cropped(to: ciRect.insetBy(dx: -40, dy: -40))
            let out: CIImage?
            if style == .blur {
                let f = CIFilter(name: "CIGaussianBlur")!
                f.setValue(input, forKey: kCIInputImageKey)
                f.setValue(max(8, min(rect.width, rect.height) / 6), forKey: kCIInputRadiusKey)
                out = f.outputImage
            } else {
                let f = CIFilter(name: "CIPixellate")!
                f.setValue(input, forKey: kCIInputImageKey)
                f.setValue(max(7, min(rect.width, rect.height) / 8), forKey: kCIInputScaleKey)   // Shottr : bloc mini 7 px
                f.setValue(CIVector(x: ciRect.minX, y: ciRect.minY), forKey: kCIInputCenterKey)
                out = f.outputImage
            }
            if let o = out, let cg = ciContext.createCGImage(o.cropped(to: ciRect), from: ciRect) {
                drawImage(cg, in: rect, ctx: ctx)
            }
        }
    }

    /// Couleur la plus fréquente sur le pourtour d'un rectangle (pour « effacer » un élément sur fond uni).
    public static func dominantEdgeColor(_ img: CGImage, rect: CGRect) -> RGBA {
        guard let px = PixelBuffer(img) else { return .white }
        var counts: [UInt32: Int] = [:]
        let r = rect.integral
        let x0 = max(0, Int(r.minX) - 1), x1 = min(px.width - 1, Int(r.maxX))
        let y0 = max(0, Int(r.minY) - 1), y1 = min(px.height - 1, Int(r.maxY))
        func add(_ x: Int, _ y: Int) { counts[px.packed(x, y) & 0xF8F8F8F8, default: 0] += 1 }
        for x in x0...x1 { add(x, y0); add(x, y1) }
        for y in y0...y1 { add(x0, y); add(x1, y) }
        let best = counts.max { $0.value < $1.value }?.key ?? 0xFFFFFFFF
        return RGBA(Double((best >> 24) & 0xFF) / 255, Double((best >> 16) & 0xFF) / 255, Double((best >> 8) & 0xFF) / 255)
    }

    static func drawSpotlights(_ spots: [(CGRect, Bool)], size: CGSize, ctx: CGContext) {
        let p = CGMutablePath()
        p.addRect(CGRect(origin: .zero, size: size))
        for (r, oval) in spots {
            if oval { p.addEllipse(in: r) } else { p.addRoundedRect(in: r, cornerWidth: 4, cornerHeight: 4) }
        }
        ctx.setFillColor(RGBA.black.with(alpha: 0.5).cgColor)
        ctx.addPath(p)
        ctx.fillPath(using: .evenOdd)
    }

    static func drawMagnifier(center: CGPoint, radius: CGFloat, zoom: CGFloat, base: CGImage,
                              color: RGBA, width: CGFloat, ctx: CGContext) {
        let src = radius / max(zoom, 1)
        let srcRect = CGRect(x: center.x - src, y: center.y - src, width: 2 * src, height: 2 * src).integral
        let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        guard let crop = base.cropping(to: srcRect.intersection(full)) else { return }
        let dest = CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
        ctx.saveGState()
        ctx.addEllipse(in: dest); ctx.clip()
        ctx.interpolationQuality = .none   // pixels nets, comme une loupe de développeur
        let clipped = srcRect.intersection(full)
        let scale = dest.width / srcRect.width
        drawImage(crop, in: CGRect(x: dest.minX + (clipped.minX - srcRect.minX) * scale,
                                   y: dest.minY + (clipped.minY - srcRect.minY) * scale,
                                   width: clipped.width * scale, height: clipped.height * scale), ctx: ctx)
        ctx.restoreGState()
        ctx.setLineWidth(max(2, width * 0.75))
        ctx.strokeEllipse(in: dest)
    }

    static func drawRuler(from: CGPoint, to: CGPoint, color: RGBA, ctx: CGContext) {
        let len = from.distance(to: to)
        guard len > 0 else { return }
        let ux = (to.x - from.x) / len, uy = (to.y - from.y) / len
        let nx = -uy * 6, ny = ux * 6
        ctx.setLineWidth(1.5)
        ctx.move(to: from); ctx.addLine(to: to)
        for p in [from, to] { ctx.move(to: CGPoint(x: p.x - nx, y: p.y - ny)); ctx.addLine(to: CGPoint(x: p.x + nx, y: p.y + ny)) }
        ctx.strokePath()
        let label = Ruler.label(from: from, to: to)
        let size: CGFloat = 13
        let tw = textSize(label, size: size).width + 10
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let box = CGRect(x: mid.x - tw / 2, y: mid.y - 22, width: tw, height: 18)
        ctx.setFillColor(color.cgColor)
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: 4, cornerHeight: 4, transform: nil)); ctx.fillPath()
        drawCentered(label, center: CGPoint(x: box.midX, y: box.midY), size: size, color: color.contrastingInk, bold: true, ctx: ctx)
    }
}
