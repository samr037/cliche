import CoreGraphics
import Foundation

/// Règle « intelligente » : depuis un point, s'étend tant que les pixels restent semblables,
/// et s'arrête au premier bord net. Sert à mesurer un bouton, une marge, un espacement.
public enum Ruler {
    public struct Extents: Equatable, Sendable {
        /// Distances (px) jusqu'au bord, exclusives : le pixel au bord ne fait pas partie de la zone.
        public var left, right, up, down: Int
        public var width: Int { left + right + 1 }
        public var height: Int { up + down + 1 }
    }

    /// Sensibilité par défaut (Shottr la règle à la molette, bornée à 0…20 ; sa valeur initiale n'a pas été retrouvée).
    public static let defaultTolerance = 4

    /// Seuil de bord pour une sensibilité `s` : somme des écarts R+G+B entre pixels voisins > 2·s² (comme Shottr).
    public static func threshold(_ s: Int) -> Int { 2 * s * s }

    /// Mesure autour de (x, y) : on avance tant que chaque pixel ressemble à son voisin précédent.
    public static func measure(_ px: PixelBuffer, x: Int, y: Int, tolerance: Int = defaultTolerance) -> Extents {
        guard x >= 0, y >= 0, x < px.width, y < px.height else { return Extents(left: 0, right: 0, up: 0, down: 0) }
        let limit = threshold(max(0, min(20, tolerance)))
        func run(_ dx: Int, _ dy: Int) -> Int {
            var n = 0, cx = x + dx, cy = y + dy
            while cx >= 0, cy >= 0, cx < px.width, cy < px.height, px.sumDiff(cx - dx, cy - dy, cx, cy) <= limit {
                n += 1; cx += dx; cy += dy
            }
            return n
        }
        return Extents(left: run(-1, 0), right: run(1, 0), up: run(0, -1), down: run(0, 1))
    }

    /// Plus petit rectangle uniforme autour d'un point (intersection des deux axes de mesure).
    public static func box(_ px: PixelBuffer, x: Int, y: Int, tolerance: Int = defaultTolerance) -> CGRect {
        let e = measure(px, x: x, y: y, tolerance: tolerance)
        return CGRect(x: x - e.left, y: y - e.up, width: e.width, height: e.height)
    }

    /// Libellé d'une mesure entre deux points : « 120 px », ou « 120 × 45 px · 128 » en diagonale.
    public static func label(from a: CGPoint, to b: CGPoint, scale: CGFloat = 1, unit: String = "px") -> String {
        let dx = abs(b.x - a.x) / scale, dy = abs(b.y - a.y) / scale
        func f(_ v: CGFloat) -> String { String(Int(v.rounded())) }
        if dy < 0.5 { return "\(f(dx)) \(unit)" }
        if dx < 0.5 { return "\(f(dy)) \(unit)" }
        return "\(f(dx)) × \(f(dy)) \(unit) · \(f(hypot(dx, dy)))"
    }

    /// Accroche un point au bord le plus proche dans un rayon (pour poser une règle précisément).
    public static func snap(_ px: PixelBuffer, point p: CGPoint, radius: Int = 6, tolerance: Int = defaultTolerance) -> CGPoint {
        let x = Int(p.x), y = Int(p.y)
        guard x > 0, y > 0, x < px.width - 1, y < px.height - 1 else { return p }
        var best: (Int, CGPoint)? = nil
        for dy in -radius...radius {
            for dx in -radius...radius {
                let cx = x + dx, cy = y + dy
                guard cx > 0, cy > 0, cx < px.width - 1, cy < px.height - 1 else { continue }
                let t = threshold(tolerance)
                let edge = px.sumDiff(cx, cy, cx - 1, cy) > t || px.sumDiff(cx, cy, cx, cy - 1) > t
                if edge {
                    let d = dx * dx + dy * dy
                    if best == nil || d < best!.0 { best = (d, CGPoint(x: cx, y: cy)) }
                }
            }
        }
        return best?.1 ?? p
    }
}
