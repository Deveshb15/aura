import SwiftUI

/// Root of the first-launch onboarding. A two-step flow: a four-page pager
/// (welcome → drop to save → remembers → auto categorise) slides to a final
/// launch-at-login step ("Get Started"). Forces dark mode and the Aura canvas so
/// it reads identically regardless of system appearance.
struct OnboardingView: View {
    /// Drives the hard-paywall `.license` step (passed down to the gate view).
    let license: LicenseManager
    /// Called once the user finishes onboarding (final "Get Started").
    let onFinish: () -> Void

    private enum Step { case pager, license, launchAtLogin }
    @State private var step: Step = .pager

    var body: some View {
        ZStack {
            AuraTheme.background.ignoresSafeArea()

            switch step {
            case .pager:
                OnboardingCarousel(onContinue: { advance(to: .license) })
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .leading).combined(with: .opacity)))
            case .license:
                // Hard paywall: the user can't reach "Get Started" (which completes
                // onboarding and brings the app live) until the license activates.
                LicenseActivationView(license: license,
                                      onActivated: { advance(to: .launchAtLogin) })
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))
            case .launchAtLogin:
                LaunchAtLoginScreen(onFinish: onFinish)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity))
            }
        }
        .frame(width: 560, height: 640)
        .preferredColorScheme(.dark)
    }

    private func advance(to next: Step) {
        withAnimation(.smooth(duration: 0.4)) { step = next }
    }
}
