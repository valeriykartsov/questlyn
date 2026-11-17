import Foundation
import Domain

/// Оружие героя (17.11.2026, макет HeroWeapons): только вид. Сетки — по прототипу Design/tools/weapons_mock.py.
/// Координаты — в рисунке героя 32×56, могут выходить за него (до 10 px с каждой стороны).
nonisolated enum WeaponArt {
    static let pad = 10

    struct Pixel: Sendable {
        let x: Int
        let y: Int
        let color: UInt32
    }

    private static let colors: [Character: UInt32] = [
        "K": 0x2A2320, "M": 0xA9B1BC, "m": 0x7C8592, "W": 0xF4EFE4, "B": 0x6B4A2E, "b": 0x8A5A34, "G": 0xD9A441, "R": 0xA8432F,
        "r": 0xC82C28, "s": 0xE86050, "d": 0x7A181A, "N": 0x1C181E, "Y": 0xC42828,
    ]

    /// Слои оружия: позади тела (копьё) и поверх него.
    static func layers(_ weapon: HeroAppearance.Weapon) -> (behind: [Pixel], front: [Pixel]) {
        // Сетки нарисованы под кисть (7–8, 31–32); руки — опущенные, как у «Ассасина»: кисть (8–9, 36–37).
        let shift = weapon == .daggers || weapon == .spear ? (0, 0) : (1, 5)
        var behind: [Pixel] = [], front: [Pixel] = []
        for (x, y, char, isBehind) in points(weapon) {
            guard let color = colors[char] else { continue }
            let pixel = Pixel(x: x + shift.0, y: y + shift.1, color: color)
            if isBehind { behind.append(pixel) } else { front.append(pixel) }
        }
        return (behind, front)
    }

    private static func points(_ weapon: HeroAppearance.Weapon) -> [(Int, Int, Character, Bool)] {
        var p: [(Int, Int, Character, Bool)] = []
        func put(_ x: Int, _ y: Int, _ c: Character) { p.append((x, y, c, false)) }
        func back(_ x: Int, _ y: Int, _ c: Character) { p.append((x, y, c, true)) }
        switch weapon {
        case .katana:
            // Короткая рукоять в кулаке, навершие, цуба под кулаком, красный клинок наружу и вниз, сужается к острию.
            for (x, y, c) in [(10, 29, "G"), (11, 28, "K"), (9, 30, "N"), (8, 31, "Y"), (7, 32, "N"), (6, 33, "Y"), (10, 30, "K"), (9, 29, "K")] as [(Int, Int, Character)] { put(x, y, c) }
            for (x, y) in [(3, 33), (7, 33), (5, 31), (5, 35), (3, 32), (7, 34), (4, 31), (6, 35), (2, 33), (6, 31)] { put(x, y, "K") }
            for (x, y) in [(5, 33), (4, 33), (6, 33), (5, 32), (5, 34), (4, 32), (6, 34), (4, 34), (6, 32)] { put(x, y, "G") }
            put(5, 33, "W")
            let n = 16
            for k in 1...n {
                let x = 4 - k, y = 34 + k
                if k <= n - 4 {
                    put(x - 1, y, "d"); put(x, y, "r"); put(x + 1, y, "s"); put(x - 2, y, "K"); put(x + 2, y, "K"); put(x + 1, y + 1, "K")
                } else if k <= n - 1 {
                    put(x, y, "r"); put(x + 1, y, "s"); put(x - 1, y, "K"); put(x + 2, y, "K"); put(x + 1, y + 1, "K")
                } else {
                    put(x, y, "s"); put(x - 1, y, "K"); put(x + 1, y, "K"); put(x, y + 1, "K")
                }
            }
        case .axe:
            for y in 12..<42 { put(6, y, "K"); put(7, y, y % 4 == 0 ? "B" : "b"); put(8, y, "K") }
            for y in 12..<22 {
                let w = 5 - abs(y - 16) / 2
                for x in 1..<6 where x >= 6 - w { put(x, y, x > 1 ? "M" : "W") }
                put(6 - w - 1, y, "K")
            }
        case .spear:
            // За спиной по диагонали, лезвием к земле: длинный лист внизу слева, конец древка над плечом.
            for k in 0..<26 {
                let x = 4 + k, y = 38 - k
                back(x, y, "b"); back(x, y + 1, "B"); back(x - 1, y, "K"); back(x + 1, y + 1, "K")
            }
            put(30, 12, "B"); put(31, 11, "K"); put(30, 11, "K")
            for (x, y, c) in [(4, 39, "G"), (3, 40, "G"), (5, 40, "R"), (4, 41, "R"), (2, 41, "R"), (3, 42, "R")] as [(Int, Int, Character)] { put(x, y, c) }
            let widths = [1, 2, 2, 3, 3, 3, 3, 2, 2, 2, 1, 1, 0]
            for k in 0..<13 {
                let cx = 2 - k * 7 / 10, cy = 42 + k, w = widths[k]
                for d in -w...w { put(cx + d, cy, d == 0 ? "W" : (d > 0 ? "M" : "m")) }
                put(cx - w - 1, cy, "K"); put(cx + w + 1, cy, "K")
            }
            put(-7, 55, "K")
        case .hammer:
            for y in 16..<44 { put(6, y, "K"); put(7, y, "B"); put(8, y, "K") }
            for y in 10..<18 { for x in 2..<13 {
                put(x, y, y == 10 || y == 17 || x == 2 || x == 12 ? "K" : (y == 11 ? "W" : (x > 8 ? "m" : "M")))
            } }
        case .daggers:
            for (hx, sx) in [(8, -1), (23, 1)] {
                put(hx, 36, "B"); put(hx, 37, "B"); put(hx - sx, 35, "G")
                put(hx + sx, 38, "G"); put(hx, 38, "G"); put(hx + 2 * sx, 38, "K")
                for k in 1..<8 {
                    let x = hx + sx * k, y = 38 + k
                    put(x, y, k < 6 ? "W" : "M"); put(x - sx, y, "m"); put(x + sx, y, "K"); put(x - sx, y + 1, "K")
                }
            }
        case .crossbow:
            for x in 0..<13 { put(x, 30, "K"); put(x, 31, "b"); put(x, 32, "B"); put(x, 33, "K") }
            for y in 25..<39 { put(1, y, (26...37).contains(y) ? "M" : "K"); put(2, y, "K") }
            for y in 26..<38 { put(3 + abs(y - 31) / 3, y, "W") }
            put(12, 29, "M"); put(13, 30, "M"); put(13, 31, "M")
        }
        return p
    }
}
