import SwiftUI

/// Root of the first-launch onboarding. A two-step flow: the welcome screen
/// (logo + name + notifications) slides to the how-to carousel. Forces dark mode
/// and the Aura canvas so it reads identically regardless of system appearance.
struct OnboardingView: View {
    /// Called once the user finishes onboarding (final "Get Started").
    let onFinish: () -> Void

    private enum Step { case welcome, howTo }
    @State private var step: Step = .welcome

    var body: some View {
        ZStack {
            AuraTheme.background.ignoresSafeArea()

            if step == .welcome {
                WelcomeScreen(onContinue: {
                    withAnimation(.smooth(duration: 0.4)) { step = .howTo }
                })
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                OnboardingCarousel(onFinish: onFinish)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity))
            }
        }
        .frame(width: 560, height: 640)
        .preferredColorScheme(.dark)
    }
}
