import SwiftUI

struct URLCardView: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(height: 96)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? item.host ?? "Link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(item.host ?? item.textContent ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    private var icon: String {
        switch item.subtype {
        case .youtube: return "play.rectangle.fill"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .twitter: return "at"
        default: return "globe"
        }
    }

    private var gradient: [Color] {
        switch item.subtype {
        case .youtube: return [.red, .orange]
        case .github: return [Color(white: 0.3), Color(white: 0.1)]
        case .twitter: return [.blue, .cyan]
        default: return [.indigo, .purple]
        }
    }
}
