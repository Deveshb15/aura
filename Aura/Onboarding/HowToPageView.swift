import SwiftUI

/// One page of the "how to use" carousel: a rendered illustration on top, then a
/// serif title and a short description. Illustrations are drawn in SwiftUI (no
/// screenshots) so they stay crisp and on-brand with the vector icon.
struct HowToPage: Identifiable {
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String

    enum Kind {
        case copyNudge
        case hotkey(keys: [String], symbol: String)
        case reminder
        case dragSave
    }

    static let all: [HowToPage] = [
        HowToPage(
            kind: .copyNudge,
            title: "Copy anything",
            detail: "Copy text, a link, or an image and a card nudges out of the notch. Click Keep to save it — ignore it and it slips away."
        ),
        HowToPage(
            kind: .hotkey(keys: ["⌥", "⌘", "V"], symbol: "tray.full.fill"),
            title: "Open your library",
            detail: "Press ⌥⌘V from anywhere to open your library and search everything you've saved."
        ),
        HowToPage(
            kind: .hotkey(keys: ["⌃", "⌘", "N"], symbol: "square.and.pencil"),
            title: "Jot a quick note",
            detail: "Press ⌃⌘N to write a quick note right in the notch. Hit return and it lands in your vault."
        ),
        HowToPage(
            kind: .reminder,
            title: "Reminders, just write them",
            detail: "Start a note with “remind me…” and Aura reads the time and sets a notification — “remind me to call mom tomorrow at 3pm” just works."
        ),
        HowToPage(
            kind: .dragSave,
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
        case .copyNudge:
            NotchMockView(mode: .nudge)
        case .hotkey(let keys, let symbol):
            HotkeyIllustration(keys: keys, symbol: symbol)
        case .reminder:
            ReminderMockView()
        case .dragSave:
            NotchMockView(mode: .drag)
        }
    }
}

/// A note card whose text reads "remind me…", with the parsed time shown as a
/// bell chip and a small notification banner floating above — conveying that
/// writing a reminder note sets an alert.
private struct ReminderMockView: View {
    var body: some View {
        ZStack {
            AuraGlow(size: 230, intensity: 0.46)

            VStack(spacing: 16) {
                notificationBanner

                VStack(alignment: .leading, spacing: 12) {
                    Text("Remind me to call mom\ntomorrow at 3pm")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(AuraTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 5) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Tomorrow 3:00 PM")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(AuraTheme.accentDot)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(AuraTheme.accentDot.opacity(0.16)))
                }
                .padding(16)
                .frame(width: 256, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AuraTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AuraTheme.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
            }
        }
    }

    private var notificationBanner: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AuraTheme.accentDot.opacity(0.22))
                .overlay(Image(systemName: "bell.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AuraTheme.accentDot))
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text("Reminder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AuraTheme.textPrimary)
                Capsule().fill(Color.white.opacity(0.16)).frame(width: 96, height: 5)
            }

            Spacer(minLength: 6)
        }
        .padding(10)
        .frame(width: 220)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AuraTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(AuraTheme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
    }
}

// MARK: - Illustrations

/// A stylized MacBook notch with either a "keep this?" card nudging out below it,
/// or items being dragged up into it. Echoes the real notch using `NotchShape`.
private struct NotchMockView: View {
    enum Mode { case nudge, drag }
    let mode: Mode

    var body: some View {
        ZStack {
            AuraGlow(size: 230, intensity: 0.5)

            VStack(spacing: 14) {
                // The notch silhouette with two tiny sprite eyes.
                NotchShape(bottomRadius: 13)
                    .fill(Color.black)
                    .frame(width: 168, height: 36)
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 11) {
                            eye
                            eye
                        }
                        .padding(.bottom, 9)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 3)

                Group {
                    switch mode {
                    case .nudge: nudgeCard
                    case .drag:  dragItems
                    }
                }
            }
        }
    }

    private var eye: some View {
        Capsule()
            .fill(Color.white.opacity(0.92))
            .frame(width: 6, height: 6)
    }

    private var nudgeCard: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AuraTheme.accentDot.opacity(0.22))
                .overlay(Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AuraTheme.accentDot))
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
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AuraTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AuraTheme.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }

    private var dragItems: some View {
        HStack(spacing: 14) {
            dragChip("doc.fill", Color(hex: "#5B7CFF")!)
            dragChip("link", Color(hex: "#43C6AC")!)
            dragChip("photo.fill", AuraTheme.accentDot)
        }
        .overlay(alignment: .top) {
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AuraTheme.textTertiary)
                .offset(y: -26)
        }
    }

    private func dragChip(_ symbol: String, _ tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(AuraTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(AuraTheme.hairline, lineWidth: 1)
            )
            .overlay(Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint))
            .frame(width: 56, height: 56)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

/// A big hotkey combo with the destination's SF Symbol floating above it.
private struct HotkeyIllustration: View {
    let keys: [String]
    let symbol: String

    var body: some View {
        ZStack {
            AuraGlow(size: 230, intensity: 0.42)

            VStack(spacing: 22) {
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(AuraTheme.textPrimary)
                    .shadow(color: AuraTheme.accentDot.opacity(0.3), radius: 14)

                KeycapCombo(keys: keys)
                    .scaleEffect(1.25)
            }
        }
    }
}

/// The soft blue→magenta aura that sits behind onboarding illustrations,
/// echoing the app icon's directional glow (cool upper-left, warm lower-right).
struct AuraGlow: View {
    var size: CGFloat = 260
    var intensity: Double = 0.5

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: "#5B7CFF")!.opacity(intensity), .clear],
                    center: .center, startRadius: 0, endRadius: size * 0.55))
                .frame(width: size, height: size)
                .offset(x: -size * 0.13, y: -size * 0.10)
            Circle()
                .fill(RadialGradient(
                    colors: [AuraTheme.accentDot.opacity(intensity), .clear],
                    center: .center, startRadius: 0, endRadius: size * 0.55))
                .frame(width: size, height: size)
                .offset(x: size * 0.13, y: size * 0.12)
        }
        .blur(radius: 42)
        .allowsHitTesting(false)
    }
}
