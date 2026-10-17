import CoreGraphics
import Foundation

/// Fond décoratif autour d'une capture (dégradé, couleur unie, image), avec marge, coins arrondis et ombre.
public struct Backdrop: Codable, Hashable, Sendable {
    public enum Fill: Codable, Hashable, Sendable {
        case none
        case solid(RGBA)
        case linear(RGBA, RGBA, angle: Double)     // angle en degrés, 0 = gauche → droite
        case mesh([RGBA])                          // 4 coins (haut-g, haut-d, bas-g, bas-d)
    }

    public var fill: Fill
    /// Marge autour de la capture, en fraction du plus grand côté.
    public var padding: Double
    public var cornerRadius: Double
    public var shadow: Double            // 0…1
    /// Rapport largeur/hauteur imposé (nil = libre), ex. 16/9 pour un post.
    public var aspect: Double?

    public init(fill: Fill = .linear(RGBA(0.40, 0.49, 0.96), RGBA(0.93, 0.38, 0.68), angle: 45),
                padding: Double = 0.08, cornerRadius: Double = 12, shadow: Double = 0.5, aspect: Double? = nil) {
        self.fill = fill; self.padding = padding; self.cornerRadius = cornerRadius; self.shadow = shadow; self.aspect = aspect
    }

    public static let presets: [Fill] = [
        .linear(RGBA(0.40, 0.49, 0.96), RGBA(0.93, 0.38, 0.68), angle: 45),
        .linear(RGBA(0.98, 0.76, 0.35), RGBA(0.96, 0.35, 0.40), angle: 135),
        .linear(RGBA(0.20, 0.83, 0.67), RGBA(0.18, 0.45, 0.89), angle: 90),
        .linear(RGBA(0.12, 0.13, 0.17), RGBA(0.28, 0.30, 0.38), angle: 90),
        .mesh([RGBA(0.99, 0.80, 0.55), RGBA(0.98, 0.55, 0.62), RGBA(0.55, 0.62, 0.99), RGBA(0.62, 0.90, 0.85)]),
        .solid(RGBA(0.95, 0.95, 0.96)),
    ]

    /// Compose l'image finale.
    public func apply(to img: CGImage) -> CGImage? {
        if case .none = fill, padding == 0 { return img }
        let w = CGFloat(img.width), h = CGFloat(img.height)
        let pad = CGFloat(padding) * max(w, h)
        var cw = w + 2 * pad, ch = h + 2 * pad
        if let a = aspect, a > 0 {
            if cw / ch < CGFloat(a) { cw = ch * CGFloat(a) } else { ch = cw / CGFloat(a) }
        }
        guard let ctx = Renderer.makeContext(width: Int(cw.rounded()), height: Int(ch.rounded())) else { return nil }
        let canvas = CGRect(x: 0, y: 0, width: cw, height: ch)
        paint(fill, in: canvas, ctx: ctx)
        let rect = CGRect(x: ((cw - w) / 2).rounded(), y: ((ch - h) / 2).rounded(), width: w, height: h)
        let r = CGFloat(cornerRadius)
        let path = CGPath(roundedRect: rect, cornerWidth: min(r, w / 2), cornerHeight: min(r, h / 2), transform: nil)
        if shadow > 0 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -max(w, h) * 0.01), blur: max(w, h) * 0.04 * CGFloat(shadow) + 4,
                          color: RGBA.black.with(alpha: 0.55 * shadow).cgColor)
            ctx.setFillColor(RGBA.black.cgColor)
            ctx.addPath(path); ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.draw(img, in: rect)
        ctx.restoreGState()
        return ctx.makeImage()
    }

    func paint(_ fill: Fill, in rect: CGRect, ctx: CGContext) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        switch fill {
        case .none:
            break
        case let .solid(c):
            ctx.setFillColor(c.cgColor); ctx.fill(rect)
        case let .linear(a, b, angle):
            guard let g = CGGradient(colorsSpace: space, colors: [a.cgColor, b.cgColor] as CFArray, locations: [0, 1]) else { return }
            let rad = angle * .pi / 180
            let dx = cos(rad) * rect.width / 2, dy = sin(rad) * rect.height / 2
            ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX - dx, y: rect.midY + dy),
                                   end: CGPoint(x: rect.midX + dx, y: rect.midY - dy), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case let .mesh(c):
            // Interpolation bilinéaire des 4 coins sur une petite grille, agrandie avec lissage.
            guard c.count == 4 else { return }
            let n = 32
            var bytes = [UInt8](repeating: 255, count: n * n * 4)
            for y in 0..<n {
                for x in 0..<n {
                    let u = Double(x) / Double(n - 1), v = Double(y) / Double(n - 1)
                    func mix(_ k: KeyPath<RGBA, Double>) -> UInt8 {
                        let top = c[0][keyPath: k] * (1 - u) + c[1][keyPath: k] * u
                        let bot = c[2][keyPath: k] * (1 - u) + c[3][keyPath: k] * u
                        return UInt8(max(0, min(255, (top * (1 - v) + bot * v) * 255)))
                    }
                    let i = (y * n + x) * 4
                    bytes[i] = mix(\.r); bytes[i + 1] = mix(\.g); bytes[i + 2] = mix(\.b)
                }
            }
            if let img = PixelBuffer(width: n, height: n, bytes: bytes).makeImage() {
                ctx.interpolationQuality = .high
                ctx.draw(img, in: rect)
            }
        }
    }
}
