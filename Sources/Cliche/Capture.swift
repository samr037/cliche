import AppKit
import ScreenCaptureKit

/// Une capture : l'image en pixels et son facteur d'échelle (2 sur écran Retina).
struct Shot {
    var image: CGImage
    var scale: CGFloat
    var date = Date()
    /// Zone capturée en coordonnées écran globales (points, origine en bas à gauche), si connue.
    var screenRect: CGRect?
}

enum CaptureError: LocalizedError {
    case permission, noDisplay, failed(String)
    var errorDescription: String? {
        switch self {
        case .permission: return String(localized: "Cliché a besoin de l'autorisation « Enregistrement de l'écran ».")
        case .noDisplay: return String(localized: "Aucun écran trouvé.")
        case let .failed(m): return m
        }
    }
}

/// Captures via ScreenCaptureKit (SCScreenshotManager), comme Shottr pour le plein écran.
enum Capturer {
    static func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()
        return false
    }

    /// Écran sous la souris.
    static var activeScreen: NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    /// Capture complète d'un écran, sans les fenêtres de Cliché.
    static func captureScreen(_ screen: NSScreen) async throws -> Shot {
        guard ensurePermission() else { throw CaptureError.permission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let id = displayID(screen)
        guard let display = content.displays.first(where: { $0.displayID == id }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }
        let mine = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
        let cfg = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        cfg.width = Int(CGFloat(display.width) * scale)
        cfg.height = Int(CGFloat(display.height) * scale)
        cfg.showsCursor = Settings.shared.captureCursor
        cfg.captureResolution = .best
        cfg.colorSpaceName = CGColorSpace.sRGB
        let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        return Shot(image: img, scale: scale, screenRect: screen.frame)
    }

    /// Capture d'une fenêtre seule, fond transparent, avec ou sans ombre.
    static func captureWindow(_ window: SCWindow) async throws -> Shot {
        guard ensurePermission() else { throw CaptureError.permission }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let cfg = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        cfg.width = Int(filter.contentRect.width * scale)
        cfg.height = Int(filter.contentRect.height * scale)
        cfg.ignoreShadowsSingleWindow = !Settings.shared.windowShadow
        cfg.showsCursor = false
        cfg.captureResolution = .best
        cfg.colorSpaceName = CGColorSpace.sRGB
        let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        return Shot(image: img, scale: scale, screenRect: nil)
    }

    /// Fenêtres visibles des autres apps, de l'avant vers l'arrière, avec leur cadre (repère Quartz, origine haut-gauche).
    static func visibleWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let mine = Bundle.main.bundleIdentifier
        // Ordre de superposition : CGWindowList est trié de l'avant vers l'arrière.
        let order = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return content.windows
            .filter { $0.windowLayer == 0 && $0.frame.width > 40 && $0.frame.height > 40
                && $0.owningApplication?.bundleIdentifier != mine && $0.isOnScreen }
            .sorted { (rank[$0.windowID] ?? .max) < (rank[$1.windowID] ?? .max) }
    }

    /// Recadre une capture d'écran sur un rectangle en points écran globaux (origine bas-gauche).
    static func crop(_ shot: Shot, to rect: CGRect) -> Shot? {
        guard let sr = shot.screenRect else { return nil }
        let s = shot.scale
        let px = CGRect(x: (rect.minX - sr.minX) * s, y: (sr.maxY - rect.maxY) * s,
                        width: rect.width * s, height: rect.height * s).integral
        guard let img = shot.image.cropping(to: px) else { return nil }
        return Shot(image: img, scale: s, date: shot.date, screenRect: rect)
    }
}
