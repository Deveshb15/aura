// DMGBackground.swift — renders the disk-image "drag to Applications" background, no external deps.
//
// Run:  swift Tools/DMGBackground.swift   → writes dist/dmg-bg-1x.png + dist/dmg-bg-2x.png
//       (660×420 @1x and 1320×840 @2x). A HiDPI .tiff is then assembled from them
//       (tiffutil -cathidpicheck) so the background maps 1:1 to the 660×420-point window
//       yet stays crisp on retina — see scripts/release.sh.
//
// Aura's dark serif identity: near-black canvas + a low rose glow, the "Capture Aura"
// Awesome Serif wordmark with its pink accent dot, two frosted pads where the app icon
// and the Applications alias rest (kept light so Finder's icon labels stay legible on the
// dark canvas), and a rose arrow between them. The drop-zone centers MUST match the
// create-dmg --icon / --app-drop-link coordinates (app at 180,205 — Applications at 480,205).
//
// Self-contained: inlines RGBA + c() and registers the bundled Awesome Serif so it compiles
// standalone and never enters the app target.

import SwiftUI
import AppKit
import CoreText

struct RGBA {
    var r, g, b, a: Double
    init(hex: UInt32, a: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        self.a = a
    }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}
func c(_ hex: Int, _ a: Double = 1) -> Color { RGBA(hex: UInt32(truncatingIfNeeded: hex), a: a).color }

/// Register the bundled Awesome Serif faces so Font.custom resolves in this standalone process.
func registerAwesomeSerif() {
    let dir = "Aura/Fonts/Awesome-Serif"
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
    for f in files where f.hasSuffix(".otf") {
        CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "\(dir)/\(f)") as CFURL, .process, nil)
    }
}

private let W: CGFloat = 660
private let H: CGFloat = 420
private let appCenter  = CGPoint(x: 180, y: 205)
private let appsCenter = CGPoint(x: 480, y: 205)

struct DMGBackgroundArt: View {
    // AuraTheme hexes.
    private let bgTop = 0x0B0B0D, bgBot = 0x141417
    private let textPrimary = 0xF2F2F3, textSecondary = 0x8B8B8E, accentRose = 0xFF5C8A

    var body: some View {
        ZStack {
            LinearGradient(colors: [c(bgTop), c(bgBot)], startPoint: .top, endPoint: .bottom)
            // A low rose bloom echoing the accent dot.
            RadialGradient(colors: [c(accentRose, 0.16), c(accentRose, 0)],
                           center: UnitPoint(x: 0.5, y: 0.92),
                           startRadius: 0, endRadius: W * 0.55)
            // A faint top highlight for depth.
            RadialGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0)],
                           center: UnitPoint(x: 0.5, y: 0.0),
                           startRadius: 0, endRadius: W * 0.5)

            // Wordmark — "Capture Aura", mirroring the app header.
            Text("Capture Aura")
                .font(.custom("AwesomeSerif-MediumRegular", size: 30))
                .foregroundStyle(c(textPrimary))
                .position(x: W / 2, y: 58)

            Text("your captures, one drag from home")
                .font(.system(size: 13.5, weight: .regular, design: .default))
                .foregroundStyle(c(textSecondary))
                .position(x: W / 2, y: 92)

            pad.position(appCenter)
            pad.position(appsCenter)

            ArrowShape()
                .stroke(c(accentRose), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .frame(width: 116, height: 28)
                .position(x: (appCenter.x + appsCenter.x) / 2, y: appCenter.y)
                .shadow(color: c(accentRose, 0.45), radius: 7, y: 2)

            Text("drag Aura into your Applications folder")
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(c(textSecondary))
                .position(x: W / 2, y: 372)
        }
        .frame(width: W, height: H)
    }

    /// A soft frosted pad the real icon / Applications alias rests on. Kept light so the
    /// black Finder icon labels stay readable against the dark canvas.
    private var pad: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color.white.opacity(0.92))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
            .frame(width: 168, height: 190)
            .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }
}

/// A horizontal arrow pointing right (from the app pad toward the Applications pad).
struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = rect.midY
        p.move(to: CGPoint(x: rect.minX, y: y))
        p.addLine(to: CGPoint(x: rect.maxX, y: y))
        p.move(to: CGPoint(x: rect.maxX - 14, y: y - 9))
        p.addLine(to: CGPoint(x: rect.maxX, y: y))
        p.addLine(to: CGPoint(x: rect.maxX - 14, y: y + 9))
        return p
    }
}

@MainActor
func render(scale: CGFloat, to out: String) {
    let renderer = ImageRenderer(content: DMGBackgroundArt().frame(width: W, height: H))
    renderer.scale = scale
    guard let cg = renderer.cgImage else {
        FileHandle.standardError.write(Data("ERROR: no image\n".utf8)); exit(1)
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("ERROR: png encode\n".utf8)); exit(1)
    }
    do {
        try data.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)  (\(cg.width)×\(cg.height))")
    } catch {
        FileHandle.standardError.write(Data("ERROR writing \(out): \(error)\n".utf8)); exit(1)
    }
}

registerAwesomeSerif()
MainActor.assumeIsolated {
    render(scale: 1, to: "dist/dmg-bg-1x.png")
    render(scale: 2, to: "dist/dmg-bg-2x.png")
}
