import CoreGraphics
import Foundation

/// Correction de forme pour le dessin à main levée : un trait presque droit devient une ligne,
/// un tracé fermé devient un rectangle ou une ellipse. Sinon le tracé reste libre.
public enum ShapeRecognizer {
    public enum Shape: Equatable, Sendable {
        case line(CGPoint, CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case none
    }

    public static func recognize(_ pts: [CGPoint]) -> Shape {
        guard pts.count >= 3 else {
            if pts.count == 2 { return .line(pts[0], pts[1]) }
            return .none
        }
        let first = pts[0], last = pts[pts.count - 1]
        let pathLen = zip(pts, pts.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        guard pathLen > 8 else { return .none }

        // Ligne : la corde explique presque toute la longueur et aucun point ne s'en écarte.
        let chord = first.distance(to: last)
        let maxDev = pts.map { $0.distance(toSegment: first, last) }.max() ?? 0
        if chord / pathLen > 0.92 && maxDev < max(6, chord * 0.06) { return .line(first, last) }

        // Forme fermée : les extrémités se rejoignent (relativement à la taille du tracé).
        let box = CGRect.bounding(pts)
        let diag = hypot(box.width, box.height)
        guard diag > 16, chord < diag * 0.25, box.width > 8, box.height > 8 else { return .none }

        // Écart moyen normalisé à l'ellipse inscrite et au rectangle.
        let cx = box.midX, cy = box.midY, rx = box.width / 2, ry = box.height / 2
        var eErr: CGFloat = 0, rErr: CGFloat = 0
        for p in pts {
            let nx = (p.x - cx) / rx, ny = (p.y - cy) / ry
            eErr += abs((nx * nx + ny * ny).squareRoot() - 1)
            // Distance au bord du rectangle, normalisée par demi-axe : 0 sur le contour.
            rErr += min(abs(abs(nx) - 1), abs(abs(ny) - 1))
        }
        eErr /= CGFloat(pts.count); rErr /= CGFloat(pts.count)
        // Un rectangle tracé à la main colle mieux au cadre qu'à l'ellipse (coins remplis).
        if rErr < 0.09 && rErr < eErr * 0.8 { return .rectangle(box) }
        if eErr < 0.16 { return .ellipse(box) }
        return .none
    }

    /// Simplification Ramer–Douglas–Peucker (réduit les points d'un tracé avant stockage).
    public static func simplify(_ pts: [CGPoint], epsilon: CGFloat = 0.8) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var maxD: CGFloat = 0, idx = 0
        for i in 1..<(pts.count - 1) {
            let d = pts[i].distance(toSegment: pts[0], pts[pts.count - 1])
            if d > maxD { maxD = d; idx = i }
        }
        if maxD <= epsilon { return [pts[0], pts[pts.count - 1]] }
        let a = simplify(Array(pts[...idx]), epsilon: epsilon)
        let b = simplify(Array(pts[idx...]), epsilon: epsilon)
        return a.dropLast() + b
    }
}
