import AppKit
import ClicheCore

/// Réglages persistants (UserDefaults). Noms de clés repris de Shottr quand l'équivalent existe.
enum AfterCapture: String, CaseIterable {
    case preview   // vignette en bas à droite
    case editor    // ouvre directement l'éditeur
    case nothing
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    init() {
        d.register(defaults: [
            "afterGrabShow": AfterCapture.preview.rawValue,
            "afterGrabCopy": true,
            "afterGrabSave": false,
            "saveFormat": SaveFormat.png.rawValue,
            "downscaleOnSave": false,
            "colorFormat": ColorFormat.hex.rawValue,
            "defaultColor": "#F03333",
            "strokeWidth": 4.0,
            "captureCursor": false,
            "windowShadow": true,
            "scrollingMax": 20_000,
            "scrollingSpeed": 3,
            "scrollingReverseAutoscroll": false,
            "ocrRemoveBreaks": false,
            "copyOnEsc": true,
            "thumbnailSeconds": 6.0,
        ])
    }

    var afterCapture: AfterCapture {
        get { AfterCapture(rawValue: d.string(forKey: "afterGrabShow") ?? "") ?? .preview }
        set { d.set(newValue.rawValue, forKey: "afterGrabShow") }
    }
    var copyAfterCapture: Bool { get { d.bool(forKey: "afterGrabCopy") } set { d.set(newValue, forKey: "afterGrabCopy") } }
    var saveAfterCapture: Bool { get { d.bool(forKey: "afterGrabSave") } set { d.set(newValue, forKey: "afterGrabSave") } }
    var saveFormat: SaveFormat {
        get { SaveFormat(rawValue: d.string(forKey: "saveFormat") ?? "") ?? .png }
        set { d.set(newValue.rawValue, forKey: "saveFormat") }
    }
    var downscaleOnSave: Bool { get { d.bool(forKey: "downscaleOnSave") } set { d.set(newValue, forKey: "downscaleOnSave") } }
    var colorFormat: ColorFormat {
        get { ColorFormat(rawValue: d.string(forKey: "colorFormat") ?? "") ?? .hex }
        set { d.set(newValue.rawValue, forKey: "colorFormat") }
    }
    var defaultColor: RGBA {
        get { ColorMath.parseHex(d.string(forKey: "defaultColor") ?? "") ?? .red }
        set { d.set(ColorFormat.hex.string(newValue), forKey: "defaultColor") }
    }
    var strokeWidth: CGFloat { get { CGFloat(d.double(forKey: "strokeWidth")) } set { d.set(Double(newValue), forKey: "strokeWidth") } }
    var captureCursor: Bool { get { d.bool(forKey: "captureCursor") } set { d.set(newValue, forKey: "captureCursor") } }
    var windowShadow: Bool { get { d.bool(forKey: "windowShadow") } set { d.set(newValue, forKey: "windowShadow") } }
    var scrollingMax: Int { get { d.integer(forKey: "scrollingMax") } set { d.set(newValue, forKey: "scrollingMax") } }
    var scrollingSpeed: Int { get { d.integer(forKey: "scrollingSpeed") } set { d.set(newValue, forKey: "scrollingSpeed") } }
    var reverseScroll: Bool { get { d.bool(forKey: "scrollingReverseAutoscroll") } set { d.set(newValue, forKey: "scrollingReverseAutoscroll") } }
    var ocrRemoveBreaks: Bool { get { d.bool(forKey: "ocrRemoveBreaks") } set { d.set(newValue, forKey: "ocrRemoveBreaks") } }
    var copyOnEsc: Bool { get { d.bool(forKey: "copyOnEsc") } set { d.set(newValue, forKey: "copyOnEsc") } }
    var thumbnailSeconds: Double { get { d.double(forKey: "thumbnailSeconds") } set { d.set(newValue, forKey: "thumbnailSeconds") } }

    /// Dossier d'enregistrement : choix de l'utilisateur, sinon celui de capture d'écran macOS, sinon le Bureau.
    var saveFolder: URL {
        get {
            if let p = d.string(forKey: "defaultFolder") { return URL(fileURLWithPath: p) }
            if let sys = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
                return URL(fileURLWithPath: (sys as NSString).expandingTildeInPath)
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        }
        set { d.set(newValue.path, forKey: "defaultFolder") }
    }

    /// Dernière zone capturée (pour « Répéter la capture de zone »), en coordonnées écran globales.
    var lastArea: CGRect? {
        get { d.string(forKey: "lastArea").map { NSRectFromString($0) } }
        set { d.set(newValue.map { NSStringFromRect($0) }, forKey: "lastArea") }
    }
}
