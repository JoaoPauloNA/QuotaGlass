import AppKit
import SwiftUI

struct ResetIndicatorStyle: Codable {
    var emoji: String = ""
    var colorHex: String? = nil
    var symbol: String { String(emoji.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)) }
    var color: Color? {
        guard let colorHex, colorHex.count == 6, let rgb = UInt32(colorHex, radix: 16) else { return nil }
        return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
    static func hex(_ color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
}

struct ResetIndicators: View {
    let count: Int?
    var style = ResetIndicatorStyle()
    var showsOutline = true
    private var available: Int { max(0, min(10000, count ?? 0)) }
    private var visibleLimit: Int { style.symbol.isEmpty ? 5 : 3 }
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<min(available, visibleLimit), id: \.self) { _ in
                if style.symbol.isEmpty {
                    Circle().strokeBorder(lineWidth: 1.5).frame(width: 10, height: 10)
                } else {
                    let glyph = Text(style.symbol).font(.system(size: 12)).frame(width: 14, height: 14)
                    if let color = style.color {
                        ZStack {
                            ForEach(0..<9, id: \.self) { position in
                                if showsOutline && position != 4 {
                                    Color.black.frame(width: 14, height: 14).mask { glyph }
                                        .offset(x: CGFloat(position % 3 - 1) * 0.65,
                                                y: CGFloat(position / 3 - 1) * 0.65)
                                }
                            }
                            color.frame(width: 14, height: 14).mask { glyph }
                        }.frame(width: 14, height: 14)
                    } else { glyph }
                }
            }
            if available > visibleLimit {
                Text("+\(available - visibleLimit)").font(.system(size: 9, weight: .semibold))
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}
