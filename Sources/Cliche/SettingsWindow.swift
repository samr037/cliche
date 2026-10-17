import AppKit
import ClicheCore
import ServiceManagement
import SwiftUI

/// Réglages (SwiftUI). État observable maison : les macros SwiftUI ne sont pas disponibles sans Xcode.
final class SettingsModel: ObservableObject {
    enum Pane: String, CaseIterable, Identifiable {
        case general, capture, editor, scrolling, shortcuts, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return String(localized: "Général")
            case .capture: return String(localized: "Capture")
            case .editor: return String(localized: "Éditeur")
            case .scrolling: return String(localized: "Défilement")
            case .shortcuts: return String(localized: "Raccourcis")
            case .about: return String(localized: "À propos")
            }
        }
        var symbol: String {
            switch self {
            case .general: return "gearshape.fill"
            case .capture: return "camera.viewfinder"
            case .editor: return "pencil.tip.crop.circle"
            case .scrolling: return "arrow.up.and.down.text.horizontal"
            case .shortcuts: return "command"
            case .about: return "info.circle.fill"
            }
        }
        var tint: Color {
            switch self {
            case .general: return Color(white: 0.55)
            case .capture: return Color(red: 0.94, green: 0.26, blue: 0.42)
            case .editor: return Color(red: 1.0, green: 0.55, blue: 0.2)
            case .scrolling: return Color(red: 0.2, green: 0.6, blue: 0.95)
            case .shortcuts: return Color(red: 0.45, green: 0.38, blue: 0.9)
            case .about: return Color(red: 0.72, green: 0.14, blue: 0.48)
            }
        }
    }

    private let s = Settings.shared
    @Published var pane: Pane = .general
    @Published var afterCapture: AfterCapture { didSet { s.afterCapture = afterCapture } }
    @Published var copyAfter: Bool { didSet { s.copyAfterCapture = copyAfter } }
    @Published var saveAfter: Bool { didSet { s.saveAfterCapture = saveAfter } }
    @Published var format: SaveFormat { didSet { s.saveFormat = format } }
    @Published var downscale: Bool { didSet { s.downscaleOnSave = downscale } }
    @Published var colorFormat: ColorFormat { didSet { s.colorFormat = colorFormat } }
    @Published var cursor: Bool { didSet { s.captureCursor = cursor } }
    @Published var shadow: Bool { didSet { s.windowShadow = shadow } }
    @Published var scrollMax: Double { didSet { s.scrollingMax = Int(scrollMax) } }
    @Published var scrollSpeed: Double { didSet { s.scrollingSpeed = Int(scrollSpeed) } }
    @Published var reverse: Bool { didSet { s.reverseScroll = reverse } }
    @Published var ocrBreaks: Bool { didSet { s.ocrRemoveBreaks = ocrBreaks } }
    @Published var copyOnEsc: Bool { didSet { s.copyOnEsc = copyOnEsc } }
    @Published var thumbSeconds: Double { didSet { s.thumbnailSeconds = thumbSeconds } }
    @Published var color: Color { didSet { s.defaultColor = RGBA(NSColor(color)) } }
    @Published var width: Double { didSet { s.strokeWidth = CGFloat(width) } }
    @Published var folder: String
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do { launchAtLogin ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() } catch {
                Toast.show(error.localizedDescription)
            }
        }
    }
    @Published var deepLinks = UserDefaults.standard.bool(forKey: "allowDeepLinks") {
        didSet { UserDefaults.standard.set(deepLinks, forKey: "allowDeepLinks") }
    }
    @Published var recording: Action?
    @Published var screenAccess = CGPreflightScreenCaptureAccess()
    @Published var axAccess = AXIsProcessTrusted()
    @Published private(set) var shortcutsVersion = 0
    private var monitor: Any?

    init() {
        afterCapture = s.afterCapture; copyAfter = s.copyAfterCapture; saveAfter = s.saveAfterCapture
        format = s.saveFormat; downscale = s.downscaleOnSave; colorFormat = s.colorFormat
        cursor = s.captureCursor; shadow = s.windowShadow
        scrollMax = Double(s.scrollingMax); scrollSpeed = Double(s.scrollingSpeed); reverse = s.reverseScroll
        ocrBreaks = s.ocrRemoveBreaks; copyOnEsc = s.copyOnEsc; thumbSeconds = s.thumbnailSeconds
        color = Color(nsColor: s.defaultColor.nsColor); width = Double(s.strokeWidth)
        folder = s.saveFolder.path
        launchAtLogin = SMAppService.mainApp.status == .enabled
        Hotkeys.shared.onChange = { [weak self] in self?.shortcutsVersion += 1 }
    }

    func refreshPermissions() {
        screenAccess = CGPreflightScreenCaptureAccess()
        axAccess = AXIsProcessTrusted()
    }

    func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.directoryURL = s.saveFolder
        if p.runModal() == .OK, let u = p.url { s.saveFolder = u; folder = u.path }
    }

    // Enregistreur de raccourci : les raccourcis globaux sont suspendus le temps de taper la combinaison.
    func record(_ a: Action) {
        stopRecording()
        recording = a
        Hotkeys.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            switch Int(e.keyCode) {
            case 53: self.stopRecording()                                  // Échap : annule
            case 51, 117: a.shortcut = nil; self.stopRecording()           // ⌫ : efface
            default:
                guard let sc = Shortcut(event: e) else { NSSound.beep(); return nil }
                // Un raccourci déjà attribué à une autre action lui est retiré.
                for other in Action.allCases where other != a && other.shortcut == sc { other.shortcut = nil }
                a.shortcut = sc
                self.stopRecording()
            }
            return nil
        }
    }

    func stopRecording() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = nil
        Hotkeys.shared.reload()
    }

    func resetShortcuts() {
        for a in Action.allCases { UserDefaults.standard.removeObject(forKey: "shortcut.\(a.rawValue)") }
        Hotkeys.shared.reload()
    }
}

// MARK: - Vue

struct SettingsView: View {
    @ObservedObject var m: SettingsModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(m.pane.title).font(.system(size: 22, weight: .bold)).padding(.top, 4)
                    content
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 720, height: 520)
        .onAppear { m.refreshPermissions() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Cliché").font(.system(size: 15, weight: .semibold))
                    Text("v\(appVersion)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.top, 34).padding(.bottom, 14)
            ForEach(SettingsModel.Pane.allCases) { p in
                Button { m.pane = p } label: {
                    HStack(spacing: 10) {
                        Image(systemName: p.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.tint.gradient))
                        Text(p.title).font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(m.pane == p ? Color.accentColor.opacity(0.18) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: 210)
        .background(.regularMaterial)
    }

    @ViewBuilder private var content: some View {
        switch m.pane {
        case .general: general
        case .capture: capture
        case .editor: editor
        case .scrolling: scrolling
        case .shortcuts: shortcuts
        case .about: about
        }
    }

    // MARK: Volets

    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card("Après une capture") {
                Row("Afficher") {
                    Picker("", selection: $m.afterCapture) {
                        Text("Vignette").tag(AfterCapture.preview)
                        Text("Éditeur").tag(AfterCapture.editor)
                        Text("Rien").tag(AfterCapture.nothing)
                    }.pickerStyle(.segmented).frame(width: 240)
                }
                Divider()
                Toggle("Copier dans le presse-papiers", isOn: $m.copyAfter)
                Toggle("Enregistrer dans le dossier", isOn: $m.saveAfter)
                if m.afterCapture == .preview {
                    Divider()
                    Row("Vignette visible") {
                        Picker("", selection: $m.thumbSeconds) {
                            Text("4 s").tag(4.0); Text("6 s").tag(6.0); Text("10 s").tag(10.0); Text("Jusqu'au clic").tag(0.0)
                        }.frame(width: 160)
                    }
                }
            }
            Card("Enregistrement") {
                Row("Dossier") {
                    HStack {
                        Text(abbreviated(m.folder)).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("Choisir…") { m.chooseFolder() }
                    }
                }
                Divider()
                Row("Format") {
                    Picker("", selection: $m.format) {
                        ForEach(SaveFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 200)
                }
                Toggle("Réduire les captures Retina à 1×", isOn: $m.downscale)
            }
            Card("Système") {
                Toggle("Ouvrir Cliché à l'ouverture de session", isOn: $m.launchAtLogin)
                Divider()
                Permission(title: "Enregistrement de l'écran", detail: "Indispensable pour toute capture.", granted: m.screenAccess,
                           pane: "Privacy_ScreenCapture") { CGRequestScreenCaptureAccess(); m.refreshPermissions() }
                Permission(title: "Accessibilité", detail: "Seulement pour la capture défilante (molette simulée).", granted: m.axAccess,
                           pane: "Privacy_Accessibility") {
                    _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                    m.refreshPermissions()
                }
            }
        }
    }

    private var capture: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card("Image") {
                Toggle("Inclure le curseur", isOn: $m.cursor)
                Toggle("Garder l'ombre des fenêtres", isOn: $m.shadow)
            }
            Card("Texte et QR codes") {
                Toggle("Joindre les lignes reconnues (sans retours à la ligne)", isOn: $m.ocrBreaks)
                Text("La reconnaissance se fait sur le Mac avec Vision ; rien n'est envoyé en ligne.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card("Outils") {
                Row("Couleur par défaut") {
                    HStack(spacing: 8) {
                        ForEach(Self.swatches, id: \.self) { hex in
                            let c = Color(nsColor: (ColorMath.parseHex(hex) ?? .red).nsColor)
                            Circle().fill(c).frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                                .onTapGesture { m.color = c }
                        }
                        ColorPicker("", selection: $m.color, supportsOpacity: false).labelsHidden()
                    }
                }
                Divider()
                Row("Épaisseur") {
                    HStack {
                        Slider(value: $m.width, in: 2...12, step: 1).frame(width: 160)
                        Text("\(Int(m.width)) px").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Row("Format de couleur (pipette)") {
                    Picker("", selection: $m.colorFormat) {
                        ForEach(ColorFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.frame(width: 140)
                }
            }
            Card("Fermeture") {
                Toggle("Échap copie l'image avant de fermer l'éditeur", isOn: $m.copyOnEsc)
            }
            Card("Raccourcis de l'éditeur") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    ForEach(Tool.allCases, id: \.self) { t in
                        HStack(spacing: 8) {
                            Keycap(t.key.uppercased())
                            Image(systemName: t.symbol).frame(width: 16)
                            Text(t.title).font(.callout).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var scrolling: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card("Capture défilante") {
                Row("Hauteur maximale") {
                    HStack {
                        Slider(value: $m.scrollMax, in: 2_000...50_000, step: 1_000).frame(width: 180)
                        Text("\(Int(m.scrollMax)) px").monospacedDigit().frame(width: 70, alignment: .trailing)
                    }
                }
                Row("Vitesse") {
                    HStack {
                        Image(systemName: "tortoise").foregroundStyle(.secondary)
                        Slider(value: $m.scrollSpeed, in: 1...5, step: 1).frame(width: 150)
                        Image(systemName: "hare").foregroundStyle(.secondary)
                    }
                }
                Divider()
                Toggle("Inverser le sens (si un utilitaire inverse déjà la molette)", isOn: $m.reverse)
            }
            Text("Choisissez la zone qui défile : Cliché fait défiler la page, recolle les images et retire les barres fixes (en-tête, pied). Échap ou un clic arrête.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card("Raccourcis globaux") {
                ForEach(Array(Action.allCases.enumerated()), id: \.element) { i, a in
                    if i > 0 { Divider() }
                    HStack {
                        Image(systemName: a.symbol).frame(width: 20).foregroundStyle(.secondary)
                        Text(a.title)
                        Spacer()
                        if Hotkeys.shared.conflicts.contains(a) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .help("Ce raccourci est déjà utilisé par une autre app")
                        }
                        ShortcutButton(action: a, m: m)
                    }
                }
            }
            HStack {
                Text("Cliquez puis tapez une combinaison. ⌫ efface, Échap annule.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Rétablir les raccourcis par défaut") { m.resetShortcuts() }
            }
            Card("Schéma d'URL") {
                Toggle("Autoriser les liens cliche:// (apps et pages web)", isOn: $m.deepLinks)
                Text("cliche://grab/area · grab/fullscreen · grab/window · grab/scrolling · grab/area/repeat · ocr · load/clipboard")
                    .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Text("Pratique depuis Raccourcis, Raycast ou Alfred : open \"cliche://grab/area\"").font(.caption).foregroundStyle(.secondary)
            }
        }
        .id(m.shortcutsVersion)
    }

    private var about: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
            Text("Cliché").font(.system(size: 28, weight: .bold))
            Text("Captures d'écran open source pour macOS.\nCapturer, annoter, mesurer.").multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("Version \(appVersion) · Licence MIT").font(.callout)
            HStack {
                Link("Code source", destination: URL(string: "https://github.com/samr037/cliche")!)
                Text("·").foregroundStyle(.secondary)
                Link("Signaler un problème", destination: URL(string: "https://github.com/samr037/cliche/issues")!)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    static let swatches = ["#F03333", "#FF8A1F", "#FFD84D", "#2DBE6C", "#2F80ED", "#8E44EF", "#111111", "#FFFFFF"]
    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    private func abbreviated(_ p: String) -> String { (p as NSString).abbreviatingWithTildeInPath }
}

// MARK: - Composants

struct Card<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08)))
        }
    }
}

struct Row<Trailing: View>: View {
    let label: String
    let trailing: Trailing
    init(_ label: String, @ViewBuilder trailing: () -> Trailing) { self.label = label; self.trailing = trailing() }
    var body: some View { HStack { Text(label); Spacer(); trailing } }
}

struct Keycap: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold, design: .rounded))
            .frame(minWidth: 22, minHeight: 20).padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.2)))
    }
}

struct ShortcutButton: View {
    let action: Action
    @ObservedObject var m: SettingsModel
    var body: some View {
        let rec = m.recording == action
        Button { rec ? m.stopRecording() : m.record(action) } label: {
            Text(rec ? "Tapez le raccourci…" : (action.shortcut?.label ?? "Aucun"))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(rec ? Color.white : (action.shortcut == nil ? Color.secondary : Color.primary))
                .frame(minWidth: 120)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(rec ? Color.accentColor : Color(nsColor: .windowBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }
}

struct Permission: View {
    let title: String, detail: String, granted: Bool, pane: String
    let request: () -> Void
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Autoriser…") {
                    request()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
            }
        }
    }
}

enum SettingsWindow {
    static func make(model: SettingsModel = SettingsModel()) -> NSWindow {
        let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(m: model)))
        w.title = String(localized: "Réglages de Cliché")
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        return w
    }
}
