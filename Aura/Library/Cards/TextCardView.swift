import SwiftUI

struct TextCardView: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.textContent ?? "")
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let app = item.sourceApp {
                Text(app)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
    }
}
