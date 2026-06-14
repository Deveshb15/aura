import SwiftUI
import AppKit

// Small reusable building blocks for the onboarding flow: keycap chips for
// rendering hotkeys (⌥⌘V / ⌃⌘N) and the two button styles used across screens.

/// The atmospheric backdrop behind the welcome logo and every illustration:
/// a soft sky-blue glow with a few blurred cloud puffs framing the corners
/// (center left open). On-brand with the flying-carpet "sky" of the app icon
/// and DMG installer — and deliberately NO pink, unlike the old dual-tone glow.
struct SkyBackdrop: View {
    var size: CGFloat = 260
    var intensity: Double = 0.5

    var body: some View {
        ZStack {
            skyGlow
            clouds
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    /// A cool sky-blue radial, biased slightly upward (sky overhead).
    private var skyGlow: some View {
        Circle()
            .fill(RadialGradient(
                colors: [AuraTheme.sky.opacity(intensity),
                         AuraTheme.skyDeep.opacity(intensity * 0.45),
                         .clear],
                center: .center, startRadius: 0, endRadius: size * 0.6))
            .frame(width: size, height: size)
            .offset(y: -size * 0.05)
            .blur(radius: size * 0.04)
    }

    /// Three soft white puffs, heavily blurred into a sky haze.
    private var clouds: some View {
        ZStack {
            cloud(w: size * 0.60, h: size * 0.20).opacity(0.11)
                .offset(x: -size * 0.28, y: -size * 0.22)
            cloud(w: size * 0.48, h: size * 0.16).opacity(0.08)
                .offset(x: size * 0.30, y: -size * 0.04)
            cloud(w: size * 0.70, h: size * 0.22).opacity(0.07)
                .offset(x: size * 0.04, y: size * 0.32)
        }
        .blur(radius: size * 0.05)
    }

    /// A single cloud: a capsule body with a few overlapping round lobes on top.
    private func cloud(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            Capsule().frame(width: w, height: h)
            Circle().frame(width: h * 1.6, height: h * 1.6).offset(x: -w * 0.22, y: -h * 0.22)
            Circle().frame(width: h * 2.0, height: h * 2.0).offset(x: w * 0.06, y: -h * 0.30)
            Circle().frame(width: h * 1.5, height: h * 1.5).offset(x: w * 0.28, y: -h * 0.12)
        }
        .foregroundStyle(.white)
    }
}

/// A quiet support line pinned to the bottom of onboarding: the two handles are
/// tappable and open their X profiles in the default browser (the app's
/// `NSWorkspace.shared.open` pattern, as in Settings).
struct HelpFooter: View {
    var body: some View {
        HStack(spacing: 5) {
            Text("Need help? Reach out to")
                .foregroundStyle(AuraTheme.textTertiary)
            HelpHandle(label: "@akhil_bvs", url: "https://x.com/akhil_bvs")
            Text("or")
                .foregroundStyle(AuraTheme.textTertiary)
            HelpHandle(label: "@deveshb15", url: "https://x.com/deveshb15")
        }
        .font(.system(size: 11.5))
    }
}

/// A tappable X handle in the help footer: uses the app's rose accent, shows a
/// pointing-hand cursor on hover, and dims slightly while hovered.
private struct HelpHandle: View {
    let label: String
    let url: String
    @State private var hovering = false

    var body: some View {
        Button(label) {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(AuraTheme.accentDot)
        .opacity(hovering ? 0.78 : 1)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help("Open \(label) on X")
    }
}

/// A single keyboard-key chip, styled to match the dark Aura surfaces.
struct KeycapChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(AuraTheme.textPrimary)
            .frame(minWidth: 36, minHeight: 38)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AuraTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(AuraTheme.hairline, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                // A faint top highlight gives the key a slight physical lift.
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.06), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 12)
                    .padding(.horizontal, 1)
                    .padding(.top, 1)
                    .allowsHitTesting(false)
            }
    }
}

/// A horizontal hotkey combo like ⌥ ⌘ V.
struct KeycapCombo: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                KeycapChip(label: key)
            }
        }
    }
}

/// Primary call-to-action — a solid white pill with black text (matches the
/// "Keep" / "Save" buttons elsewhere in the app).
struct AuraPrimaryButtonStyle: ButtonStyle {
    var fill: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.vertical, 11)
            .padding(.horizontal, fill ? 0 : 24)
            .frame(maxWidth: fill ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Secondary / neutral button — a translucent hairline-bordered chip.
struct AuraSecondaryButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 14, weight: .medium))
            .foregroundStyle(AuraTheme.textPrimary)
            .padding(.vertical, compact ? 7 : 10)
            .padding(.horizontal, compact ? 14 : 18)
            .background(
                RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                    .stroke(AuraTheme.hairline, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
