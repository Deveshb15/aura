import SwiftUI

/// Quick-note composer embedded in the notch when compose mode is active.
/// Text state is owned by the caller via @Binding (stored in NotchStateModel)
/// so NotchController's key monitor can read it directly without a callback chain.
struct ComposeView: View {
    @Binding var text: String
    let onSave: (String) -> Void
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Text input ────────────────────────────────────────────────────
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Write a quick note…")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.25))
                        .padding(.top, 2)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.88))
                    .tint(.white.opacity(0.65))
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ── Divider ───────────────────────────────────────────────────────
            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(height: 0.5)

            // ── Action strip ──────────────────────────────────────────────────
            HStack(spacing: 0) {
                Text("⌘↩ save")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))
                Text("  esc dismiss")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.18))

                Spacer(minLength: 8)

                Button(action: { onSave(text) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Save")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(isEmpty ? .white.opacity(0.28) : .black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        isEmpty
                            ? AnyShapeStyle(.white.opacity(0.07))
                            : AnyShapeStyle(.white),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(isEmpty)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.50))
                        .frame(width: 22, height: 22)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .onAppear {
            // Small delay so the panel is key before SwiftUI sets first responder.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
    }
}
