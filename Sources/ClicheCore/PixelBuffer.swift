import CoreGraphics
import Foundation

/// Copie RGBA 8 bits (sRGB, non prémultipliée pour les images opaques) d'une CGImage, pour lire des pixels vite.
public struct PixelBuffer: Sendable {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8]   // RGBA, ligne après ligne, origine en haut à gauche

    public init?(_ img: CGImage) {
        let width = img.width, height = img.height
        guard width > 0, height > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: width * height * 4)
        let ok = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        self.width = width; self.height = height
        bytes = buf
    }

    public init(width: Int, height: Int, bytes: [UInt8]) {
        precondition(bytes.count == width * height * 4)
        self.width = width; self.height = height; self.bytes = bytes
    }

    @inline(__always) public func index(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

    public func rgba(_ x: Int, _ y: Int) -> RGBA {
        let i = index(x, y)
        return RGBA(Double(bytes[i]) / 255, Double(bytes[i + 1]) / 255, Double(bytes[i + 2]) / 255, Double(bytes[i + 3]) / 255)
    }

    /// 0xRRGGBBAA
    @inline(__always) public func packed(_ x: Int, _ y: Int) -> UInt32 {
        let i = index(x, y)
        return UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16 | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3])
    }

    /// Plus grand écart de canal entre deux pixels (0…255).
    @inline(__always) public func diff(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Int {
        let i = index(x0, y0), j = index(x1, y1)
        return max(abs(Int(bytes[i]) - Int(bytes[j])),
                   abs(Int(bytes[i + 1]) - Int(bytes[j + 1])),
                   abs(Int(bytes[i + 2]) - Int(bytes[j + 2])))
    }

    /// Somme des écarts R+G+B entre deux pixels (0…765).
    @inline(__always) public func sumDiff(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Int {
        let i = index(x0, y0), j = index(x1, y1)
        return abs(Int(bytes[i]) - Int(bytes[j])) + abs(Int(bytes[i + 1]) - Int(bytes[j + 1]))
            + abs(Int(bytes[i + 2]) - Int(bytes[j + 2]))
    }

    /// Luminance 0…255 (Rec. 601, entière), utile pour les signatures de lignes.
    @inline(__always) public func luma(_ x: Int, _ y: Int) -> Int {
        let i = index(x, y)
        return (Int(bytes[i]) * 299 + Int(bytes[i + 1]) * 587 + Int(bytes[i + 2]) * 114) / 1000
    }

    public func makeImage() -> CGImage? {
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
