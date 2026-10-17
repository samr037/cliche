import CoreGraphics
import Foundation

/// État éditable d'une capture : annotations, recadrage, fond. L'image de base ne change pas
/// (sauf « Rasteriser » et « Ajouter une capture »), ce qui garde chaque objet modifiable.
public struct DocumentState: Equatable, Sendable {
    public var annotations: [Annotation] = []
    public var crop: CGRect? = nil
    public var backdrop: Backdrop? = nil
    public init() {}
}

/// Historique annuler/rétablir par instantanés (les états sont petits : pas de pixels dedans).
public struct History<State: Equatable>: Sendable where State: Sendable {
    public private(set) var current: State
    private var undoStack: [State] = []
    private var redoStack: [State] = []
    public var limit = 200

    public init(_ initial: State) { current = initial }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Applique une modification ; ignorée si l'état ne change pas.
    public mutating func change(_ f: (inout State) -> Void) {
        var next = current
        f(&next)
        guard next != current else { return }
        undoStack.append(current)
        if undoStack.count > limit { undoStack.removeFirst() }
        redoStack.removeAll()
        current = next
    }

    /// Remplace l'état sans créer d'étape (pendant un glisser ; l'étape est posée au début du geste).
    public mutating func replace(_ s: State) { current = s }

    /// Pose une étape à partir d'un état de départ (fin d'un geste commencé avec `replace`).
    public mutating func commit(from start: State) {
        guard start != current else { return }
        undoStack.append(start)
        if undoStack.count > limit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    public mutating func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(current); current = s
    }

    public mutating func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(current); current = s
    }
}

public extension DocumentState {
    /// Prochain numéro de compteur (suit le plus grand déjà posé).
    var nextCounter: Int {
        annotations.reduce(0) { m, a in
            if case let .counter(_, n) = a.kind { return max(m, n) }
            return m
        } + 1
    }

    /// Objet le plus haut sous le point.
    func topAnnotation(at p: CGPoint, tolerance: CGFloat = 6) -> Annotation? {
        annotations.last { $0.hitTest(p, tolerance: tolerance) }
    }

    /// Image finale : base + annotations, recadrage, puis fond décoratif.
    func render(base: CGImage) -> CGImage? {
        guard let img = Renderer.render(base: base, annotations: annotations, crop: crop) else { return nil }
        return backdrop?.apply(to: img) ?? img
    }
}
