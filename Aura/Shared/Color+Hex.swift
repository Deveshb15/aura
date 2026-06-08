import SwiftUI

extension Color {
    /// Creates a Color from a "#RRGGBB" / "#RRGGBBAA" / "#RGB" hex string.
    init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        if string.count == 3 {
            string = string.map { "\($0)\($0)" }.joined()
        }
        guard string.count == 6 || string.count == 8,
              let value = UInt64(string, radix: 16) else { return nil }

        let r, g, b, a: Double
        if string.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        } else {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
