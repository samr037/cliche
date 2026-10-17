import CoreGraphics
import Foundation

/// Couleur RGBA en espace sRGB, composantes 0…1.
public struct RGBA: Codable, Hashable, Sendable {
    public var r, g, b, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public static let red = RGBA(0.94, 0.20, 0.20)
    public static let black = RGBA(0, 0, 0)
    public static let white = RGBA(1, 1, 1)
    public static let yellow = RGBA(1, 0.86, 0.1)

    public var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    public func with(alpha: Double) -> RGBA { RGBA(r, g, b, alpha) }
    /// Luminance relative WCAG 2.x.
    public var relativeLuminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    /// Noir ou blanc selon ce qui contraste le mieux (texte sur pastille, compteur…).
    public var contrastingInk: RGBA { relativeLuminance > 0.4 ? .black : .white }
}

public enum ArrowStyle: String, Codable, CaseIterable, Sendable {
    case classic      // tige qui s'affine + tête pleine
    case line         // trait uniforme + tête pleine
    case double       // tête aux deux bouts
    case open         // tête en chevron
}

public enum LineStyle: String, Codable, CaseIterable, Sendable { case solid, dashed, dotted }

public enum ShapeFill: String, Codable, CaseIterable, Sendable {
    case stroke        // contour seul
    case fill          // plein
    case strokeOnWhite // contour + fond blanc semi-opaque (lisibilité sur capture chargée)
}

public enum ConcealStyle: String, Codable, CaseIterable, Sendable {
    case blur, pixelate, erase   // erase = remplissage par la couleur de bord dominante
}

public enum TextStyle: String, Codable, CaseIterable, Sendable {
    case plain       // texte coloré, halo contrastant
    case box         // texte contrasté dans une pastille de la couleur choisie
    case outline     // texte avec contour épais
}

/// Un objet dessiné sur la capture. Coordonnées en pixels de l'image (origine en haut à gauche).
public struct Annotation: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        case arrow(from: CGPoint, to: CGPoint, style: ArrowStyle)
        case line(from: CGPoint, to: CGPoint, style: LineStyle)
        case rectangle(CGRect, fill: ShapeFill, cornerRadius: CGFloat)
        case oval(CGRect, fill: ShapeFill)
        case text(origin: CGPoint, string: String, style: TextStyle)
        case freehand(points: [CGPoint])
        case highlighter(CGRect)
        case conceal(CGRect, style: ConcealStyle)
        case spotlight(CGRect, oval: Bool)
        case magnifier(center: CGPoint, radius: CGFloat, zoom: CGFloat)
        case counter(center: CGPoint, number: Int)
        case ruler(from: CGPoint, to: CGPoint)
        case image(CGRect, pngData: Data)
    }

    public var id: UUID
    public var kind: Kind
    public var color: RGBA
    /// Épaisseur de trait (px image) ; taille du texte = width × 4.
    public var width: CGFloat

    public init(id: UUID = UUID(), kind: Kind, color: RGBA = .red, width: CGFloat = 4) {
        self.id = id; self.kind = kind; self.color = color; self.width = width
    }

    public var fontSize: CGFloat { max(10, width * 4) }

    /// Rectangle englobant (sans marge de trait) pour le hit-test et la sélection.
    public var bounds: CGRect {
        switch kind {
        case let .arrow(a, b, _), let .line(a, b, _), let .ruler(a, b):
            return CGRect.spanning(a, b)
        case let .rectangle(r, _, _), let .oval(r, _), let .highlighter(r), let .conceal(r, _),
             let .spotlight(r, _), let .image(r, _):
            return r.standardized
        case let .text(o, s, _):
            let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
            let longest = lines.map(\.count).max() ?? 0
            return CGRect(x: o.x, y: o.y, width: max(fontSize, CGFloat(longest) * fontSize * 0.6),
                          height: CGFloat(max(1, lines.count)) * fontSize * 1.25)
        case let .freehand(pts):
            return CGRect.bounding(pts)
        case let .magnifier(c, r, _):
            return CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        case let .counter(c, _):
            let r = counterRadius
            return CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        }
    }

    public var counterRadius: CGFloat { max(12, width * 3.5) }

    /// Déplace l'objet d'un vecteur.
    public func offset(by d: CGVector) -> Annotation {
        var c = self
        func p(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x + d.dx, y: q.y + d.dy) }
        func r(_ q: CGRect) -> CGRect { q.offsetBy(dx: d.dx, dy: d.dy) }
        switch kind {
        case let .arrow(a, b, s): c.kind = .arrow(from: p(a), to: p(b), style: s)
        case let .line(a, b, s): c.kind = .line(from: p(a), to: p(b), style: s)
        case let .ruler(a, b): c.kind = .ruler(from: p(a), to: p(b))
        case let .rectangle(q, f, cr): c.kind = .rectangle(r(q), fill: f, cornerRadius: cr)
        case let .oval(q, f): c.kind = .oval(r(q), fill: f)
        case let .highlighter(q): c.kind = .highlighter(r(q))
        case let .conceal(q, s): c.kind = .conceal(r(q), style: s)
        case let .spotlight(q, o): c.kind = .spotlight(r(q), oval: o)
        case let .image(q, data): c.kind = .image(r(q), pngData: data)
        case let .text(o, s, st): c.kind = .text(origin: p(o), string: s, style: st)
        case let .freehand(pts): c.kind = .freehand(points: pts.map(p))
        case let .magnifier(ce, ra, z): c.kind = .magnifier(center: p(ce), radius: ra, zoom: z)
        case let .counter(ce, n): c.kind = .counter(center: p(ce), number: n)
        }
        return c
    }

    /// Vrai si `pt` touche l'objet (tolérance en px image).
    public func hitTest(_ pt: CGPoint, tolerance: CGFloat = 6) -> Bool {
        let tol = tolerance + width / 2
        switch kind {
        case let .arrow(a, b, _), let .line(a, b, _), let .ruler(a, b):
            return pt.distance(toSegment: a, b) <= tol
        case let .freehand(pts):
            return zip(pts, pts.dropFirst()).contains { pt.distance(toSegment: $0, $1) <= tol }
        case let .rectangle(r, fill, _):
            let rr = r.standardized
            if fill == .fill { return rr.insetBy(dx: -tol, dy: -tol).contains(pt) }
            return rr.insetBy(dx: -tol, dy: -tol).contains(pt) && !rr.insetBy(dx: tol, dy: tol).contains(pt)
        case let .oval(r, fill):
            let rr = r.standardized
            guard rr.width > 0, rr.height > 0 else { return false }
            let nx = (pt.x - rr.midX) / (rr.width / 2), ny = (pt.y - rr.midY) / (rr.height / 2)
            let d = (nx * nx + ny * ny).squareRoot()
            let rel = tol / min(rr.width, rr.height) * 2
            return fill == .fill ? d <= 1 + rel : abs(d - 1) <= rel
        default:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(pt)
        }
    }
}

public extension CGRect {
    static func spanning(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
    static func bounding(_ pts: [CGPoint]) -> CGRect {
        guard let f = pts.first else { return .zero }
        var r = CGRect(origin: f, size: .zero)
        for p in pts.dropFirst() { r = r.union(CGRect(origin: p, size: .zero)) }
        return r
    }
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

public extension CGPoint {
    func distance(to p: CGPoint) -> CGFloat { hypot(x - p.x, y - p.y) }
    func distance(toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return distance(to: a) }
        let t = max(0, min(1, ((x - a.x) * dx + (y - a.y) * dy) / len2))
        return distance(to: CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }
}
