import AppKit
import CoreText

/// Registers the bundled Awesome Serif `.otf` files with the running process at
/// launch so `Font.custom("AwesomeSerif-…")` resolves. Doing this in-process is
/// deterministic regardless of how the build lays the font files into the
/// bundle (flat in Resources/ vs. preserved in a subfolder).
enum FontRegistrar {
    static func registerBundledFonts() {
        var urls = Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? []
        for sub in ["Awesome-Serif", "Fonts/Awesome-Serif", "Fonts"] {
            urls += Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: sub) ?? []
        }
        let unique = Array(Set(urls))
        guard !unique.isEmpty else {
            NSLog("Aura: no bundled .otf fonts found to register")
            return
        }

        for url in unique {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // "already registered" is benign (e.g. if also auto-registered).
                let desc = error?.takeRetainedValue().localizedDescription ?? "unknown"
                NSLog("Aura: font register skipped \(url.lastPathComponent): \(desc)")
            }
        }

        let faces = NSFontManager.shared.availableFonts.filter { $0.contains("AwesomeSerif") }
        NSLog("Aura: AwesomeSerif faces available: \(faces.count)")
    }
}
