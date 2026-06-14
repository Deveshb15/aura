import SwiftUI

/// Screen 2 — a horizontal "how to use" carousel. macOS has no paged `TabView`,
/// so this is a simple index-driven `HStack` that slides with the app's spring.
struct OnboardingCarousel: View {
    /// Called when the user finishes the final page ("Get Started").
    let onFinish: () -> Void

    private let pages = HowToPage.all
    private let pageWidth: CGFloat = 560
    @State private var index = 0

    var body: some View {
        VStack(spacing: 0) {
            // Sliding pages — each is full-width; the row is clipped to one page.
            HStack(spacing: 0) {
                ForEach(pages) { page in
                    HowToPageView(page: page)
                        .frame(width: pageWidth)
                }
            }
            .frame(width: pageWidth, alignment: .leading)
            .offset(x: -CGFloat(index) * pageWidth)
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: index)
            .frame(height: 430)
            .clipped()

            Spacer(minLength: 0)

            pageDots
                .padding(.bottom, 28)

            navRow
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
        }
        .frame(width: pageWidth, height: 640)
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(pages.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? AuraTheme.sky : Color.white.opacity(0.18))
                    .frame(width: i == index ? 18 : 6, height: 6)
                    .animation(.spring(response: 0.4, dampingFraction: 1.0), value: index)
                    .onTapGesture { index = i }
            }
        }
    }

    private var navRow: some View {
        HStack {
            Button("Back") { index = max(0, index - 1) }
                .buttonStyle(AuraSecondaryButtonStyle())
                .opacity(index == 0 ? 0 : 1)
                .disabled(index == 0)

            Spacer()

            if index == pages.count - 1 {
                Button("Get Started") { onFinish() }
                    .buttonStyle(AuraPrimaryButtonStyle())
            } else {
                Button("Next") { index += 1 }
                    .buttonStyle(AuraPrimaryButtonStyle())
            }
        }
    }
}
