import SwiftUI

/// Quick-note composer embedded in the notch when compose mode is active.
/// Text state is owned by the caller via @Binding (stored in NotchStateModel)
/// so NotchController's key monitor can read it directly without a callback chain.
struct ComposeView: View {
    @Binding var text: String
    let onSave: (String) -> Void
    let onBack: () -> Void

    @FocusState private var isFocused: Bool

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Back button ───────────────────────────────────────────────────
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AuraTheme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(AuraTheme.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Back")
            .padding(.leading, -8)   // sit closer to the panel edge, left of the text

            // ── Text input ────────────────────────────────────────────────────
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Write a quick note…")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AuraTheme.textTertiary)
                        .padding(.top, 2)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AuraTheme.textPrimary)
                    .tint(AuraTheme.accentDot)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ── Divider ───────────────────────────────────────────────────────
            Rectangle()
                .fill(AuraTheme.hairline)
                .frame(height: 0.5)

            // ── Action strip ──────────────────────────────────────────────────
            HStack(spacing: 0) {
                Text("↩ save")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AuraTheme.textTertiary)
                Text("  ⇧↩ newline")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AuraTheme.textTertiary)
                Text("  esc dismiss")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AuraTheme.textTertiary)

                Spacer(minLength: 8)

                Button(action: { onSave(text) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Save")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(isEmpty ? AuraTheme.textTertiary : AuraTheme.activePillLabel)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        isEmpty
                            ? AnyShapeStyle(AuraTheme.fill)
                            : AnyShapeStyle(AuraTheme.activePill),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 0)
        .onAppear {
            // Small delay so the panel is key before SwiftUI sets first responder.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
    }
}
