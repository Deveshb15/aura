import SwiftUI
import AppKit

/// Centralized palette + Awesome Serif typography for the redesigned Library
/// window. Tokens are **adaptive**: each resolves a dark or light value from the
/// active appearance, so the whole UI flips when a host applies
/// `.preferredColorScheme(...)` (driven by `ThemeManager`). Dark is the default;
/// the dark values match the original Figma mockup. Because resolution happens at
/// render time off the environment's color scheme, every `AuraTheme.*` call site
/// adapts for free — no per-site edits.
enum AuraTheme {
    static let background      = hex(dark: "#0B0B0D", light: "#F6F6F8")
    static let surface         = hex(dark: "#19191B", light: "#FFFFFF")
    static let surfaceHover    = hex(dark: "#202023", light: "#F0F0F2")
    static let hairline        = blend(dark: (.white, 0.06), light: (.black, 0.08))
    static let textPrimary     = hex(dark: "#F2F2F3", light: "#1A1A1C")
    static let textSecondary   = hex(dark: "#8B8B8E", light: "#6E6E73")
    static let textTertiary    = hex(dark: "#6A6A6E", light: "#9A9A9E")
    static let accentDot       = hex(dark: "#FF5C8A", light: "#FF5C8A") // pink reads on both
    static let activePill      = hex(dark: "#FFFFFF", light: "#1A1A1C")
    static let destructive     = hex(dark: "#FF6B6B", light: "#E5484D")

    /// Sky-blue brand accent — the flying-carpet "sky" that the app icon and DMG
    /// installer lead with. Used by the onboarding atmosphere + accents (kept out
    /// of the working surfaces, which stay on `accentDot`).
    static let sky             = hex(dark: "#5C9CEC", light: "#3B82E0")
    static let skyDeep         = hex(dark: "#4C9ADC", light: "#2F6FC8")

    // MARK: - Tokens for surfaces that were previously inline white/black opacity

    /// Text/glyph color drawn ON the active tab pill (which inverts per theme).
    static let activePillLabel = hex(dark: "#0B0B0D", light: "#FFFFFF")
    /// A slightly stronger hairline for chips, action buttons, the notch border.
    static let hairlineStrong  = blend(dark: (.white, 0.10), light: (.black, 0.12))
    /// Faint fill for chips / mini-card tiles / off-state toggle tracks.
    static let fill            = blend(dark: (.white, 0.08), light: (.black, 0.05))
    /// Even fainter fill (e.g. inert pills, inputs).
    static let fillSubtle      = blend(dark: (.white, 0.05), light: (.black, 0.035))
    /// Drop shadow under cards / toasts — much softer in light mode.
    static let shadow          = blend(dark: (.black, 0.35), light: (.black, 0.12))
    /// The notch panel: pure black in dark (blends with the hardware notch),
    /// white in light. Kept distinct from `surface` so the dark notch stays #000.
    static let notchPanel      = hex(dark: "#000000", light: "#FFFFFF")

    // MARK: - Adaptive helpers

    /// Wraps a light/dark provider in a dynamic `NSColor`; SwiftUI re-resolves it
    /// against the environment's color scheme whenever a host's appearance flips.
    private static func dynamic(_ provider: @escaping (Bool) -> NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            provider(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        })
    }

    /// Adaptive solid color from two `#RRGGBB` hex strings.
    private static func hex(dark: String, light: String) -> Color {
        let d = nsColor(dark), l = nsColor(light)
        return dynamic { $0 ? d : l }
    }

    /// Parses a `#RRGGBB` string into an sRGB `NSColor` (the palette is all
    /// 6-digit opaque hex). Mirrors `Color(hex:)` but stays in NSColor space so
    /// the dynamic provider returns a concrete, non-dynamic color.
    private static func nsColor(_ hex: String) -> NSColor {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255,
                       alpha: 1)
    }

    /// Adaptive translucent color: a base (white/black) at a per-theme opacity.
    private static func blend(dark: (NSColor, CGFloat), light: (NSColor, CGFloat)) -> Color {
        let d = dark.0.withAlphaComponent(dark.1)
        let l = light.0.withAlphaComponent(light.1)
        return dynamic { $0 ? d : l }
    }
}

/// Awesome Serif, addressed by its exact PostScript name per weight × height.
/// The family ships three optical "height" cuts (Regular / Tall / ExtraTall);
/// the taller cuts have longer ascenders and read better at display sizes
/// (the "Capture Aura" wordmark and the "Ask your Memory…" hero).
enum AuraFont {
    enum Weight { case light, regular, medium, semibold, bold }
    enum Height { case regular, tall, extraTall }

    static func serif(_ size: CGFloat, _ weight: Weight = .regular, _ height: Height = .regular) -> Font {
        Font.custom(postScriptName(weight, height), size: size)
    }

    /// Explicit mapping — the shipped names are slightly irregular (note the
    /// `SemBd` abbreviation only in the ExtraTall cut), so we don't string-build.
    static func postScriptName(_ weight: Weight, _ height: Height) -> String {
        switch (weight, height) {
        case (.regular, .regular):    return "AwesomeSerif-Regular"
        case (.regular, .tall):       return "AwesomeSerif-Tall"
        case (.regular, .extraTall):  return "AwesomeSerif-ExtraTall"
        case (.light, .regular):      return "AwesomeSerif-LightRegular"
        case (.light, .tall):         return "AwesomeSerif-LightTall"
        case (.light, .extraTall):    return "AwesomeSerif-LightExtraTall"
        case (.medium, .regular):     return "AwesomeSerif-MediumRegular"
        case (.medium, .tall):        return "AwesomeSerif-MediumTall"
        case (.medium, .extraTall):   return "AwesomeSerif-MediumExtraTall"
        case (.semibold, .regular):   return "AwesomeSerif-SemiBoldRegular"
        case (.semibold, .tall):      return "AwesomeSerif-SemiBoldTall"
        case (.semibold, .extraTall): return "AwesomeSerif-SemBdExtraTall"
        case (.bold, .regular):       return "AwesomeSerif-BoldRegular"
        case (.bold, .tall):          return "AwesomeSerif-BoldTall"
        case (.bold, .extraTall):     return "AwesomeSerif-BoldExtraTall"
        }
    }
}
