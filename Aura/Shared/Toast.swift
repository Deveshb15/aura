import SwiftUI
import Observation

/// A transient confirmation banner shown over the Library window. A small value
/// type describing the message; `ToastCenter` owns presentation + auto-dismiss
/// so any surface can fire one with a single call.
struct AuraToast: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var subtitle: String?
    var symbol: String = "checkmark"
}

/// Holds the one toast currently on screen and dismisses it after a delay.
/// Injected into the Library window's environment (the only surface with room
/// for a banner); reusable for any future confirmation.
@MainActor
@Observable
final class ToastCenter {
    private(set) var current: AuraToast?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func show(_ toast: AuraToast, duration: Double = 3.5) {
        current = toast
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}

/// The toast pill: a neutral glyph + title/subtitle on a solid dark card with a
/// hairline border — the same treatment as the library's cards and answer
/// banner. Floated near the bottom of the window; tap to dismiss early.
struct ToastView: View {
    let toast: AuraToast
    var onTap: () -> Void = {}

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: toast.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AuraTheme.textPrimary)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(AuraTheme.textPrimary)
                if let subtitle = toast.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AuraTheme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AuraTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AuraTheme.hairline))
        .shadow(color: AuraTheme.shadow, radius: 18, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { onTap() }
    }
}
