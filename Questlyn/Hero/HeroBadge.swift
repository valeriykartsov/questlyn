import SwiftUI
import Domain

/// Значок состояния справа сверху от героя, напротив лица (макет 12D.5): 💧 интоксикация или ✨ Perfect.
/// Интоксикация важнее: при ней ✨ не показывается.
enum HeroBadge: String, Sendable {
    case intoxicated, perfect

    init?(_ vitals: VitalsState?) {
        guard let vitals else { return nil }
        if vitals.intoxication != nil { self = .intoxicated } else if vitals.isPerfect { self = .perfect } else { return nil }
    }

    var title: String { self == .intoxicated ? "Интоксикация" : "Perfect" }

    /// Пиксельный значок для карт и «Побродить»: капля 5×7 или искра 7×7.
    var pixels: [String] {
        switch self {
        case .intoxicated: ["..g..", ".gGg.", ".gGg.", "gGGWg", "gGGGg", "gGGGg", ".ggg."]
        case .perfect: ["...Y...", "...Y...", "..YWY..", "YYWWWYY", "..YWY..", "...Y...", "...Y..."]
        }
    }

    private static let palette: [Character: UInt32] = ["g": 0x2E7D4F, "G": 0x3FA65A, "W": 0xFFFCF6, "Y": 0xE2A04A]

    /// В пиксельный буфер карты: левый верхний угол значка.
    func draw(_ buffer: inout PixelBuffer, x: Int, y: Int) {
        for (row, line) in pixels.enumerated() {
            for (column, char) in line.enumerated() {
                if let color = Self.palette[char] { buffer.set(x + column, y + row, color) }
            }
        }
    }

    /// Картинка для SpriteKit и SwiftUI-карт.
    var image: CGImage? {
        let width = pixels.map(\.count).max() ?? 0
        var canvas = RGBACanvas(width: width, height: pixels.count, fill: nil)
        for (row, line) in pixels.enumerated() {
            for (column, char) in line.enumerated() {
                if let color = Self.palette[char] { canvas.set(column, row, color) }
            }
        }
        return canvas.image
    }
}

/// Значок в кружке — на «Герое», в редакторе и на виджете.
struct HeroBadgeView: View {
    let badge: HeroBadge
    var size: CGFloat = 24

    var body: some View {
        Group {
            switch badge {
            case .intoxicated:
                Image(systemName: "drop.fill").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(Color(hex: 0x3FA65A))
            case .perfect:
                Image(systemName: "sparkles").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(Color(hex: 0xE2A04A))
            }
        }
        .frame(width: size, height: size)
        .background(QColor.sheet, in: Circle())
        .overlay(Circle().strokeBorder(badge == .intoxicated ? Color(hex: 0x2E7D4F) : Color(hex: 0xE2A04A), lineWidth: 1.5))
        .accessibilityLabel(badge.title)
    }
}
