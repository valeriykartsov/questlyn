import SwiftUI
import Domain

/// Аура ранга (10.3, макет AuraTiers): пиксельное кольцо у ног и искры цвета ступени.
enum AuraArt {
    static func colors(_ tier: Int) -> (ring: UInt32, spark: UInt32)? {
        switch tier {
        case 1: (0x7FB069, 0xC8E6B0)
        case 2: (0x5B8FD6, 0x9EC1EE)
        case 3: (0x9B6FD6, 0xD2BCF2)
        case 4: (0xE2A04A, 0xF7D898)
        case 5: (0xF2D27A, 0xFFFFFF)
        default: nil
        }
    }

    static func title(_ tier: Int) -> String {
        ["без ауры", "зелёная", "синяя", "фиолетовая", "золотая", "сияющая"][min(max(tier, 0), 5)]
    }

    /// Точки кольца (эллипс) и искр относительно центра у ног; размер точки — `dot`.
    static func pixels(tier: Int, rx: Double, ry: Double) -> [(x: Double, y: Double, spark: Bool)] {
        guard tier > 0 else { return [] }
        var result: [(Double, Double, Bool)] = []
        let count = 22 + tier * 4
        for k in 0..<count {
            let a = Double(k) / Double(count) * 2 * .pi
            result.append((cos(a) * rx, sin(a) * ry, false))
        }
        let sparks: [(Double, Double)] = [(-0.9, -2.2), (0.85, -2.9), (-1.0, -1.0), (1.05, -1.4), (-0.4, -3.6), (0.5, -0.6), (0, -4.2)]
        for (sx, sy) in sparks.prefix(1 + tier) { result.append((sx * rx, sy * ry * 1.6, true)) }
        return result
    }

    /// Кольцо и искры в пиксельный буфер (миниатюра «Сегодня»).
    static func draw(_ buffer: inout PixelBuffer, tier: Int, centerX: Int, feetY: Int, rx: Double, ry: Double) {
        guard let colors = colors(tier) else { return }
        for point in pixels(tier: tier, rx: rx, ry: ry) {
            buffer.set(centerX + Int(point.x.rounded()), feetY + Int(point.y.rounded()), point.spark ? colors.spark : colors.ring)
        }
    }
}

/// Аура SwiftUI под героем: кольцо у ног и искры; при «Уменьшении движения» — без мерцания.
struct AuraView: View {
    let tier: Int
    /// Ширина кольца в точках.
    var width: CGFloat
    var dot: CGFloat = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = false

    var body: some View {
        if let colors = AuraArt.colors(tier) {
            let rx = Double(width / 2), ry = Double(width / 7)
            Canvas { context, size in
                let feet = CGPoint(x: size.width / 2, y: size.height - CGFloat(ry) - dot)
                for point in AuraArt.pixels(tier: tier, rx: rx, ry: ry) {
                    let rect = CGRect(x: feet.x + point.x - dot / 2, y: feet.y + point.y - dot / 2, width: point.spark ? dot * 1.5 : dot, height: point.spark ? dot * 1.5 : dot)
                    context.fill(Path(rect), with: .color(Color(hex: point.spark ? colors.spark : colors.ring)))
                }
            }
            .opacity(tier == 5 && !reduceMotion ? (glow ? 1 : 0.6) : 0.9)
            .onAppear {
                guard tier == 5, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { glow = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
