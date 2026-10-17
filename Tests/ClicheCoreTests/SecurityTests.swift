import Foundation
import Testing
@testable import ClicheCore

/// Tests de sécurité : tout ce qui arrive de l'extérieur doit être refusé par défaut.
@Suite struct URLSchemeSecurityTests {
    @Test func acceptsKnownCommands() {
        for c in URLCommand.allCases {
            #expect(URLCommand.parse(URL(string: "cliche://\(c.rawValue)")!) == c)
        }
        #expect(URLCommand.parse(URL(string: "CLICHE://grab/area")!) == .area)
    }

    @Test(arguments: [
        "shottr://grab/area",                     // autre schéma
        "cliche://grab/area?then=save",           // paramètres refusés
        "cliche://grab/area#x",                   // fragment
        "cliche://user:pw@grab/area",             // identifiants
        "cliche://grab:80/area",                  // port
        "cliche://grab/../settings",              // remontée de chemin
        "cliche://grab/area/../../etc",
        "cliche://grab/area/extra/more",          // trop de segments
        "cliche://grab/%2e%2e/area",              // encodage
        "cliche://grab/Area",                     // casse du chemin
        "cliche://",                              // vide
        "cliche://grab",
        "cliche://load/file",                     // pas d'ouverture de fichier par lien
        "file:///etc/passwd",
        "javascript:alert(1)",
    ])
    func rejectsEverythingElse(_ s: String) {
        guard let u = URL(string: s) else { return }
        #expect(URLCommand.parse(u) == nil)
    }
}

@Suite struct FilenameSecurityTests {
    @Test func sanitizes() {
        #expect(SafeFilename.sanitize("../../.ssh/authorized_keys") == "-.-.ssh-authorized_keys" || !SafeFilename.sanitize("../../.ssh/authorized_keys").contains("/"))
        #expect(!SafeFilename.sanitize("a/b\\c:d").contains("/"))
        #expect(!SafeFilename.sanitize(".hidden").hasPrefix("."))
        #expect(SafeFilename.sanitize("\u{0}\u{7}") == "Cliché")
        #expect(SafeFilename.sanitize(String(repeating: "é", count: 500)).utf8.count <= 240)
        #expect(SafeFilename.sanitize("Capture 2026-10-17.png") == "Capture 2026-10-17.png")
    }

    @Test func containment() {
        let dir = URL(fileURLWithPath: "/tmp/cliche-test-dir")
        #expect(SafeFilename.isInside(dir.appendingPathComponent("a.png"), folder: dir))
        #expect(!SafeFilename.isInside(dir.appendingPathComponent("../x.png"), folder: dir))
        #expect(!SafeFilename.isInside(URL(fileURLWithPath: "/tmp/cliche-test-dir-evil/a.png"), folder: dir))
    }

    @Test func exportNamesAreSafe() {
        let n = Exporter.filename(date: Date(timeIntervalSince1970: 0), ext: "png")
        #expect(SafeFilename.sanitize(n) == n)
    }
}
