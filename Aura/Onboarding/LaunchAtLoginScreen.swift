import SwiftUI

/// Final onboarding step — a dedicated "one more thing" screen offering to start
/// Carpet automatically at login. The toggle defaults ON (opt-out): for an
/// always-on menu-bar vault that's the expected behavior, and it's what makes
/// the app come back after a restart. "Get Started" applies the choice through
/// `LaunchAtLogin` and finishes onboarding.
struct LaunchAtLoginScreen: View {
    /// Finishes onboarding (marks it complete and brings the app live).
    let onFinish: () -> Void

    /// Pre-checked — see the type doc. The user can switch it off here.
    @State private var enabled = true
    /// Staged reveal: 0 = nothing, 1 = icon + glow, 2 = heading, 3 = controls.
    @State private var reveal = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            icon
                .padding(.bottom, 30)

            heading
                .padding(.bottom, 30)

            controls

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 44)
        .frame(width: 560, height: 640)
        .task { await runEntrance() }
    }

    // MARK: - Icon + glow

    private var icon: some View {
        ZStack {
            SkyBackdrop(size: 260, intensity: 0.5)
                .scaleEffect(reveal >= 1 ? 1 : 0.4)
                .opacity(reveal >= 1 ? (reveal >= 3 ? 0.6 : 0.95) : 0)
                .animation(.smooth(duration: 0.6), value: reveal)

            Image(systemName: "sunrise.fill")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(AuraTheme.sky)
                .shadow(color: AuraTheme.sky.opacity(0.35), radius: 22, y: 6)
                .scaleEffect(reveal >= 1 ? 1 : 0.7)
                .offset(y: reveal >= 1 ? 0 : 30)
                .opacity(reveal >= 1 ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: reveal)
        }
        .frame(height: 150)
    }

    private var heading: some View {
        VStack(spacing: 10) {
            Text("Keep Carpet at the ready")
                .font(AuraFont.serif(30, .semibold, .tall))
                .foregroundStyle(AuraTheme.textPrimary)
            Text("Start Carpet automatically when you log in to your Mac, so your vault is always a glance away.")
                .font(.system(size: 14.5))
                .foregroundStyle(AuraTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .opacity(reveal >= 2 ? 1 : 0)
        .offset(y: reveal >= 2 ? 0 : 10)
        .animation(.smooth(duration: 0.42), value: reveal)
    }

    // MARK: - Controls (toggle + finish)

    private var controls: some View {
        VStack(spacing: 16) {
            toggleCard

            Button("Get Started") { finish() }
                .buttonStyle(AuraPrimaryButtonStyle(fill: true))
        }
        .frame(maxWidth: 360)
        .opacity(reveal >= 3 ? 1 : 0)
        .offset(y: reveal >= 3 ? 0 : 14)
        .animation(.smooth(duration: 0.42), value: reveal)
    }

    private var toggleCard: some View {
        Toggle(isOn: $enabled) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Launch at login")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(AuraTheme.textPrimary)
                Text("Opens automatically at startup")
                    .font(.system(size: 12))
                    .foregroundStyle(AuraTheme.textTertiary)
            }
        }
        .toggleStyle(.aura)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AuraTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AuraTheme.hairline))
    }

    // MARK: - Finish

    private func finish() {
        LaunchAtLogin.setEnabled(enabled)
        // Mirror the choice into the Settings toggle's store, and record that a
        // launch-at-login decision was made so the existing-user migration in
        // AppDelegate never overrides it.
        UserDefaults.standard.set(enabled, forKey: LaunchAtLogin.enabledDefaultsKey)
        UserDefaults.standard.set(true, forKey: LaunchAtLogin.configuredDefaultsKey)
        onFinish()
    }

    // MARK: - Animation

    @MainActor
    private func runEntrance() async {
        reveal = 1
        try? await Task.sleep(for: .milliseconds(520))
        reveal = 2
        try? await Task.sleep(for: .milliseconds(260))
        reveal = 3
    }
}
