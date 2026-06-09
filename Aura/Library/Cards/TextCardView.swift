import SwiftUI

struct TextCardView: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.textContent ?? "")
                .font(.system(size: 15))
                .foregroundStyle(AuraTheme.textPrimary)
                .lineSpacing(2)
                .lineLimit(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let app = item.sourceApp {
                Text(app)
                    .font(.system(size: 11))
                    .foregroundStyle(AuraTheme.textTertiary)
            }
        }
        .padding(20)
    }
}
