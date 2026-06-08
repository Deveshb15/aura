import SwiftUI

/// The single peeking card shown when something is copied. Click it to keep;
/// ignore it and it retracts after a few seconds without saving anything.
struct NudgeCardView: View {
    let nudge: NudgeItem
    let onKeep: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            thumb
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 30, height: 30)
                .background(.white, in: Circle())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onKeep() }
        .help("Click to keep")
    }

    @ViewBuilder private var thumb: some View {
        switch nudge.preview {
        case .image(let image):
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        case .color(let hex):
            Color(hex: hex) ?? Color.gray
        default:
            ZStack {
                Color.white.opacity(0.12)
                Image(systemName: icon).foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    private var title: String {
        switch nudge.preview {
        case .text: return "Text copied"
        case .url: return "Link copied"
        case .image: return "Image copied"
        case .file(let name): return name
        case .color(let hex): return hex
        }
    }

    private var subtitle: String {
        switch nudge.preview {
        case .text(let value): return value
        case .url(let value): return value
        case .image: return "Click to keep"
        case .file: return "File"
        case .color: return "Color"
        }
    }

    private var icon: String {
        switch nudge.preview {
        case .url: return "link"
        case .file: return "doc.fill"
        case .text: return "text.alignleft"
        default: return "square.on.square"
        }
    }
}
