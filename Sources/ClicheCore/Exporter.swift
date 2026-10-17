import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum SaveFormat: String, CaseIterable, Codable, Sendable {
    case png = "PNG"
    case jpeg = "JPEG"
    case auto = "Auto"   // PNG, sauf photo lourde → JPEG
}

public enum Exporter {
    public static func encode(_ img: CGImage, as type: UTType, quality: Double = 0.9, dpi: Double = 72) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        if type == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Choix du format « Auto » : PNG pour les interfaces (peu de couleurs), JPEG si le PNG est
    /// nettement plus gros qu'un JPEG de bonne qualité (photo, vidéo, dégradés).
    public static func encodeAuto(_ img: CGImage, dpi: Double = 72) -> (Data, UTType)? {
        guard let png = encode(img, as: .png, dpi: dpi) else { return nil }
        guard png.count > 1_500_000, let jpg = encode(img, as: .jpeg, quality: 0.88, dpi: dpi) else { return (png, .png) }
        return jpg.count * 3 < png.count ? (jpg, .jpeg) : (png, .png)
    }

    public static func encode(_ img: CGImage, format: SaveFormat, dpi: Double = 72) -> (Data, UTType)? {
        switch format {
        case .png: return encode(img, as: .png, dpi: dpi).map { ($0, .png) }
        case .jpeg: return encode(img, as: .jpeg, quality: 0.9, dpi: dpi).map { ($0, .jpeg) }
        case .auto: return encodeAuto(img, dpi: dpi)
        }
    }

    /// Réduit une capture Retina à 1× (option « Downscale to 1× when saving »).
    public static func downscale(_ img: CGImage, by factor: CGFloat) -> CGImage? {
        guard factor > 1 else { return img }
        let w = Int((CGFloat(img.width) / factor).rounded()), h = Int((CGFloat(img.height) / factor).rounded())
        guard let ctx = Renderer.makeContext(width: w, height: h) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Nom de fichier façon macOS/Shottr : « SCR-20261017-hmsx.png » remplacé par un horodatage lisible.
    public static func filename(date: Date = Date(), ext: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Cliché \(f.string(from: date)).\(ext)"
    }

    /// GIF animé à partir d'images (ex. superposition alternée avant/après).
    public static func gif(_ frames: [CGImage], delay: Double = 0.8) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames.count, nil) else { return nil }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for f in frames {
            CGImageDestinationAddImage(dest, f, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
