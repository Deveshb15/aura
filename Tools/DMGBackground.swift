// DMGBackground.swift — renders the disk-image "drag to Applications" background, no external deps.
//
// Run:  swift Tools/DMGBackground.swift   → writes dist/dmg-bg-1x.png + dist/dmg-bg-2x.png
//       (660×420 @1x and 1320×840 @2x). A HiDPI .tiff is then assembled from them
//       (tiffutil -cathidpicheck) so the background maps 1:1 to the 660×420-point window
//       yet stays crisp on retina — see scripts/release.sh.
//
// Carpet's sky identity: the bright blue cloud sky (Tools/sky.png, rasterized from the
// shared sky.svg by Tools/render_sky.sh — clouds frame the corners, center open), the
// "Capture Carpet" Awesome Serif wordmark in white, two soft frosted-white cards where the
// app icon and the Applications alias rest (so the art + Finder's black icon labels stay
// crisp on the sky), and a rose arrow between them. The drop-zone centers MUST match the
// create-dmg --icon / --app-drop-link coordinates (app at 180,205 — Applications at 480,205).
//
// Self-contained: inlines RGBA + c(), loads Tools/sky.png, and registers the bundled Awesome
// Serif so it compiles standalone and never enters the app target.

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
    private let accentRose = 0xFF5C8A
    private let shadowInk = 0x1B4368   // deep sky-shadow blue, for soft text/card shadows
    private let sky = NSImage(contentsOfFile: "Tools/sky.png")

    var body: some View {
        ZStack {
            // Sky base — clouds frame the corners, the center stays open. Falls back to a
            // flat brand blue if sky.png is somehow missing so the render never crashes.
            if let sky {
                Image(nsImage: sky).resizable().frame(width: W, height: H)
            } else {
                c(0x4C9ADC)
            }

            // Wordmark — "Capture Carpet", white like the logo wordmark.
            Text("Capture Carpet")
                .font(.custom("AwesomeSerif-MediumRegular", size: 30))
                .foregroundStyle(.white)
                .shadow(color: c(shadowInk, 0.35), radius: 6, y: 1)
                .position(x: W / 2, y: 58)

            Text("your captures, one drag from home")
                .font(.system(size: 13.5, weight: .medium, design: .default))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: c(shadowInk, 0.3), radius: 4, y: 1)
                .position(x: W / 2, y: 92)

            pad.position(appCenter)
            pad.position(appsCenter)

            ArrowShape()
                .stroke(c(accentRose), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .frame(width: 116, height: 28)
                .position(x: (appCenter.x + appsCenter.x) / 2, y: appCenter.y)
                .shadow(color: c(accentRose, 0.5), radius: 7, y: 2)

            Text("drag Carpet into your Applications folder")
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundStyle(.white)
                .shadow(color: c(shadowInk, 0.38), radius: 5, y: 1)
                .position(x: W / 2, y: 372)
        }
        .frame(width: W, height: H)
    }

    /// A soft frosted-white card the real icon / Applications alias rests on, so the art and
    /// Finder's black icon labels stay crisp and pop against the blue sky.
    private var pad: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white.opacity(0.9))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.95), lineWidth: 1))
            .frame(width: 168, height: 190)
            .shadow(color: c(shadowInk, 0.32), radius: 18, y: 8)
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
