import SwiftUI
import AppKit

/// Screen 1 — the app logo animates in, then the greeting, an optional name
/// field, and a Continue button reveal in stages.
struct WelcomeScreen: View {
    /// Advances to the how-to carousel.
    let onContinue: () -> Void

    @AppStorage("userName") private var userName = ""

    /// Staged reveal: 0 = nothing, 1 = logo + glow, 2 = greeting, 3 = controls.
    @State private var reveal = 0
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)

            logo
                .padding(.bottom, 30)

            greeting
                .padding(.bottom, 30)

            controls

            Spacer(minLength: 30)
        }
        .padding(.horizontal, 44)
        .frame(width: 560, height: 640)
        .task { await runEntrance() }
    }

    // MARK: - Logo + glow

    private var logo: some View {
        ZStack {
            SkyBackdrop(size: 300, intensity: 0.55)
                .scaleEffect(reveal >= 1 ? 1 : 0.4)
                .opacity(reveal >= 1 ? (reveal >= 3 ? 0.6 : 0.95) : 0)
                .animation(.smooth(duration: 0.6), value: reveal)

            Image("CarpetLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)
                .shadow(color: AuraTheme.sky.opacity(0.35), radius: 26, y: 6)
                .scaleEffect(reveal >= 1 ? 1 : 0.7)
                .offset(y: reveal >= 1 ? 0 : 30)
                .opacity(reveal >= 1 ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: reveal)
        }
        .frame(height: 150)
    }

    private var greeting: some View {
        VStack(spacing: 10) {
            Text("Welcome to Carpet")
                .font(AuraFont.serif(36, .semibold, .tall))
                .foregroundStyle(AuraTheme.textPrimary)
            Text("Your quiet little vault that lives in the notch.")
                .font(.system(size: 14.5))
                .foregroundStyle(AuraTheme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .opacity(reveal >= 2 ? 1 : 0)
        .offset(y: reveal >= 2 ? 0 : 10)
        .animation(.smooth(duration: 0.42), value: reveal)
    }

    // MARK: - Controls (name + continue)

    private var controls: some View {
        VStack(spacing: 14) {
            nameField

            Button("Continue") { onContinue() }
                .buttonStyle(AuraPrimaryButtonStyle(fill: true))
                .padding(.top, 6)
        }
        .frame(maxWidth: 340)
        .opacity(reveal >= 3 ? 1 : 0)
        .offset(y: reveal >= 3 ? 0 : 14)
        .animation(.smooth(duration: 0.42), value: reveal)
    }

    private var nameField: some View {
        TextField("", text: $userName, prompt:
            Text("Your name (optional)").foregroundStyle(AuraTheme.textTertiary))
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(AuraTheme.textPrimary)
            .focused($nameFocused)
            .onSubmit { onContinue() }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AuraTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(nameFocused ? AuraTheme.sky.opacity(0.7) : AuraTheme.hairline,
                            lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.15), value: nameFocused)
    }

    // MARK: - Animation

    @MainActor
    private func runEntrance() async {
        reveal = 1
        try? await Task.sleep(for: .milliseconds(560))
        reveal = 2
        try? await Task.sleep(for: .milliseconds(260))
        reveal = 3
    }
}
