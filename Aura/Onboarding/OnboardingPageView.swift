import SwiftUI

/// One page of the onboarding pager: a rendered illustration on top, then a serif
/// title and a short description. Every illustration shares one visual grammar —
/// a soft sky glow with the real notch silhouette on top and a page-specific
/// element below it — drawn in SwiftUI (no screenshots) so it stays crisp and
/// on-brand with the app icon. Page 1 swaps the notch scene for the Carpet logo.
struct OnboardingPage: Identifiable {
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String

    enum Kind {
        case welcome      // Carpet logo + sky glow
        case drop         // media chips lifting up into the notch
        case remember     // an "Ask your Memory…" field + results surfacing
        case categorise   // content-type tab pills auto-sorting
    }

    static let all: [OnboardingPage] = [
        OnboardingPage(
            kind: .welcome,
            title: "Welcome to Carpet.",
            detail: "Your quiet little memory vault that lives in the notch."
        ),
        OnboardingPage(
            kind: .drop,
            title: "Drop to Save",
            detail: "Drag any media file into the notch — or copy it to save into the vault."
        ),
        OnboardingPage(
            kind: .remember,
            title: "Carpet remembers things.",
            detail: "Ask your vault a question and it resurfaces what you saved."
        ),
        OnboardingPage(
            kind: .categorise,
            title: "Auto Categorise",
            detail: "Carpet sorts everything into categories for you. Click the notch to dive in."
        )
    ]
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    /// True when this is the visible page — drives the staged entrance so each
    /// page reveals (and re-reveals) as it slides into view.
    var isActive: Bool = true

    @State private var shown = false

    var body: some View {
        VStack(spacing: 28) {
            illustration
                .frame(height: 210)
                .frame(maxWidth: .infinity)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.92)
                .animation(.spring(response: 0.55, dampingFraction: 0.82), value: shown)

            VStack(spacing: 12) {
                Text(page.title)
                    .font(AuraFont.serif(page.kind == .welcome ? 34 : 30, .semibold, .tall))
                    .foregroundStyle(AuraTheme.textPrimary)

                Text(page.detail)
                    .font(.system(size: 14.5))
                    .foregroundStyle(AuraTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .animation(.smooth(duration: 0.45).delay(0.12), value: shown)
        }
        .padding(.horizontal, 56)
        .padding(.top, 36)
        .onAppear { if isActive { shown = true } }
        .onChange(of: isActive) { _, active in shown = active }
    }

    @ViewBuilder
    private var illustration: some View {
        switch page.kind {
        case .welcome:    WelcomeHero()
        case .drop:       DropScene()
        case .remember:   RememberScene()
        case .categorise: CategoriseScene()
        }
    }
}

// MARK: - Shared stage

/// The stylized MacBook notch with two tiny sprite eyes — echoes the real notch
/// using `NotchShape`. Reused by every scene so the set reads as one.
private struct NotchSilhouette: View {
    var body: some View {
        NotchShape(bottomRadius: 13)
            .fill(Color.black)
            .frame(width: 168, height: 36)
            .overlay(alignment: .bottom) {
                HStack(spacing: 11) { eye; eye }
                    .padding(.bottom, 9)
            }
            .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
    }

    private var eye: some View {
        Capsule()
            .fill(Color.white.opacity(0.92))
            .frame(width: 6, height: 6)
    }
}

/// The common scaffold: a sky backdrop with the notch on top and a page-specific
/// element below it.
private struct NotchStage<Content: View>: View {
    var glow: CGFloat = 240
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            SkyBackdrop(size: glow, intensity: 0.5)
            VStack(spacing: 16) {
                NotchSilhouette()
                content
            }
        }
    }
}

// MARK: - Scenes

/// Welcome → the Carpet logo over a wide sky glow (no notch — this is the brand
/// hero). The page's staged entrance scales/fades it in.
private struct WelcomeHero: View {
    var body: some View {
        ZStack {
            SkyBackdrop(size: 300, intensity: 0.55)
            Image("CarpetLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .shadow(color: AuraTheme.sky.opacity(0.35), radius: 26, y: 6)
        }
    }
}

/// Drop to save → file / link / image chips lifting up into the notch on a slow
/// staggered loop, suggesting "drop these in."
private struct DropScene: View {
    @State private var lift = false

    var body: some View {
        NotchStage {
            HStack(spacing: 14) {
                chip("doc.fill", AuraTheme.sky, index: 0)
                chip("link", Color(hex: "#43C6AC")!, index: 1)
                chip("photo.fill", Color.white.opacity(0.9), index: 2)
            }
            .overlay(alignment: .top) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AuraTheme.sky.opacity(0.8))
                    .offset(y: -26)
                    .opacity(lift ? 1 : 0.35)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: lift)
            }
        }
        .onAppear { lift = true }
    }

    private func chip(_ symbol: String, _ tint: Color, index: Int) -> some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(AuraTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
            .overlay(Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint))
            .frame(width: 56, height: 56)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            .offset(y: lift ? -8 : 0)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                .delay(Double(index) * 0.14), value: lift)
    }
}

/// Carpet remembers → a mini "Ask your Memory…" field (echoing the library
/// search hero) with a blinking caret, and a couple of result rows surfacing
/// beneath it.
private struct RememberScene: View {
    @State private var caretOn = true
    @State private var surfaced = false

    var body: some View {
        NotchStage {
            VStack(spacing: 10) {
                askField
                VStack(spacing: 7) {
                    resultRow(width: 196, accent: true)
                    resultRow(width: 168, accent: false)
                }
                .opacity(surfaced ? 1 : 0)
                .offset(y: surfaced ? 0 : 10)
                .animation(.smooth(duration: 0.5).delay(0.25), value: surfaced)
            }
        }
        .onAppear {
            surfaced = true
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                caretOn = false
            }
        }
    }

    private var askField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AuraTheme.sky)
            Text("Ask your Memory…")
                .font(.system(size: 13))
                .foregroundStyle(AuraTheme.textTertiary)
            RoundedRectangle(cornerRadius: 1)
                .fill(AuraTheme.sky)
                .frame(width: 2, height: 14)
                .opacity(caretOn ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(width: 230)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(AuraTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }

    private func resultRow(width: CGFloat, accent: Bool) -> some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(accent ? AuraTheme.sky.opacity(0.22) : Color.white.opacity(0.10))
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(Color.white.opacity(0.20)).frame(width: width * 0.55, height: 5)
                Capsule().fill(Color.white.opacity(0.12)).frame(width: width * 0.36, height: 5)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(AuraTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }
}

/// Auto categorise → a small spread of saved items above a row of content-type
/// tab pills (styled like the library's tab bar) whose active pill cycles, as if
/// Carpet is sorting everything into place.
private struct CategoriseScene: View {
    @State private var active = 0

    private let tabs: [(symbol: String, label: String)] = [
        ("note.text", "Notes"),
        ("photo.fill", "Images"),
        ("link", "Links")
    ]

    // Staggered tile heights so the spread reads as a masonry of saved items.
    private let columns: [[CGFloat]] = [[30, 20], [22, 28], [18, 32]]

    var body: some View {
        NotchStage {
            VStack(spacing: 16) {
                grid
                pillRow
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(950))
                withAnimation(.easeOut(duration: 0.3)) {
                    active = (active + 1) % tabs.count
                }
            }
        }
    }

    private var grid: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(columns.indices, id: \.self) { col in
                VStack(spacing: 8) {
                    ForEach(columns[col].indices, id: \.self) { row in
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(AuraTheme.surface)
                            .frame(width: 40, height: columns[col][row])
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(AuraTheme.hairline, lineWidth: 1))
                    }
                }
            }
        }
    }

    private var pillRow: some View {
        HStack(spacing: 6) {
            ForEach(tabs.indices, id: \.self) { i in
                let isActive = i == active
                HStack(spacing: 5) {
                    Image(systemName: tabs[i].symbol)
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(tabs[i].label)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(isActive ? AuraTheme.activePillLabel : AuraTheme.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background {
                    if isActive { Capsule().fill(AuraTheme.activePill) }
                }
            }
        }
    }
}
