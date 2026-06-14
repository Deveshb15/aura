import SwiftUI
import AppKit

/// In-app note composer presented as a sheet over the Library window — used for
/// both creating a new text note and editing an existing `.text` item. Unlike
/// the notch's `ComposeView` (which relies on `NotchController`'s external
/// NSEvent monitor for ⌘↩), this lives in a normal key window and uses in-view
/// `.keyboardShortcut`.
struct NoteComposerView: View {
    enum Mode: Equatable {
        case create
        case edit(Item)
        var isEdit: Bool { if case .edit = self { return true }; return false }
    }

    /// What the composer returns on save: the trimmed note text.
    struct Result { var text: String }

    let mode: Mode
    let onSave: (Result) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var editorFocused: Bool

    init(mode: Mode, onSave: @escaping (Result) -> Void, onCancel: @escaping () -> Void) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
        switch mode {
        case .create:
            _text = State(initialValue: "")
        case .edit(let item):
            _text = State(initialValue: item.textContent ?? "")
        }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isEmpty: Bool { trimmed.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            editor
            footer
        }
        .padding(20)
        .frame(width: 460)
        .background(AuraTheme.surface)
        .preferredColorScheme(.dark)
        .onExitCommand { onCancel() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { editorFocused = true }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text(mode.isEdit ? "Edit note" : "New note")
                .font(AuraFont.serif(20, .medium))
                .foregroundStyle(AuraTheme.textPrimary)
            Spacer()
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Write a note…")
                    .font(.system(size: 14))
                    .foregroundStyle(AuraTheme.textTertiary)
                    .padding(.top, 8).padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: 14))
                .foregroundStyle(AuraTheme.textPrimary)
                .tint(AuraTheme.accentDot)
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .padding(6)
        }
        .frame(height: 160)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AuraTheme.background))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AuraTheme.hairline))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Cancel") { onCancel() }
                .keyboardShortcut(.cancelAction)
            Button(mode.isEdit ? "Save" : "Add note") { save() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(AuraTheme.accentDot)
        }
    }

    // MARK: - Actions

    private func save() {
        guard !isEmpty else { return }
        onSave(Result(text: trimmed))
    }
}
