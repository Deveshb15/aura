import Foundation

/// Installs the Chrome Native Messaging host manifest for `aura-x-host` into
/// every installed Chromium-family browser, so the Aura browser extension can
/// reach the desktop app with no localhost port to configure and no install
/// order to worry about. Idempotent; run on every launch (paths can change when
/// the app moves).
enum XHostManifestInstaller {
    static let hostName = "app.captureaura.xhost"
    /// Extension IDs allowed to talk to the host. The first is the pinned
    /// unpacked/dev ID (derived from the `key` in the extension manifest). After
    /// publishing to the Chrome Web Store — which assigns its OWN id and rejects
    /// any upload containing `key` — add that store id here and rebuild.
    static let extensionIDs = [
        "gmombdkcjjnlgcbfanhcfgabpjkajdbn",   // unpacked / dev
        // "<chrome-web-store-id>",            // ← paste after publishing, then rebuild
    ]

    /// Browser data directories (under ~/Library/Application Support) that hold a
    /// `NativeMessagingHosts/` folder. We only write where the browser exists.
    private static let browserBases = [
        "Google/Chrome",
        "Google/Chrome Beta",
        "Google/Chrome Canary",
        "Google/Chrome Dev",
        "Chromium",
        "Microsoft Edge",
        "BraveSoftware/Brave-Browser",
        "Arc/User Data",
        "Arc",
        "Vivaldi",
        "company.thebrowser.dia/Dia", // Dia (Chromium-based), best-effort
    ]

    static func install() {
        guard let helperPath = helperExecutablePath() else {
            NSLog("Aura: aura-x-host not found in bundle; skipping native-host install")
            return
        }

        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Aura X bookmark bridge",
            "path": helperPath,
            "type": "stdio",
            "allowed_origins": extensionIDs.map { "chrome-extension://\($0)/" },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) else { return }

        let fm = FileManager.default
        guard let support = try? fm.url(for: .applicationSupportDirectory,
                                        in: .userDomainMask, appropriateFor: nil, create: false) else { return }

        for base in browserBases {
            let browserDir = support.appendingPathComponent(base, isDirectory: true)
            guard fm.fileExists(atPath: browserDir.path) else { continue }
            let hostsDir = browserDir.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
            do {
                try fm.createDirectory(at: hostsDir, withIntermediateDirectories: true)
                let dest = hostsDir.appendingPathComponent("\(hostName).json")
                try data.write(to: dest, options: .atomic)
            } catch {
                NSLog("Aura: failed to install native-host manifest in \(base): \(error)")
            }
        }
    }

    /// The bundled helper. XcodeGen copies it under Contents/Helpers; we also
    /// check Contents/MacOS as a fallback depending on the copy destination.
    private static func helperExecutablePath() -> String? {
        let candidates = [
            "Contents/Helpers/aura-x-host",
            "Contents/MacOS/aura-x-host",
        ]
        let bundle = Bundle.main.bundleURL
        let fm = FileManager.default
        for rel in candidates {
            let url = bundle.appendingPathComponent(rel)
            if fm.fileExists(atPath: url.path) { return url.path }
        }
        return nil
    }
}
