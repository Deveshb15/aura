import SwiftUI

/// Brand switch for the in-app Settings screen: a pink-when-on capsule with a
/// sliding white knob, so toggles read as Aura's own rather than the stock
/// blue system control. The whole row is tappable, as in a settings list.
struct AuraToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)

            Capsule()
                .fill(configuration.isOn ? AuraTheme.accentDot : AuraTheme.fill)
                .frame(width: 42, height: 25)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .frame(width: 21, height: 21)
                        .shadow(color: AuraTheme.shadow, radius: 1.5, y: 1)
                        .offset(x: configuration.isOn ? 8.5 : -8.5)
                )
                .animation(.easeOut(duration: 0.16), value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
    }
}

extension ToggleStyle where Self == AuraToggleStyle {
    /// `Toggle(...).toggleStyle(.aura)`
    static var aura: AuraToggleStyle { AuraToggleStyle() }
}
