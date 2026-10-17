import CoreGraphics
import Foundation

/// Assemble des captures successives d'une même zone pendant un défilement vertical.
///
/// Chaque nouvelle image est comparée à la précédente ligne par ligne (empreinte de chaque ligne) :
/// on retire d'abord les bandes fixes en haut et en bas (barre d'outils, pied de page collant),
/// puis on cherche le décalage vertical qui fait coïncider le plus de lignes de la zone qui défile.
/// Seules les lignes nouvelles sont ajoutées. Fonctionne vers le bas comme vers le haut.
public final class ScrollStitcher {
    public enum Direction: Sendable { case down, up }

    public enum Step: Equatable, Sendable {
        case first
        case appended(rows: Int)   // nouvelles lignes ajoutées
        case noShift               // rien n'a bougé (fin de page ou défilement pas encore rendu)
        case noMatch               // pas de recouvrement fiable (défilement trop rapide)
        case limitReached
    }

    public let direction: Direction
    public let maxHeight: Int
    public private(set) var width = 0
    private var frameHeight = 0
    private var header = 0, footer = 0
    private var headerRows: [[UInt8]] = []
    private var footerRows: [[UInt8]] = []
    /// Lignes de la zone qui défile, dans l'ordre de la page.
    private var body: [[UInt8]] = []
    private var last: (rows: [[UInt8]], hashes: [UInt64])?

    /// Recouvrement minimal (lignes) pour accepter un décalage.
    public var minOverlap = 24
    /// Part minimale de lignes « informatives » identiques dans le recouvrement.
    public var minMatchRatio = 0.97

    public init(direction: Direction = .down, maxHeight: Int = 30_000) {
        self.direction = direction
        self.maxHeight = maxHeight
    }

    public var height: Int { header + body.count + footer }

    @discardableResult
    public func add(_ px: PixelBuffer) -> Step {
        let rows = (0..<px.height).map { y in Array(px.bytes[(y * px.width * 4)..<((y + 1) * px.width * 4)]) }
        let hashes = rows.map(Self.hash)
        guard let prev = last else {
            width = px.width; frameHeight = px.height
            body = rows
            last = (rows, hashes)
            return .first
        }
        guard px.width == width, px.height == frameHeight else { return .noMatch }
        if hashes == prev.hashes { return .noShift }

        // Bandes fixes : lignes identiques à la même position en haut et en bas.
        // On les fige au premier mouvement ; ensuite on garde ces valeurs.
        if headerRows.isEmpty && footerRows.isEmpty && header == 0 && footer == 0 {
            var h = 0
            while h < frameHeight / 3, hashes[h] == prev.hashes[h] { h += 1 }
            var f = 0
            while f < frameHeight / 3, hashes[frameHeight - 1 - f] == prev.hashes[frameHeight - 1 - f] { f += 1 }
            header = h; footer = f
            headerRows = Array(prev.rows[0..<h])
            footerRows = Array(rows[(frameHeight - f)...])
            body = Array(body[h..<(body.count - f)])
        }
        let lo = header, hi = frameHeight - footer
        let a = Array(prev.hashes[lo..<hi]), b = Array(hashes[lo..<hi])
        guard let shift = Self.bestShift(a, b, direction: direction, minOverlap: minOverlap, minRatio: minMatchRatio) else {
            return .noMatch
        }
        last = (rows, hashes)
        if !footerRows.isEmpty { footerRows = Array(rows[(frameHeight - footer)...]) }
        let scroll = Array(rows[lo..<hi])
        var fresh = direction == .down ? Array(scroll[(scroll.count - shift)...]) : Array(scroll[0..<shift])
        let room = maxHeight - height
        if room <= 0 { return .limitReached }
        if fresh.count > room { fresh = direction == .down ? Array(fresh.prefix(room)) : Array(fresh.suffix(room)) }
        if direction == .down { body.append(contentsOf: fresh) } else { body.insert(contentsOf: fresh, at: 0) }
        return fresh.count < shift ? .limitReached : .appended(rows: fresh.count)
    }

    /// Décalage s > 0 tel que, vers le bas, `a[s + i] == b[i]` (le contenu remonte de s lignes).
    /// Les lignes unies (toutes de la même couleur) ne comptent pas : elles collent partout.
    static func bestShift(_ a: [UInt64], _ b: [UInt64], direction: Direction, minOverlap: Int, minRatio: Double) -> Int? {
        let n = a.count
        guard n > minOverlap else { return nil }
        var best: (score: Double, shift: Int)? = nil
        for s in 1...(n - minOverlap) {
            var match = 0, informative = 0
            for i in 0..<(n - s) {
                let (x, y) = direction == .down ? (a[s + i], b[i]) : (a[i], b[s + i])
                if x & flatMask != 0 && x == y { continue }
                informative += 1
                if x == y { match += 1 }
            }
            guard informative >= max(8, (n - s) / 8) else { continue }
            let ratio = Double(match) / Double(informative)
            guard ratio >= minRatio else { continue }
            // À taux égal, le plus grand recouvrement (petit décalage) gagne.
            let score = ratio + Double(informative) * 1e-7
            if best == nil || score > best!.score { best = (score, s) }
        }
        return best?.shift
    }

    // Empreinte FNV-1a de la ligne ; un bit marque les lignes unies.
    static let flatMask: UInt64 = 1 << 63

    static func hash(_ row: [UInt8]) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        var uniform = true
        let r0 = row.count >= 4 ? (row[0], row[1], row[2]) : (0, 0, 0)
        var i = 0
        while i + 3 < row.count {
            if uniform && (row[i], row[i + 1], row[i + 2]) != r0 { uniform = false }
            h = (h ^ UInt64(row[i])) &* 0x100000001b3
            h = (h ^ UInt64(row[i + 1])) &* 0x100000001b3
            h = (h ^ UInt64(row[i + 2])) &* 0x100000001b3
            i += 4
        }
        return uniform ? (h | flatMask) : (h & ~flatMask)
    }

    public func makeImage() -> CGImage? {
        guard width > 0 else { return nil }
        let rows = headerRows + body + footerRows
        var bytes = [UInt8](); bytes.reserveCapacity(rows.count * width * 4)
        for r in rows { bytes.append(contentsOf: r) }
        return PixelBuffer(width: width, height: rows.count, bytes: bytes).makeImage()
    }
}
