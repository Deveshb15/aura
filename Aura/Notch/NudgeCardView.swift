import SwiftUI

/// A slim "keep this?" chip shown at the top of the expanded notch panel when a
/// just-copied item is pending. Click Keep to save it; ✕ to dismiss. (Replaces
/// the old auto-popping card — copies now just bounce the notch.)
struct KeepChipView: View {
    static let height: CGFloat = 50

    let item: NudgeItem
    let onKeep: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            thumb
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            Button(action: onKeep) {
                HStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 10, weight: .semibold))
                    Text("Keep").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.07)))
    }

    @ViewBuilder private var thumb: some View {
        switch item.preview {
        case .image(let image):
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        case .color(let hex):
            Color(hex: hex) ?? Color.gray
        default:
            ZStack {
                Color.white.opacity(0.12)
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    private var title: String {
        switch item.preview {
        case .text: return "Keep text"
        case .url: return "Keep link"
        case .image: return "Keep image"
        case .file(let name): return name
        case .color(let hex): return hex
        }
    }

    private var subtitle: String {
        switch item.preview {
        case .text(let value): return value
        case .url(let value): return value
        case .image: return "Just copied"
        case .file: return "File"
        case .color: return "Color"
        }
    }

    private var icon: String {
        switch item.preview {
        case .url: return "link"
        case .file: return "doc.fill"
        case .text: return "text.alignleft"
        default: return "square.on.square"
        }
    }
}
