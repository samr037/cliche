import Foundation

/// Formats de couleur proposés par la pipette (même liste que Shottr : HEX, RGB, HSL, OKLCH…).
public enum ColorFormat: String, CaseIterable, Codable, Sendable {
    case hex = "HEX"
    case rgb = "RGB"
    case hsl = "HSL"
    case hsb = "HSB"
    case oklch = "OKLCH"
    case swiftUI = "SwiftUI"
    case nsColor = "NSColor"

    public func string(_ c: RGBA) -> String {
        func i(_ v: Double) -> Int { Int((v * 255).rounded()) }
        func f(_ v: Double, _ d: Int = 3) -> String { String(format: "%.\(d)f", v) }
        switch self {
        case .hex: return String(format: "#%02X%02X%02X", i(c.r), i(c.g), i(c.b))
        case .rgb: return "rgb(\(i(c.r)), \(i(c.g)), \(i(c.b)))"
        case .hsl:
            let (h, s, l) = ColorMath.hsl(c)
            return "hsl(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
        case .hsb:
            let (h, s, v) = ColorMath.hsb(c)
            return "hsb(\(Int(h.rounded())), \(Int((s * 100).rounded()))%, \(Int((v * 100).rounded()))%)"
        case .oklch:
            let (l, ch, h) = ColorMath.oklch(c)
            return "oklch(\(f(l * 100, 1))% \(f(ch, 3)) \(f(h, 1)))"
        case .swiftUI: return "Color(red: \(f(c.r)), green: \(f(c.g)), blue: \(f(c.b)))"
        case .nsColor: return "NSColor(srgbRed: \(f(c.r)), green: \(f(c.g)), blue: \(f(c.b)), alpha: 1)"
        }
    }
}

public enum ColorMath {
    public static func hsl(_ c: RGBA) -> (h: Double, s: Double, l: Double) {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        let l = (mx + mn) / 2
        guard mx != mn else { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        return (hue(c, mx, d), s, l)
    }

    public static func hsb(_ c: RGBA) -> (h: Double, s: Double, b: Double) {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        let d = mx - mn
        return (d == 0 ? 0 : hue(c, mx, d), mx == 0 ? 0 : d / mx, mx)
    }

    static func hue(_ c: RGBA, _ mx: Double, _ d: Double) -> Double {
        var h: Double
        if mx == c.r { h = (c.g - c.b) / d + (c.g < c.b ? 6 : 0) }
        else if mx == c.g { h = (c.b - c.r) / d + 2 }
        else { h = (c.r - c.g) / d + 4 }
        h *= 60
        return h
    }

    /// sRGB → OKLab → OKLCH (Björn Ottosson, 2020). L 0…1, C ≈ 0…0.4, h en degrés.
    public static func oklch(_ c: RGBA) -> (l: Double, c: Double, h: Double) {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = lin(c.r), g = lin(c.g), b = lin(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let C = (A * A + B * B).squareRoot()
        var h = atan2(B, A) * 180 / .pi
        if h < 0 { h += 360 }
        return (L, C, C < 1e-4 ? 0 : h)
    }

    /// Rapport de contraste WCAG 2.x (1…21).
    public static func contrastRatio(_ a: RGBA, _ b: RGBA) -> Double {
        let la = a.relativeLuminance, lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Verdict WCAG pour du texte normal : AAA ≥ 7, AA ≥ 4.5, AA grand texte ≥ 3.
    public static func wcagGrade(_ ratio: Double) -> String {
        switch ratio {
        case 7...: return "AAA"
        case 4.5...: return "AA"
        case 3...: return "AA Large"
        default: return "Fail"
        }
    }

    /// Lecture d'un code hexadécimal (#RGB, #RRGGBB, #RRGGBBAA).
    public static func parseHex(_ s: String) -> RGBA? {
        var h = s.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        if h.count == 6 {
            return RGBA(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
        }
        return RGBA(Double((v >> 24) & 0xFF) / 255, Double((v >> 16) & 0xFF) / 255,
                    Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}
