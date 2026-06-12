import SwiftUI
import AppKit

/// In-app note composer presented as a sheet over the Library window — used for
/// both creating a new text note and editing an existing `.text` item. Unlike
/// the notch's `ComposeView` (which relies on `NotchController`'s external
/// NSEvent monitor for ⌘↩), this lives in a normal key window and uses in-view
/// `.keyboardShortcut`. As you type, on-device AI (`ReminderDetector`) quietly
/// checks whether the note is a reminder and, if so, reveals an editable time
/// row to confirm — no separate reminder UI.
struct NoteComposerView: View {
    enum Mode: Equatable {
        case create
        case edit(Item)
        var isEdit: Bool { if case .edit = self { return true }; return false }
    }

    /// What the composer returns on save: the trimmed text plus an optional
    /// confirmed reminder time.
    struct Result { var text: String; var reminderAt: Date? }

    let mode: Mode
    let onSave: (Result) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @State private var reminderAt: Date?
    @State private var reminderDismissed: Bool   // user explicitly removed it → don't re-detect
    @State private var detecting = false
    @State private var notifDenied = false
    @FocusState private var editorFocused: Bool

    init(mode: Mode, onSave: @escaping (Result) -> Void, onCancel: @escaping () -> Void) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
        switch mode {
        case .create:
            _text = State(initialValue: "")
            _reminderAt = State(initialValue: nil)
        case .edit(let item):
            _text = State(initialValue: item.textContent ?? "")
            _reminderAt = State(initialValue: item.reminderAt)
        }
        _reminderDismissed = State(initialValue: false)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isEmpty: Bool { trimmed.isEmpty }

    /// Non-optional binding for the DatePicker, defaulting to tomorrow 9 AM.
    private var reminderBinding: Binding<Date> {
        Binding(get: { reminderAt ?? ReminderParser.defaultFireDate() },
                set: { reminderAt = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            editor
            if reminderAt != nil { reminderRow }
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
        .task(id: text) { await detectReminder() }
        .task(id: reminderAt != nil) {
            notifDenied = reminderAt != nil ? await ReminderScheduler.isDenied() : false
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text(mode.isEdit ? "Edit note" : "New note")
                .font(AuraFont.serif(20, .medium))
                .foregroundStyle(AuraTheme.textPrimary)
            Spacer()
            if detecting {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("Checking for a reminder…")
                        .font(.system(size: 11))
                        .foregroundStyle(AuraTheme.textTertiary)
                }
            }
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

    private var reminderRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AuraTheme.accentDot)
                Text("Remind me")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AuraTheme.textPrimary)
                Spacer()
                DatePicker("", selection: reminderBinding,
                           in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(AuraTheme.accentDot)
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        reminderAt = nil
                        reminderDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AuraTheme.textSecondary)
                        .frame(width: 20, height: 20)
                        .background(AuraTheme.surfaceHover, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Remove reminder")
            }
            if notifDenied {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text("Notifications are off — this won't alert you.")
                        .font(.system(size: 11))
                    Button("Open Settings") { openNotificationSettings() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AuraTheme.accentDot)
                }
                .foregroundStyle(AuraTheme.textTertiary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AuraTheme.background))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AuraTheme.hairline))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if reminderAt == nil {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        reminderDismissed = false
                        reminderAt = ReminderParser.defaultFireDate()
                    }
                } label: {
                    Label("Add reminder", systemImage: "bell")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AuraTheme.textSecondary)
                .help("Add a reminder")
            }
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
        onSave(Result(text: trimmed, reminderAt: reminderAt))
    }

    /// Debounced on-device detection. Only auto-adds a reminder when none is set
    /// and the user hasn't explicitly removed one, so a confirmed/edited time is
    /// never overwritten.
    private func detectReminder() async {
        guard reminderAt == nil, !reminderDismissed else { return }
        let snapshot = trimmed
        guard !snapshot.isEmpty else { return }
        try? await Task.sleep(nanoseconds: 800_000_000)   // debounce
        guard !Task.isCancelled else { return }

        detecting = true
        let parse = await ReminderDetector.detect(snapshot)
        detecting = false
        guard !Task.isCancelled else { return }

        if parse.isReminder, reminderAt == nil, !reminderDismissed {
            withAnimation(.easeOut(duration: 0.2)) {
                reminderAt = parse.date ?? ReminderParser.defaultFireDate()
            }
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}
