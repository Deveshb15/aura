import SwiftUI

// Small reusable building blocks for the onboarding flow: keycap chips for
// rendering hotkeys (⌥⌘V / ⌃⌘N) and the two button styles used across screens.

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
