// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Cliche",
    platforms: [.macOS(.v14)],
    targets: [
        // Logique pure (modèle d'annotations, rendu CoreGraphics, couleurs, règle, couture, formes) : testable sans AppKit.
        .target(name: "ClicheCore"),
        // App menubar : raccourcis, capture ScreenCaptureKit, sélection de zone, éditeur, vignette, épingles, OCR.
        .executableTarget(name: "Cliche", dependencies: ["ClicheCore"]),
        .testTarget(name: "ClicheCoreTests", dependencies: ["ClicheCore"]),
    ]
)
