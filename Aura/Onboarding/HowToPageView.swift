import SwiftUI

/// One page of the "how to" carousel: a rendered illustration on top, then a
/// serif title and a short description. Every illustration shares one visual
/// grammar — the real notch on top, the real app element below it — drawn in
/// SwiftUI (no screenshots) so they stay crisp and on-brand with the icon.
struct HowToPage: Identifiable {
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String

    enum Kind {
        case copy                       // notch + "keep this?" nudge card
        case library(keys: [String])    // notch + mini bento grid + hotkey
        case quickNote(keys: [String])  // notch + compose card + hotkey
        case drag                       // notch + items dragged up into it
    }

    static let all: [HowToPage] = [
        HowToPage(
            kind: .copy,
            title: "Copy anything",
            detail: "Copy text, a link, or an image and a card nudges out of the notch. Click Keep to save it — ignore it and it slips away."
        ),
        HowToPage(
            kind: .library(keys: ["⌥", "⌘", "V"]),
            title: "Open your library",
            detail: "Press ⌥⌘V from anywhere to open your library and search everything you've saved."
        ),
        HowToPage(
            kind: .quickNote(keys: ["⌃", "⌘", "N"]),
            title: "Jot a quick note",
            detail: "Press ⌃⌘N to write a quick note right in the notch. Hit return and it lands in your Notes."
        ),
        HowToPage(
            kind: .drag,
            title: "Drag to save",
            detail: "Drag files, links, or images onto the notch to drop them straight into your vault."
        )
    ]
}

struct HowToPageView: View {
    let page: HowToPage

    var body: some View {
        VStack(spacing: 28) {
            illustration
                .frame(height: 210)
                .frame(maxWidth: .infinity)

            VStack(spacing: 12) {
                Text(page.title)
                    .font(AuraFont.serif(30, .semibold, .tall))
                    .foregroundStyle(AuraTheme.textPrimary)

                Text(page.detail)
                    .font(.system(size: 14.5))
                    .foregroundStyle(AuraTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }
        }
        .padding(.horizontal, 56)
        .padding(.top, 36)
    }

    @ViewBuilder
    private var illustration: some View {
        switch page.kind {
        case .copy:                  CopyScene()
        case .library(let keys):     LibraryScene(keys: keys)
        case .quickNote(let keys):   QuickNoteScene(keys: keys)
        case .drag:                  DragScene()
        }
    }
}

// MARK: - Shared stage

/// The stylized MacBook notch with two tiny sprite eyes — echoes the real notch
/// using `NotchShape`. Reused by every illustration so the set reads as one.
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

/// Copy → a "keep this?" card nudging out below the notch.
private struct CopyScene: View {
    var body: some View {
        NotchStage { nudgeCard }
    }

    private var nudgeCard: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AuraTheme.sky.opacity(0.18))
                .overlay(Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AuraTheme.sky))
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(Color.white.opacity(0.22)).frame(width: 78, height: 6)
                Capsule().fill(Color.white.opacity(0.12)).frame(width: 52, height: 6)
            }

            Spacer(minLength: 6)

            Text("Keep")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(.white))
        }
        .padding(12)
        .frame(width: 240)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AuraTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }
}

/// Open library → a mini bento grid (what ⌥⌘V opens) over the hotkey.
private struct LibraryScene: View {
    let keys: [String]

    // Staggered heights per column so the grid reads as masonry.
    private let columns: [[CGFloat]] = [[34, 22], [26, 30], [20, 36]]

    var body: some View {
        NotchStage {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(columns.indices, id: \.self) { col in
                        VStack(spacing: 8) {
                            ForEach(columns[col].indices, id: \.self) { row in
                                tile(height: columns[col][row],
                                     accent: col == 1 && row == 0)
                            }
                        }
                    }
                }
                .frame(width: 168)

                KeycapCombo(keys: keys)
            }
        }
    }

    private func tile(height: CGFloat, accent: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(accent ? AuraTheme.sky.opacity(0.20) : AuraTheme.surface)
            .frame(width: 44, height: height)
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(AuraTheme.hairline, lineWidth: 1))
    }
}

/// Quick note → the notch's compose card with a blinking caret, over the hotkey.
private struct QuickNoteScene: View {
    let keys: [String]
    @State private var caretOn = true

    var body: some View {
        NotchStage {
            VStack(spacing: 16) {
                composeCard
                KeycapCombo(keys: keys)
            }
        }
    }

    private var composeCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Capsule().fill(Color.white.opacity(0.22)).frame(width: 152, height: 6)
            Capsule().fill(Color.white.opacity(0.16)).frame(width: 122, height: 6)
            HStack(spacing: 4) {
                Capsule().fill(Color.white.opacity(0.12)).frame(width: 64, height: 6)
                RoundedRectangle(cornerRadius: 1)
                    .fill(AuraTheme.sky)
                    .frame(width: 2, height: 13)
                    .opacity(caretOn ? 1 : 0)
            }
        }
        .padding(14)
        .frame(width: 212, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AuraTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                caretOn = false
            }
        }
    }
}

/// Drag → file / link / image chips lifting up into the notch.
private struct DragScene: View {
    var body: some View {
        NotchStage { dragItems }
    }

    private var dragItems: some View {
        HStack(spacing: 14) {
            dragChip("doc.fill", AuraTheme.sky)
            dragChip("link", Color(hex: "#43C6AC")!)
            dragChip("photo.fill", Color.white.opacity(0.9))
        }
        .overlay(alignment: .top) {
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AuraTheme.sky.opacity(0.8))
                .offset(y: -26)
        }
    }

    private func dragChip(_ symbol: String, _ tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(AuraTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
            .overlay(Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint))
            .frame(width: 56, height: 56)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}
