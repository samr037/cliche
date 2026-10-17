import AppKit
import Carbon.HIToolbox

/// Raccourci clavier global : code de touche + modificateurs Carbon.
struct Shortcut: Equatable, Codable {
    var keyCode: UInt32
    var modifiers: UInt32

    static func cmdShift(_ k: Int) -> Shortcut { Shortcut(keyCode: UInt32(k), modifiers: UInt32(cmdKey | shiftKey)) }

    init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }

    /// Depuis un événement clavier ; nil sans modificateur (un raccourci global sans modificateur volerait la touche partout).
    init?(event e: NSEvent) {
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        let isFKey = (96...122).contains(Int(e.keyCode))
        guard m & UInt32(cmdKey | optionKey | controlKey) != 0 || isFKey else { return nil }
        self.init(keyCode: UInt32(e.keyCode), modifiers: m)
    }

    /// Équivalent pour l'affichage dans un NSMenu (touche simple uniquement).
    var keyEquivalent: String? {
        let name = Self.keyName(Int(keyCode))
        return name.count == 1 ? name.lowercased() : nil
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { f.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { f.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        return f
    }

    var label: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Self.keyName(Int(keyCode))
    }

    static func keyName(_ code: Int) -> String {
        let special: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: String(localized: "Espace"), kVK_Delete: "⌫", kVK_Escape: "⎋", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        ]
        if let s = special[code] { return s }
        // Caractère produit par la touche sur la disposition clavier courante (A, Z, 1, &…).
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        func translate(_ modifiers: UInt32) -> String? {
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var len = 0
            let status = data.withUnsafeBytes { raw -> OSStatus in
                UCKeyTranslate(raw.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(code), UInt16(kUCKeyActionDisplay),
                               modifiers, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
            }
            return status == noErr && len > 0 ? String(utf16CodeUnits: chars, count: len) : nil
        }
        guard let plain = translate(0) else { return "?" }
        // Rangée des chiffres en AZERTY : la touche donne « & » ou « é » sans Maj et « 1 » ou « 2 » avec. On affiche le chiffre,
        // comme les raccourcis ⇧⌘1… sont documentés partout.
        if let shifted = translate(UInt32(shiftKey >> 8) & 0xFF), shifted.count == 1, shifted.first!.isNumber,
           !(plain.first?.isNumber ?? false) {
            return shifted
        }
        return plain.uppercased()
    }
}

/// Actions globales, avec leur raccourci par défaut (évite ⌘⇧3/4/5 de macOS).
enum Action: String, CaseIterable {
    case fullscreen, area, areaRepeat, window, scrolling, ocr, delayed, openClipboard

    var title: String {
        switch self {
        case .fullscreen: return String(localized: "Capture plein écran")
        case .area: return String(localized: "Capture de zone")
        case .areaRepeat: return String(localized: "Répéter la capture de zone")
        case .window: return String(localized: "Capture de fenêtre")
        case .scrolling: return String(localized: "Capture défilante")
        case .ocr: return String(localized: "Reconnaître le texte (OCR / QR)")
        case .delayed: return String(localized: "Capture plein écran différée (3 s)")
        case .openClipboard: return String(localized: "Ouvrir depuis le presse-papiers")
        }
    }

    var symbol: String {
        switch self {
        case .fullscreen: return "macwindow"
        case .area: return "viewfinder"
        case .areaRepeat: return "arrow.clockwise"
        case .window: return "macwindow.on.rectangle"
        case .scrolling: return "arrow.down.to.line.compact"
        case .ocr: return "text.viewfinder"
        case .delayed: return "timer"
        case .openClipboard: return "doc.on.clipboard"
        }
    }

    var defaultShortcut: Shortcut? {
        switch self {
        case .fullscreen: return .cmdShift(kVK_ANSI_1)
        case .area: return .cmdShift(kVK_ANSI_2)
        case .areaRepeat: return .cmdShift(kVK_ANSI_9)
        case .window: return .cmdShift(kVK_ANSI_6)
        case .scrolling: return .cmdShift(kVK_ANSI_7)
        case .ocr: return .cmdShift(kVK_ANSI_8)
        case .delayed, .openClipboard: return nil
        }
    }

    /// Raccourci effectif : réglage de l'utilisateur, sinon défaut. Un raccourci effacé est stocké vide.
    var shortcut: Shortcut? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "shortcut.\(rawValue)") else { return defaultShortcut }
            return try? JSONDecoder().decode(Shortcut?.self, from: data)
        }
        nonmutating set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "shortcut.\(rawValue)")
            Hotkeys.shared.reload()
        }
    }

    var shortcutLabel: String { shortcut?.label ?? "" }
}

/// Raccourcis globaux via RegisterEventHotKey (pas de permission d'Accessibilité nécessaire).
final class Hotkeys {
    static let shared = Hotkeys()
    private var refs: [EventHotKeyRef] = []
    private var handlers: [Action: () -> Void] = [:]
    private var installed = false
    /// Raccourcis refusés par le système (déjà pris par une autre app).
    private(set) var conflicts: Set<Action> = []
    var onChange: (() -> Void)?

    func register(_ action: Action, _ handler: @escaping () -> Void) {
        handlers[action] = handler
        reload()
    }

    /// Désenregistre tout (pendant l'enregistrement d'un nouveau raccourci dans les réglages).
    func suspend() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    func reload() {
        installHandlerOnce()
        suspend()
        conflicts.removeAll()
        for (i, a) in Action.allCases.enumerated() where handlers[a] != nil {
            guard let sc = a.shortcut else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x434C4943), id: UInt32(i + 1))   // 'CLIC'
            if RegisterEventHotKey(sc.keyCode, sc.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            } else {
                conflicts.insert(a)
            }
        }
        onChange?()
    }

    private func installHandlerOnce() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let i = Int(hk.id) - 1
            DispatchQueue.main.async {
                guard Action.allCases.indices.contains(i) else { return }
                Hotkeys.shared.handlers[Action.allCases[i]]?()
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
