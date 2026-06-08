import SwiftUI

struct ColorCardView: View {
    let item: Item

    var body: some View {
        VStack(spacing: 0) {
            (Color(hex: item.colorHex ?? "") ?? Color.gray)
                .frame(height: 120)
            Text(item.colorHex ?? "—")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }
}
