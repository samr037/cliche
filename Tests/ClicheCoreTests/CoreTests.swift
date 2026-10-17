import CoreGraphics
import Foundation
import Testing
@testable import ClicheCore

/// Image de test : fond blanc, rectangle gris foncé en (20,10) de 40×20.
func sampleImage(width: Int = 100, height: Int = 50) -> PixelBuffer {
    var b = [UInt8](repeating: 255, count: width * height * 4)
    for y in 10..<30 { for x in 20..<60 {
        let i = (y * width + x) * 4
        b[i] = 40; b[i + 1] = 40; b[i + 2] = 40
    } }
    return PixelBuffer(width: width, height: height, bytes: b)
}

@Suite struct RulerTests {
    @Test func measuresBoxFromInside() {
        let e = Ruler.measure(sampleImage(), x: 30, y: 15)
        #expect(e.left == 10 && e.right == 29 && e.up == 5 && e.down == 14)
        #expect(e.width == 40 && e.height == 20)
        #expect(Ruler.box(sampleImage(), x: 30, y: 15) == CGRect(x: 20, y: 10, width: 40, height: 20))
    }
    @Test func measuresGapOutside() {
        let e = Ruler.measure(sampleImage(), x: 70, y: 20)
        #expect(e.left == 10)  // x 60…69 blancs, bord du rectangle en x=59
        #expect(e.right == 29)
    }
    @Test func labels() {
        #expect(Ruler.label(from: .zero, to: CGPoint(x: 120, y: 0)) == "120 px")
        #expect(Ruler.label(from: .zero, to: CGPoint(x: 30, y: 40)) == "30 × 40 px · 50")
        #expect(Ruler.label(from: .zero, to: CGPoint(x: 0, y: 200), scale: 2, unit: "pt") == "100 pt")
    }
    @Test func snapsToEdge() {
        let p = Ruler.snap(sampleImage(), point: CGPoint(x: 23, y: 15))
        #expect(p == CGPoint(x: 20, y: 15))
    }
}

@Suite struct ColorTests {
    @Test func formats() {
        let c = RGBA(1, 0.5, 0)
        #expect(ColorFormat.hex.string(c) == "#FF8000")
        #expect(ColorFormat.rgb.string(c) == "rgb(255, 128, 0)")
        #expect(ColorFormat.hsl.string(c) == "hsl(30, 100%, 50%)")
    }
    @Test func oklchOfWhiteAndRed() {
        let w = ColorMath.oklch(.white)
        #expect(abs(w.l - 1) < 1e-3 && w.c < 1e-3)
        let r = ColorMath.oklch(RGBA(1, 0, 0))
        #expect(abs(r.l - 0.628) < 2e-3 && abs(r.c - 0.2577) < 2e-3 && abs(r.h - 29.23) < 0.1)
    }
    @Test func contrast() {
        #expect(abs(ColorMath.contrastRatio(.black, .white) - 21) < 1e-6)
        #expect(ColorMath.wcagGrade(4.6) == "AA")
        #expect(ColorMath.parseHex("#f80") == RGBA(1, 0x88 / 255.0, 0))
    }
}

@Suite struct ShapeTests {
    @Test func line() {
        let pts = (0...20).map { CGPoint(x: CGFloat($0) * 10, y: CGFloat($0 % 2)) }
        guard case .line = ShapeRecognizer.recognize(pts) else { Issue.record("not a line"); return }
    }
    @Test func ellipse() {
        let pts = (0...60).map { i -> CGPoint in
            let t = Double(i) / 60 * 2 * .pi
            return CGPoint(x: 100 + 80 * cos(t), y: 100 + 40 * sin(t))
        }
        #expect(ShapeRecognizer.recognize(pts) == .ellipse(CGRect(x: 20, y: 60, width: 160, height: 80)))
    }
    @Test func rectangle() {
        var pts: [CGPoint] = []
        for x in stride(from: 0, through: 100, by: 5) { pts.append(CGPoint(x: x, y: 0)) }
        for y in stride(from: 0, through: 60, by: 5) { pts.append(CGPoint(x: 100, y: y)) }
        for x in stride(from: 100, through: 0, by: -5) { pts.append(CGPoint(x: x, y: 60)) }
        for y in stride(from: 60, through: 2, by: -5) { pts.append(CGPoint(x: 0, y: y)) }
        guard case .rectangle = ShapeRecognizer.recognize(pts) else { Issue.record("not a rect"); return }
    }
    @Test func scribbleStaysFree() {
        let pts = (0...40).map { CGPoint(x: CGFloat($0) * 5, y: CGFloat(($0 * 37) % 50)) }
        #expect(ShapeRecognizer.recognize(pts) == .none)
    }
}

/// Page synthétique de 600 lignes « texte », avec barre fixe en haut (20) et en bas (10).
func page(_ offset: Int, width: Int = 40, height: Int = 120) -> PixelBuffer {
    var b = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        let contentY = y + offset
        for x in 0..<width {
            let i = (y * width + x) * 4
            var v: UInt8
            if y < 20 { v = 200 }                 // en-tête fixe
            else if y >= height - 10 { v = 90 }   // pied fixe
            else { v = UInt8(truncatingIfNeeded: (contentY &* 7919 &+ x &* (contentY % 13 + 1)) % 251) }
            b[i] = v; b[i + 1] = v &+ 3; b[i + 2] = v &+ 7; b[i + 3] = 255
        }
    }
    return PixelBuffer(width: width, height: height, bytes: b)
}

@Suite struct StitchTests {
    @Test func stitchesDownWithFixedBars() {
        let s = ScrollStitcher()
        #expect(s.add(page(0)) == .first)
        #expect(s.add(page(0)) == .noShift)
        #expect(s.add(page(35)) == .appended(rows: 35))
        #expect(s.add(page(70)) == .appended(rows: 35))
        #expect(s.add(page(100)) == .appended(rows: 30))
        // 20 en-tête + 90 zone + 100 lignes ajoutées + 10 pied
        #expect(s.height == 220)
        let img = s.makeImage()
        #expect(img?.height == 220)
        // La ligne 20+90+99 de l'assemblage correspond à la dernière ligne de contenu de la dernière image.
        let px = PixelBuffer(img!)!
        let last = page(100)
        #expect(px.packed(5, 209) == last.packed(5, 109))
        #expect(px.packed(5, 215) == last.packed(5, 115))
    }
    @Test func rejectsJump() {
        let s = ScrollStitcher()
        s.add(page(0))
        #expect(s.add(page(500)) == .noMatch)
    }
    @Test func respectsLimit() {
        let s = ScrollStitcher(maxHeight: 150)
        s.add(page(0))
        #expect(s.add(page(30)) == .appended(rows: 30))
        #expect(s.add(page(60)) == .limitReached)
        #expect(s.height == 150)
    }
    @Test func stitchesUp() {
        let s = ScrollStitcher(direction: .up)
        s.add(page(200))
        #expect(s.add(page(160)) == .appended(rows: 40))
        let px = PixelBuffer(s.makeImage()!)!
        #expect(px.packed(3, 20) == page(160).packed(3, 20))
    }
}

@Suite struct RenderTests {
    @Test func rendersAllKindsWithCrop() throws {
        let base = try #require(sampleImage(width: 300, height: 200).makeImage())
        var doc = DocumentState()
        doc.annotations = [
            Annotation(kind: .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 150, y: 90), style: .classic)),
            Annotation(kind: .rectangle(CGRect(x: 20, y: 20, width: 80, height: 40), fill: .stroke, cornerRadius: 6)),
            Annotation(kind: .oval(CGRect(x: 120, y: 20, width: 80, height: 40), fill: .strokeOnWhite)),
            Annotation(kind: .text(origin: CGPoint(x: 30, y: 120), string: "Bonjour\nCliché", style: .box)),
            Annotation(kind: .freehand(points: [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 9), CGPoint(x: 20, y: 3)])),
            Annotation(kind: .highlighter(CGRect(x: 0, y: 150, width: 100, height: 20)), color: .yellow),
            Annotation(kind: .conceal(CGRect(x: 15, y: 5, width: 50, height: 30), style: .blur)),
            Annotation(kind: .conceal(CGRect(x: 200, y: 100, width: 50, height: 30), style: .pixelate)),
            Annotation(kind: .conceal(CGRect(x: 100, y: 160, width: 30, height: 20), style: .erase)),
            Annotation(kind: .spotlight(CGRect(x: 10, y: 10, width: 60, height: 40), oval: false)),
            Annotation(kind: .magnifier(center: CGPoint(x: 25, y: 15), radius: 30, zoom: 3)),
            Annotation(kind: .counter(center: CGPoint(x: 250, y: 30), number: 1)),
            Annotation(kind: .ruler(from: CGPoint(x: 20, y: 180), to: CGPoint(x: 120, y: 180))),
        ]
        doc.crop = CGRect(x: 5, y: 5, width: 250, height: 180)
        let out = try #require(doc.render(base: base))
        #expect(out.width == 250 && out.height == 180)
        // Le projecteur assombrit l'extérieur : un pixel blanc hors zone devient gris.
        let px = try #require(PixelBuffer(out))
        let c = px.rgba(240, 170)
        #expect(c.r < 0.6)
    }
    @Test func eraseUsesEdgeColor() {
        let img = sampleImage().makeImage()!
        #expect(Renderer.dominantEdgeColor(img, rect: CGRect(x: 25, y: 15, width: 10, height: 5)).r < 0.2)
        #expect(Renderer.dominantEdgeColor(img, rect: CGRect(x: 70, y: 35, width: 10, height: 5)).r > 0.9)
    }
    @Test func backdropGrows() throws {
        let img = try #require(sampleImage().makeImage())
        let out = try #require(Backdrop(padding: 0.1).apply(to: img))
        #expect(out.width == 120 && out.height == 70)
        let sq = try #require(Backdrop(fill: .solid(.white), padding: 0.1, aspect: 1).apply(to: img))
        #expect(sq.width == sq.height)
        let mesh = try #require(Backdrop(fill: Backdrop.presets[4]).apply(to: img))
        #expect(mesh.width > img.width)
    }
    @Test func hitTesting() {
        let a = Annotation(kind: .rectangle(CGRect(x: 0, y: 0, width: 100, height: 100), fill: .stroke, cornerRadius: 0))
        #expect(a.hitTest(CGPoint(x: 1, y: 50)))
        #expect(!a.hitTest(CGPoint(x: 50, y: 50)))
        let l = Annotation(kind: .line(from: .zero, to: CGPoint(x: 100, y: 0), style: .solid))
        #expect(l.hitTest(CGPoint(x: 50, y: 4)) && !l.hitTest(CGPoint(x: 50, y: 20)))
    }
}

@Suite struct HistoryTests {
    @Test func undoRedo() {
        var h = History(DocumentState())
        h.change { $0.annotations.append(Annotation(kind: .counter(center: .zero, number: 1))) }
        h.change { $0.annotations.append(Annotation(kind: .counter(center: .zero, number: 2))) }
        #expect(h.current.nextCounter == 3)
        h.undo()
        #expect(h.current.annotations.count == 1 && h.canRedo)
        h.redo()
        #expect(h.current.annotations.count == 2)
        let start = h.current
        h.replace(DocumentState())
        h.commit(from: start)
        h.undo()
        #expect(h.current.annotations.count == 2)
    }
    @Test func encodesFormats() throws {
        let img = try #require(sampleImage().makeImage())
        #expect(Exporter.encode(img, format: .png)?.1 == .png)
        #expect(Exporter.encode(img, format: .auto)?.1 == .png)
        #expect(Exporter.downscale(img, by: 2)?.width == 50)
        #expect(Exporter.gif([img, img]) != nil)
    }
}
