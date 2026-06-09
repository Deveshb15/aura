import SwiftUI

/// Centralized dark palette + Awesome Serif typography for the redesigned
/// Library window. Colors are explicit (not system colors) so the window reads
/// identically regardless of the system light/dark setting — the window forces
/// `.preferredColorScheme(.dark)`, and these tokens match the Figma mockup.
enum AuraTheme {
    static let background   = Color(hex: "#0B0B0D")!
    static let surface      = Color(hex: "#19191B")!
    static let surfaceHover = Color(hex: "#202023")!
    static let hairline     = Color.white.opacity(0.06)
    static let textPrimary  = Color(hex: "#F2F2F3")!
    static let textSecondary = Color(hex: "#8B8B8E")!
    static let textTertiary = Color(hex: "#6A6A6E")!
    static let accentDot    = Color(hex: "#FF5C8A")!
    static let activePill   = Color.white
    static let destructive  = Color(hex: "#FF6B6B")!
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
