import SwiftUI
import AppKit

/// The license activation gate. Shared by two hosts: the first-run onboarding
/// `.license` step and the standalone `LicenseActivationController` window (the
/// returning-unlicensed / re-lock path). Styled to match `LaunchAtLoginScreen`.
///
/// `license` is passed explicitly (not via `@Environment`) so it works inside the
/// AppKit-hosted onboarding / gate windows without environment plumbing — SwiftUI
/// still observes the `@Observable` because `body` reads its properties.
struct LicenseActivationView: View {
    let license: LicenseManager
    /// Called once the license becomes active (advance onboarding / close gate).
    let onActivated: () -> Void
    /// The standalone gate shows a Quit affordance (it can't be closed otherwise);
    /// the onboarding step leaves it off (the app menu's ⌘Q covers it).
    var showsQuit: Bool = false

    @State private var key = ""
    @FocusState private var fieldFocused: Bool

    private var isActivating: Bool { license.status == .activating }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            icon.padding(.bottom, 28)
            heading.padding(.bottom, 26)
            form
            Spacer(minLength: 24)
            if showsQuit { quitButton.padding(.bottom, 8) }
        }
        .padding(.horizontal, 44)
        .frame(width: 560, height: 640)
        .background(AuraTheme.background)
        .onAppear {
            if license.isLicensed { onActivated() }
            fieldFocused = true
        }
        .onChange(of: license.status) { _, new in
            if new == .licensed { onActivated() }
        }
    }

    // MARK: - Icon + heading

    private var icon: some View {
        ZStack {
            SkyBackdrop(size: 240, intensity: 0.5)
            Image(systemName: "key.fill")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(AuraTheme.sky)
                .shadow(color: AuraTheme.sky.opacity(0.35), radius: 22, y: 6)
                .rotationEffect(.degrees(-30))
        }
        .frame(height: 140)
    }

    private var heading: some View {
        VStack(spacing: 10) {
            Text("Activate Carpet")
                .font(AuraFont.serif(30, .semibold, .tall))
                .foregroundStyle(AuraTheme.textPrimary)
            Text("Enter the license key from your purchase email to unlock Carpet on this Mac.")
                .font(.system(size: 14.5))
                .foregroundStyle(AuraTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: 14) {
            keyField

            Button(action: activate) {
                if isActivating {
                    ProgressView().controlSize(.small).tint(.black)
                } else {
                    Text("Activate")
                }
            }
            .buttonStyle(AuraPrimaryButtonStyle(fill: true))
            .disabled(isActivating || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let message = errorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(AuraTheme.destructive)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            Button("Buy a license") {
                NSWorkspace.shared.open(LicenseAPI.checkoutURL)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AuraTheme.sky)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: 360)
        .animation(.easeOut(duration: 0.18), value: errorMessage)
    }

    private var keyField: some View {
        HStack(spacing: 8) {
            TextField("XXXXXXXX-XXXX-XXXX", text: $key)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(AuraTheme.textPrimary)
                .tint(AuraTheme.accentDot)
                .focused($fieldFocused)
                .onSubmit(activate)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AuraTheme.fillSubtle))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AuraTheme.hairline))

            Button("Paste", action: paste)
                .buttonStyle(AuraSecondaryButtonStyle(compact: true))
        }
    }

    private var quitButton: some View {
        Button("Quit Carpet") { NSApp.terminate(nil) }
            .buttonStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(AuraTheme.textTertiary)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }

    // MARK: - Actions

    private func activate() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isActivating else { return }
        Task { await license.activate(key: trimmed) }
    }

    private func paste() {
        guard let pasted = NSPasteboard.general.string(forType: .string) else { return }
        key = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Error copy

    private var errorMessage: String? {
        switch license.status {
        case .invalid(.badKey):
            return "That key doesn't look right. Check for extra spaces, or paste it again from your purchase email."
        case .invalid(.activationLimitReached):
            return "This license is already active on 3 Macs. Open Settings → License on one of them and deactivate it, then try again."
        case .invalid(.revoked):
            return "This license is no longer active. If you think that's a mistake, reach out to support."
        default:
            break
        }
        switch license.lastError {
        case .network:
            return "Couldn't reach the license server. Activation needs an internet connection — check your network and try again."
        case .server(let code):
            return "Activation failed (error \(code)). Please try again in a moment."
        default:
            return nil
        }
    }
}
