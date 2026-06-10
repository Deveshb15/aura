import SwiftUI

/// The peeking card that slides down from the notch the moment something is
/// copied — a small preview with a **Keep** button. Click Keep to save it; click
/// ✕ (or just ignore it) and it retracts after a few seconds without saving.
struct NudgeCardView: View {
    let item: NudgeItem
    let onKeep: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            thumb
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            Button(action: onKeep) {
                HStack(spacing: 5) {
                    Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 11, weight: .semibold))
                    Text("Keep").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 64)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08)))
        // The whole card is a keep target (the ✕ button dismisses first); this
        // also stops a card tap from falling through to "open library".
        .contentShape(Rectangle())
        .onTapGesture { onKeep() }
        .help("Click to keep")
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
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    private var title: String {
        switch item.preview {
        case .text: return "Text copied"
        case .url: return "Link copied"
        case .image: return "Image copied"
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
