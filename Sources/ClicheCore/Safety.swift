import Foundation

/// Entrées venues de l'extérieur : liens `cliche://` (n'importe quelle app ou page web peut en ouvrir un)
/// et noms de fichiers. Tout ce qui n'est pas explicitement connu est refusé.
public enum URLCommand: String, CaseIterable, Sendable {
    case fullscreen = "grab/fullscreen"
    case area = "grab/area"
    case areaRepeat = "grab/area/repeat"
    case window = "grab/window"
    case scrolling = "grab/scrolling"
    case delayed = "grab/delayed"
    case ocr = "ocr"
    case clipboard = "load/clipboard"

    /// Commande d'un lien `cliche://…` ; nil si le schéma, l'hôte ou le chemin ne sont pas exactement attendus.
    /// Les paramètres de requête, fragments, identifiants et ports sont refusés : aucune donnée n'entre par un lien.
    public static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == "cliche",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              let host = url.host, !host.isEmpty else { return nil }
        let parts = [host] + url.pathComponents.filter { $0 != "/" }
        guard parts.count <= 3, parts.allSatisfy({ $0.range(of: "^[a-z]+$", options: .regularExpression) != nil }) else { return nil }
        return URLCommand(rawValue: parts.joined(separator: "/"))
    }
}

public enum SafeFilename {
    /// Nettoie un nom de fichier proposé : pas de séparateur de chemin, pas de « .. », pas de caractères de contrôle,
    /// pas de point initial (fichier caché), longueur bornée. Ne renvoie jamais une chaîne vide.
    public static func sanitize(_ name: String, fallback: String = "Cliché") -> String {
        var s = name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined()
        for bad in ["/", ":", "\\"] { s = s.replacingOccurrences(of: bad, with: "-") }
        while s.contains("..") { s = s.replacingOccurrences(of: "..", with: ".") }
        s = s.trimmingCharacters(in: .whitespaces)
        while s.hasPrefix(".") { s.removeFirst() }
        if s.utf8.count > 200 { s = String(s.prefix(120)) }
        return s.isEmpty ? fallback : s
    }

    /// Vrai si `file` est bien à l'intérieur de `folder` une fois les liens et « .. » résolus.
    public static func isInside(_ file: URL, folder: URL) -> Bool {
        let f = file.standardizedFileURL.resolvingSymlinksInPath().path
        let d = folder.standardizedFileURL.resolvingSymlinksInPath().path
        return f.hasPrefix(d.hasSuffix("/") ? d : d + "/")
    }
}
