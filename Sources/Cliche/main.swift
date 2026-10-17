import AppKit
import ClicheCore
import ScreenCaptureKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var editors: [EditorWindowController] = []
    private var selector: AreaSelector?
    private var scrollCapture: ScrollCapture?
    private var settingsWindow: NSWindow?
    private var busy = false

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()
        buildStatusItem()
        Hotkeys.shared.register(.fullscreen) { [weak self] in self?.perform(.fullscreen) }
        Hotkeys.shared.register(.area) { [weak self] in self?.perform(.area) }
        Hotkeys.shared.register(.areaRepeat) { [weak self] in self?.perform(.areaRepeat) }
        Hotkeys.shared.register(.window) { [weak self] in self?.perform(.window) }
        Hotkeys.shared.register(.scrolling) { [weak self] in self?.perform(.scrolling) }
        Hotkeys.shared.register(.ocr) { [weak self] in self?.perform(.ocr) }
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        // Mode test : `Cliche --open <fichier>` ouvre l'éditeur sur une image.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 2 < args.count {
            Snapshots.run(out: URL(fileURLWithPath: args[i + 1]), sample: URL(fileURLWithPath: args[i + 2]))
            exit(0)
        }
        if let i = args.firstIndex(of: "--open"), i + 1 < args.count, let s = Output.imageFromFile(URL(fileURLWithPath: args[i + 1])) {
            openEditor(s)
        }
    }

    func application(_ app: NSApplication, open urls: [URL]) {
        for u in urls where u.isFileURL { if let s = Output.imageFromFile(u) { openEditor(s) } }
    }

    // MARK: Menus

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Cliché")
        let m = NSMenu()
        for a in Action.allCases {
            let it = NSMenuItem(title: a.title, action: #selector(menuAction(_:)), keyEquivalent: "")
            it.representedObject = a.rawValue
            it.target = self
            it.image = NSImage(systemSymbolName: a.symbol, accessibilityDescription: nil)
            m.addItem(it)
        }
        m.addItem(.separator())
        let open = NSMenuItem(title: String(localized: "Ouvrir une image…"), action: #selector(openFile), keyEquivalent: "")
        open.target = self
        m.addItem(open)
        let prefs = NSMenuItem(title: String(localized: "Réglages…"), action: #selector(showSettings), keyEquivalent: ",")
        prefs.target = self
        m.addItem(prefs)
        m.addItem(.separator())
        m.addItem(withTitle: String(localized: "Quitter Cliché"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        m.delegate = self
        statusItem.menu = m
    }

    /// Menu principal minimal : donne ⌘C / ⌘S / ⌘Z / zoom aux fenêtres d'éditeur.
    private func buildMainMenu() {
        let main = NSMenu()
        func sub(_ title: String, _ items: [(String, Selector, String, NSEvent.ModifierFlags)]) {
            let it = NSMenuItem(); let m = NSMenu(title: title)
            for (t, s, k, mods) in items {
                let x = NSMenuItem(title: t, action: s, keyEquivalent: k)
                x.keyEquivalentModifierMask = mods
                m.addItem(x)
            }
            it.submenu = m; main.addItem(it)
        }
        sub("Cliché", [(String(localized: "Réglages…"), #selector(showSettings), ",", .command),
                       (String(localized: "Quitter"), #selector(NSApplication.terminate(_:)), "q", .command)])
        sub(String(localized: "Fichier"), [(String(localized: "Enregistrer"), #selector(EditorWindowController.saveDocument(_:)), "s", .command),
                                          (String(localized: "Enregistrer sous…"), #selector(EditorWindowController.saveDocumentAs(_:)), "s", [.command, .shift]),
                                          (String(localized: "Épingler"), #selector(EditorWindowController.pin), "p", .command),
                                          (String(localized: "Fermer"), #selector(NSWindow.performClose(_:)), "w", .command)])
        sub(String(localized: "Édition"), [(String(localized: "Annuler"), #selector(EditorWindowController.undo(_:)), "z", .command),
                                          (String(localized: "Rétablir"), #selector(EditorWindowController.redo(_:)), "z", [.command, .shift]),
                                          (String(localized: "Copier"), #selector(NSText.copy(_:)), "c", .command),
                                          (String(localized: "Coller"), #selector(NSText.paste(_:)), "v", .command),
                                          (String(localized: "Tout sélectionner"), #selector(NSText.selectAll(_:)), "a", .command)])
        sub(String(localized: "Présentation"), [(String(localized: "Zoom avant"), #selector(EditorWindowController.zoomIn(_:)), "+", .command),
                                               (String(localized: "Zoom arrière"), #selector(EditorWindowController.zoomOut(_:)), "-", .command),
                                               (String(localized: "Taille réelle"), #selector(EditorWindowController.zoomActual(_:)), "0", .command),
                                               (String(localized: "Ajuster à la fenêtre"), #selector(EditorWindowController.zoomFit(_:)), "9", .command)])
        NSApp.mainMenu = main
    }

    /// Raccourcis affichés à jour (ils sont modifiables dans les réglages).
    func menuNeedsUpdate(_ menu: NSMenu) {
        for it in menu.items {
            guard let raw = it.representedObject as? String, let a = Action(rawValue: raw) else { continue }
            if let sc = a.shortcut, let key = sc.keyEquivalent {
                it.keyEquivalent = key
                it.keyEquivalentModifierMask = sc.cocoaModifiers
            } else {
                it.keyEquivalent = ""
            }
        }
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let a = Action(rawValue: raw) else { return }
        // Laisser le menu se fermer avant de figer l'écran.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.perform(a) }
    }

    @objc private func openFile() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .heic]
        if p.runModal() == .OK, let u = p.url, let s = Output.imageFromFile(u) { openEditor(s) }
    }

    // MARK: Actions

    func perform(_ a: Action) {
        guard !busy, selector == nil, scrollCapture == nil else { return }
        switch a {
        case .fullscreen: Task { await captureFullscreen() }
        case .delayed:
            Toast.show(String(localized: "Capture dans 3 s…"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Task { await self.captureFullscreen() } }
        case .area: Task { await select(.area) { [weak self] r, shot in self?.areaChosen(r, shot) } }
        case .areaRepeat:
            guard let r = Settings.shared.lastArea, let screen = NSScreen.screens.first(where: { $0.frame.intersects(r) }) else {
                Toast.show(String(localized: "Faites d'abord une capture de zone")); return
            }
            Task {
                guard let full = await grab(screen), let s = Capturer.crop(full, to: r) else { return }
                delivered(s)
            }
        case .window: Task { await select(.window) { _, _ in } }
        case .scrolling:
            if ScrollCapture.needsAccessibility() {
                Toast.show(String(localized: "La capture défilante demande l'autorisation Accessibilité")); return
            }
            Task {
                await select(.area) { [weak self] r, shot in
                    guard let self, let shot else { return }
                    let screen = NSScreen.screens.first { $0.frame.intersects(r) } ?? Capturer.activeScreen
                    _ = shot
                    let sc = ScrollCapture(rect: r, screen: screen) { [weak self] s in
                        self?.scrollCapture = nil
                        if let s { self?.openEditor(s) }
                    }
                    self.scrollCapture = sc
                    sc.start()
                }
            }
        case .ocr:
            Task {
                await select(.area) { r, shot in
                    guard let shot, let s = Capturer.crop(shot, to: r) else { return }
                    OCR.recognize(s.image) { text in
                        guard let text else { Toast.show(String(localized: "Aucun texte détecté")); return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        Toast.show(String(localized: "Texte copié : \(String(text.prefix(40)))"))
                    }
                }
            }
        case .openClipboard:
            if let s = Output.imageFromClipboard() { openEditor(s) } else { Toast.show(String(localized: "Pas d'image dans le presse-papiers")) }
        }
    }

    private func grab(_ screen: NSScreen) async -> Shot? {
        do { return try await Capturer.captureScreen(screen) } catch {
            await MainActor.run { Toast.show(error.localizedDescription) }
            return nil
        }
    }

    @MainActor private func captureFullscreen() async {
        busy = true; defer { busy = false }
        guard let s = await grab(Capturer.activeScreen) else { return }
        delivered(s)
    }

    /// Fige l'écran actif puis ouvre le sélecteur. En mode fenêtre, capture directement la fenêtre choisie.
    @MainActor private func select(_ mode: AreaSelector.Mode, then: @escaping (CGRect, Shot?) -> Void) async {
        busy = true
        let screen = Capturer.activeScreen
        guard let frozen = await grab(screen) else { busy = false; return }
        let windows = mode == .window ? ((try? await Capturer.visibleWindows()) ?? []) : []
        busy = false
        let sel = AreaSelector(screen: screen, frozen: frozen, mode: mode, windows: windows) { [weak self] result in
            self?.selector = nil
            switch result {
            case .cancelled: break
            case let .area(r): then(r, frozen)
            case let .window(w):
                Task { @MainActor in
                    do { self?.delivered(try await Capturer.captureWindow(w)) } catch { Toast.show(error.localizedDescription) }
                }
            }
        }
        selector = sel
        sel.present()
    }

    private func areaChosen(_ r: CGRect, _ frozen: Shot?) {
        guard let frozen, let s = Capturer.crop(frozen, to: r) else { return }
        Settings.shared.lastArea = r
        delivered(s)
    }

    /// Après une capture : copie / enregistrement automatiques, puis vignette ou éditeur.
    func delivered(_ s: Shot) {
        let st = Settings.shared
        if st.copyAfterCapture { Output.copy(s.image, scale: s.scale) }
        if st.saveAfterCapture { Output.save(s.image, scale: s.scale, date: s.date) }
        switch st.afterCapture {
        case .editor: openEditor(s)
        case .preview: PreviewPanel.show(s) { [weak self] in self?.openEditor($0) }
        case .nothing: Toast.show(st.copyAfterCapture ? String(localized: "Copié") : String(localized: "Capturé"))
        }
    }

    func openEditor(_ s: Shot) {
        let e = EditorWindowController(shot: s)
        e.onClose = { [weak self] c in self?.editors.removeAll { $0 === c } }
        editors.append(e)
        e.show()
    }

    // MARK: Schéma d'URL  cliche://grab/area, cliche://grab/fullscreen, cliche://grab/window, cliche://grab/scrolling, cliche://ocr

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let u = URL(string: s) else { return }
        guard let cmd = URLCommand.parse(u) else { Toast.show(String(localized: "Lien cliche:// refusé")); return }
        // Comme Shottr : les liens sont désactivés tant que l'utilisateur ne les a pas autorisés (une page web peut en ouvrir).
        let d = UserDefaults.standard
        if !d.bool(forKey: "allowDeepLinks") {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = String(localized: "Autoriser les liens cliche:// ?")
            a.informativeText = String(localized: "Une app ou une page web demande « \(cmd.rawValue) ». Si vous autorisez, les liens cliche:// pourront lancer des captures sans confirmation. Modifiable dans Réglages › Raccourcis.")
            a.addButton(withTitle: String(localized: "Autoriser"))
            a.addButton(withTitle: String(localized: "Refuser"))
            guard a.runModal() == .alertFirstButtonReturn else { return }
            d.set(true, forKey: "allowDeepLinks")
        }
        let map: [URLCommand: Action] = [.fullscreen: .fullscreen, .area: .area, .areaRepeat: .areaRepeat, .window: .window,
                                         .scrolling: .scrolling, .delayed: .delayed, .ocr: .ocr, .clipboard: .openClipboard]
        if let a = map[cmd] { perform(a) }
    }

    @objc func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow.make() }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
