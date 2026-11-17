import CoreGraphics
import Foundation
import Domain

// Этап 15A.7 (макеты ExploreTowns, ExploreCharacters): дома по климатическим зонам, постройки города, деревья,
// корабль. Перенос прототипа Design/tools/explore15_sprites.py. Всё — свой пиксельный рисунок.

/// Цвета без изоляции — для фоновой отрисовки земли.
nonisolated enum Pix {
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        var result: UInt32 = 0
        for shift: UInt32 in [16, 8, 0] {
            let ca = Double((a >> shift) & 0xFF), cb = Double((b >> shift) & 0xFF)
            result |= UInt32(max(0, min(255, (ca + (cb - ca) * t).rounded()))) << shift
        }
        return result
    }

    static func shade(_ color: UInt32, _ factor: Double) -> UInt32 {
        var result: UInt32 = 0
        for shift: UInt32 in [16, 8, 0] {
            result |= UInt32(max(0, min(255, (Double((color >> shift) & 0xFF) * factor).rounded()))) << shift
        }
        return result
    }

    /// Псевдослучайное 0..<1 по координатам — одинаковое при каждой отрисовке.
    static func hash(_ x: Int, _ y: Int, _ k: Int = 0) -> Double {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ k &* 2_147_483_647)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Double(h ^ (h >> 16)) / Double(UInt32.max)
    }
}

extension RGBACanvas {
    /// Цвет пикселя; nil — прозрачный.
    nonisolated func color(_ x: Int, _ y: Int) -> UInt32? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let i = (y * width + x) * 4
        guard bytes[i + 3] > 0 else { return nil }
        return UInt32(bytes[i]) << 16 | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2])
    }

    /// Заливка многоугольника (точки — центры пикселей).
    nonisolated mutating func polygon(_ points: [(Int, Int)], _ color: UInt32) {
        guard points.count >= 3 else { return }
        let top = points.map(\.1).min()!, bottom = points.map(\.1).max()!
        for y in top...bottom {
            var xs: [Double] = []
            let sy = Double(y) + 0.5
            for k in points.indices {
                let (x1, y1) = points[k], (x2, y2) = points[(k + 1) % points.count]
                let a = Double(y1) + 0.5, b = Double(y2) + 0.5
                if (a <= sy && b > sy) || (b <= sy && a > sy) {
                    xs.append(Double(x1) + (sy - a) / (b - a) * Double(x2 - x1))
                }
            }
            xs.sort()
            var k = 0
            while k + 1 < xs.count {
                let from = Int(xs[k].rounded(.down)), to = Int(xs[k + 1].rounded(.down))
                if from <= to { for x in from...to { set(x, y, color) } }
                k += 2
            }
            // Вершины и горизонтальные рёбра.
            for (px, py) in points where py == y { set(px, py, color) }
        }
    }

    /// Наложить другой холст (непрозрачные пиксели) с левым верхним углом в (x, y).
    nonisolated mutating func draw(_ sprite: RGBACanvas, at x: Int, _ y: Int) {
        for sy in 0..<sprite.height { for sx in 0..<sprite.width {
            if let c = sprite.color(sx, sy) { set(x + sx, y + sy, c) }
        } }
    }

    /// Зеркало по горизонтали.
    nonisolated var mirrored: RGBACanvas {
        var out = RGBACanvas(width: width, height: height, fill: nil)
        for y in 0..<height { for x in 0..<width { if let c = color(x, y) { out.set(width - 1 - x, y, c) } } }
        return out
    }
}

nonisolated enum ExploreSprites {
    // MARK: Дома

    enum Roof { case hip, gable, flat }

    /// Изометрический дом: основание — ромб полуширины a, стены высоты h; дверь — на левой стене, окна — на правой.
    static func house(a: Int, h: Int, wallL: UInt32, wallR: UInt32, roof: UInt32, kind: Roof, rh: Int? = nil, logs: Bool = false,
                      snow: Bool = false, chimney: Bool = false, trim: UInt32? = nil, door: UInt32 = 0x5C3A1E) -> RGBACanvas {
        let rh = rh ?? a / 2 + 3
        var c = RGBACanvas(width: 2 * a + 6, height: h + a + rh + 10, fill: nil)
        let cx = a + 3, base = c.height - 2
        let L = (cx - a, base - a / 2), R = (cx + a, base - a / 2), F = (cx, base)
        func up(_ p: (Int, Int), _ k: Int) -> (Int, Int) { (p.0, p.1 - k) }
        c.polygon([L, F, up(F, h), up(L, h)], wallL)
        c.polygon([F, R, up(R, h), up(F, h)], wallR)
        func wallY(_ x: Int) -> Int { x <= cx ? L.1 + (x - L.0) / 2 : F.1 - (x - cx) / 2 }
        if logs {
            for k in stride(from: 2, to: h, by: 3) { for x in L.0...R.0 {
                c.set(x, wallY(x) - k, Pix.shade(x <= cx ? wallL : wallR, 0.78))
            } }
        }
        for k in 0..<min(6, h - 2) { for dx in 0..<2 {
            let x = cx - a / 2 - 1 + dx
            c.set(x, wallY(x) - k, door)
        } }
        for wx in [cx + a / 3, cx + 2 * a / 3 + 1] { for k in (h / 2)..<(h / 2 + 3) { for dx in 0..<2 {
            c.set(wx + dx, wallY(wx + dx) - k, 0x5C6B7A)
        } } }
        if let trim { for x in L.0...R.0 { c.set(x, wallY(x) - h, trim) } }
        let T = up(F, h), TL = up(L, h), TR = up(R, h), TB = (cx, base - a - h)
        let e = 2
        let TLe = (TL.0 - e, TL.1), TRe = (TR.0 + e, TR.1), TFe = (T.0, T.1 + 1)
        let roofDark = Pix.shade(roof, 0.78)
        switch kind {
        case .hip:
            let apex = (cx, base - a / 2 - h - rh)
            c.polygon([TLe, TFe, apex], roof)
            c.polygon([TFe, TRe, apex], roofDark)
            if snow {
                let line = apex.1 + rh * 13 / 20
                for y in 0..<line { for x in 0..<c.width {
                    if let p = c.color(x, y), p == roof || p == roofDark { c.set(x, y, p == roof ? 0xF2F4F6 : 0xD5DCE2) }
                } }
            }
        case .gable:
            let r1 = (TL.0 + a / 2, TL.1 - a / 4 - rh), r2 = (T.0 + a / 2, T.1 - a / 4 - rh)
            c.polygon([TLe, TFe, r2, r1], roof)
            c.polygon([TFe, TRe, r2], Pix.shade(wallR, 0.95))
            c.polygon([r1, r2, TRe, (TB.0 + e, TB.1)], Pix.shade(roof, 0.8))
            if snow {
                for y in 0..<c.height { for x in 0..<c.width where c.color(x, y) == roof && Pix.hash(x, y, 3) < 0.85 { c.set(x, y, 0xF2F4F6) } }
            }
        case .flat:
            c.polygon([TL, T, TR, TB], Pix.shade(wallL, 1.08))
            for x in TL.0...TR.0 {
                let y = x <= cx ? TL.1 + (x - TL.0) / 2 : T.1 - (x - cx) / 2
                c.set(x, y - 1, Pix.shade(x <= cx ? wallL : wallR, 0.9))
                c.set(x, y - 2, Pix.shade(x <= cx ? wallL : wallR, 0.9))
            }
        }
        if chimney {
            let x0 = cx + a / 2, y0 = base - a / 2 - h - rh + 3
            for y in (y0 - 5)...(y0 + 1) { for x in x0..<(x0 + 3) { c.set(x, y, x < x0 + 2 ? 0x8A7A6A : 0x6E6054) } }
        }
        return c
    }

    static func yurt() -> RGBACanvas {
        let r = 9, h = 8, felt: UInt32 = 0xE9DCC0, band: UInt32 = 0xB8651B
        var c = RGBACanvas(width: 2 * r + 6, height: h + r + 12, fill: nil)
        let cx = r + 3, base = c.height - 3
        for y in (base - h - r / 2)...(base - r / 4) { for x in (cx - r)...(cx + r) { c.set(x, y, felt) } }
        for y in (base - r / 2)...(base + 1) { for x in (cx - r)...(cx + r) {
            let dx = Double(x - cx) / Double(r), dy = Double(y - (base - r / 4)) / Double(r / 2 + 1)
            if dx * dx + dy * dy <= 1 { c.set(x, y, felt) }
        } }
        c.polygon([(cx - r - 1, base - h - r / 3), (cx + r + 1, base - h - r / 3), (cx, base - h - r - 2)], Pix.shade(felt, 0.9))
        for y in 0..<c.height { for x in (cx + 1)...(cx + r + 1) { if let p = c.color(x, y) { c.set(x, y, Pix.shade(p, 0.86)) } } }
        for x in (cx - r)...(cx + r) {
            c.set(x, base - h + 1 - abs(x - cx) / 4, band)
            c.set(x, base - h + 2 - abs(x - cx) / 4, band)
        }
        for k in 0..<5 { c.set(cx - 2, base - k, 0x5C3A1E); c.set(cx - 1, base - k, 0x5C3A1E) }
        c.set(cx, base - h - r - 2, 0x6B4A2E)
        return c
    }

    static func domeHouse() -> RGBACanvas {
        let a = 8, h = 9
        var c = house(a: a, h: h, wallL: 0xE2C69A, wallR: 0xC9A97A, roof: 0xE2C69A, kind: .flat, door: 0x6E4529)
        let cx = a + 3, top = c.height - 2 - a / 2 - h
        let rx = Double(a / 2 + 1), ry = Double(a / 2 + 2)
        for y in (top - a / 2 - 3)...(top + 2) { for x in (cx - a / 2 - 1)...(cx + a / 2 + 1) {
            let dx = Double(x - cx) / rx, dy = Double(y - (top - 1)) / ry
            if dx * dx + dy * dy <= 1 { c.set(x, y, x > cx ? 0xD9C49E : 0xF0E2C4) }
        } }
        return c
    }

    /// Два вида дома для зоны.
    static func houses(_ zone: ClimateZone) -> [RGBACanvas] {
        switch zone {
        case .tundra:
            [house(a: 8, h: 9, wallL: 0x8A6A4A, wallR: 0x6E5238, roof: 0x6E4529, kind: .hip, logs: true, snow: true, chimney: true),
             house(a: 7, h: 8, wallL: 0x8A6A4A, wallR: 0x6E5238, roof: 0x6E4529, kind: .gable, logs: true, snow: true)]
        case .taiga:
            [house(a: 8, h: 10, wallL: 0x9A7450, wallR: 0x7A5A3E, roof: 0x4E5A3A, kind: .gable, logs: true, chimney: true),
             house(a: 7, h: 8, wallL: 0x9A7450, wallR: 0x7A5A3E, roof: 0x6E4529, kind: .hip, logs: true)]
        case .temperate:
            [house(a: 8, h: 11, wallL: 0xEDE3CC, wallR: 0xD3C6A8, roof: 0xB8651B, kind: .gable, chimney: true, trim: 0x6E4529),
             house(a: 7, h: 9, wallL: 0xEDE3CC, wallR: 0xD3C6A8, roof: 0x3E5C8A, kind: .hip, trim: 0x6E4529)]
        case .steppe:
            [yurt(), house(a: 7, h: 8, wallL: 0xD9C7A0, wallR: 0xBDA982, roof: 0x9C8E4E, kind: .hip)]
        case .desert:
            [domeHouse(), house(a: 7, h: 8, wallL: 0xE2C69A, wallR: 0xC9A97A, roof: 0xE2C69A, kind: .flat, door: 0x6E4529)]
        }
    }

    // MARK: Город

    static func well() -> RGBACanvas {
        var c = RGBACanvas(width: 14, height: 18, fill: nil)
        for y in 9...16 { for x in 1...12 {
            let dx = (Double(x) - 6.5) / 5.5, dy = (Double(y) - 12.5) / 3.5
            if dx * dx + dy * dy <= 1 { c.set(x, y, 0x8E8574) }
        } }
        for y in 10...14 { for x in 3...10 {
            let dx = (Double(x) - 6.5) / 3.5, dy = (Double(y) - 12) / 2
            if dx * dx + dy * dy <= 1 { c.set(x, y, 0x2B5884) }
        } }
        for y in 4...12 { c.set(1, y, 0x6E4529); c.set(2, y, 0x6E4529); c.set(11, y, 0x6E4529); c.set(12, y, 0x6E4529) }
        c.polygon([(0, 5), (7, 0), (13, 5)], 0xB8651B)
        return c
    }

    static func stall(_ color: UInt32) -> RGBACanvas {
        var c = RGBACanvas(width: 18, height: 18, fill: nil)
        for y in 10...16 { for x in 2...15 { c.set(x, y, 0x9A7450) } }
        for x in 2...15 { c.set(x, 9, 0xD9A441); c.set(x, 10, 0xD9A441) }
        for y in 3..<8 { for x in 1..<17 { c.set(x, y, (x / 3) % 2 == 1 ? color : 0xF4EFE4) } }
        for y in 7...16 { c.set(2, y, 0x5C3A1E); c.set(15, y, 0x5C3A1E) }
        return c
    }

    static func temple(_ zone: ClimateZone) -> RGBACanvas {
        let roof: UInt32 = zone == .tundra ? 0x6E4529 : zone == .desert ? 0xF0E2C4 : 0x3E5C8A
        var c = house(a: 7, h: 22, wallL: 0xD8D0C0, wallR: 0xB8AE9C, roof: roof, kind: .hip, rh: 12, snow: zone == .tundra, door: 0x4E3A2A)
        c.set(c.width / 2, 1, 0xD9A441)
        c.set(c.width / 2, 2, 0xD9A441)
        return c
    }

    static func boardPost() -> RGBACanvas {
        var c = RGBACanvas(width: 12, height: 16, fill: nil)
        for y in 7...15 { for x in [2, 3, 8, 9] { c.set(x, y, 0x5C3A1E) } }
        for y in 1...9 { for x in 0...11 { c.set(x, y, 0x9A7450) } }
        for y in 3...6 { for x in 2...5 { c.set(x, y, 0xF4EFE4) } }
        for y in 2...5 { for x in 7...9 { c.set(x, y, 0xF4EFE4) } }
        c.set(3, 4, 0x1F2A44)
        c.set(8, 3, 0x1F2A44)
        return c
    }

    static func stake() -> RGBACanvas {
        var c = RGBACanvas(width: 3, height: 12, fill: nil)
        for y in 2..<12 { c.set(0, y, 0x8A6A4A); c.set(1, y, 0x6E5238) }
        c.set(0, 1, 0x8A6A4A)
        return c
    }

    // MARK: Деревья по зонам

    static func tree(_ zone: ClimateZone, dark: Bool) -> RGBACanvas {
        var c = RGBACanvas(width: 11, height: 14, fill: nil)
        let x = 5, y = 13
        let trunk: UInt32 = 0x5C3A1E
        switch zone {
        case .tundra, .taiga:
            let leaf: UInt32 = zone == .tundra ? (dark ? 0x27403A : 0x2F4A3E) : (dark ? 0x264E36 : 0x2E5A3E)
            for k in 0..<2 { c.set(x, y - k, trunk) }
            for dy in 0..<9 {
                let half = dy / 2
                for dx in -half...half {
                    var col = dx > 0 ? Pix.shade(leaf, 0.88) : leaf
                    if zone == .tundra && (dy % 3 == 0 || (dx == -half && Pix.hash(x + dx, dy, 41) < 0.5)) { col = 0xF2F4F6 }
                    c.set(x + dx, y - 11 + dy, col)
                }
            }
        case .temperate:
            let leaf: UInt32 = dark ? 0x335C26 : 0x3E6B2E
            for k in 0..<3 { c.set(x, y - k, trunk) }
            for dy in 0..<5 {
                let half = dy < 3 ? dy + 1 : 5 - dy
                for dx in -half...half {
                    var col = leaf
                    if dx < 0 && dy < 2 { col = Pix.mix(leaf, 0xFFFFFF, 0.18) }
                    if dx > 0 && dy > 2 { col = Pix.shade(leaf, 0.85) }
                    c.set(x + dx, y - 7 + dy, col)
                }
            }
        case .steppe:
            let leaf: UInt32 = dark ? 0x6E7A3C : 0x7E8A46
            for dy in 0..<3 { for dx in (-2 + (dy == 0 ? 1 : 0))...(2 - (dy == 0 ? 1 : 0)) { c.set(x + dx, y - dy, leaf) } }
        case .desert:
            let leaf: UInt32 = dark ? 0x4E7A3E : 0x5E8A4A
            for dy in 0..<7 { c.set(x, y - dy, leaf) }
            for dy in 0..<3 { c.set(x - 2, y - 3 - dy, leaf); c.set(x + 2, y - 2 - dy, leaf) }
            c.set(x - 1, y - 3, leaf)
            c.set(x + 1, y - 2, leaf)
        }
        return c
    }

    // MARK: 15B, 15G: башня босса, памятники, монументы, флажок, засохшее дерево

    /// Финальная Чёрная башня (15G.2): выше обычной, красная крыша и окна.
    static func bossTower(conquered: Bool) -> RGBACanvas {
        var c = RGBACanvas(width: 34, height: 64, fill: nil)
        let wall: UInt32 = conquered ? 0x5C5C66 : 0x1B1B22, shadow: UInt32 = conquered ? 0x4A4A54 : 0x14141A
        let roof: UInt32 = conquered ? 0xD9A441 : 0x7A2E2E, glow: UInt32 = conquered ? 0xF2D27A : 0xE5482B
        for y in 14...60 { for x in 7...27 { c.set(x, y, x >= 17 ? shadow : wall) } }
        for x in stride(from: 7, through: 25, by: 5) { for y in 8...14 { for dx in 0...2 { c.set(x + dx, y, wall) } } }
        c.polygon([(5, 14), (17, 0), (29, 14)], roof)
        for y in 46...60 { for x in 14...20 { c.set(x, y, 0x7A2E2E) } }
        for (x, y) in [(11, 24), (21, 24), (16, 34)] { for dy in 0...3 { for dx in 0...2 { c.set(x + dx, y + dy, glow) } } }
        return c
    }

    /// Памятник закрытого Epic (15B.2); в пустыне — руины.
    static func epicMonument(ruin: Bool) -> RGBACanvas {
        var c = RGBACanvas(width: 26, height: 40, fill: nil)
        c.polygon([(1, 34), (13, 39), (25, 34), (13, 29)], 0x969084)
        if ruin {
            for y in 20...34 { for x in 5...9 { c.set(x, y, 0xC9A57A) } }
            for y in 14...34 { for x in 17...21 { c.set(x, y, 0xB88E62) } }
            for y in 12...14 { for x in 15...23 { c.set(x, y, 0xA8865E) } }
            for y in 30...33 { for x in 9...15 { c.set(x, y, 0xB88E62) } }
        } else {
            for y in 8...33 { for x in 8...18 { c.set(x, y, x >= 13 ? 0xBAB4A8 : 0xD6D0C4) } }
            c.polygon([(8, 8), (13, 2), (18, 8)], 0xD9A441)
            for y in 18...20 { for x in 10...16 { c.set(x, y, 0x1F2A44) } }
        }
        return c
    }

    /// Монумент полезного (15G.4): постамент и символ вида.
    static func shrine(_ buff: ExploreBuff) -> RGBACanvas {
        var c = RGBACanvas(width: 20, height: 30, fill: nil)
        c.polygon([(2, 24), (10, 28), (18, 24), (10, 20)], 0x969084)
        for y in 12...24 { for x in 5...15 { c.set(x, y, x >= 10 ? 0xA8A296 : 0xC4BEB0) } }
        for y in 10...12 { for x in 4...16 { c.set(x, y, 0x8C867A) } }
        switch buff {
        case .water: c.polygon([(10, 1), (14, 7), (10, 9), (6, 7)], 0x3E6FA3)
        case .walk:
            for y in 4...6 { for x in 7...13 { c.set(x, y, 0x2F6B4F) } }
            for y in 1...9 { for x in 9...11 { c.set(x, y, 0x2F6B4F) } }
        case .stretch:
            for k in 0..<24 {
                let a = Double(k) / 24 * 2 * .pi
                c.set(10 + Int((cos(a) * 3.5).rounded()), 5 + Int((sin(a) * 3).rounded()), 0xB8651B)
                c.set(10 + Int((cos(a) * 2.5).rounded()), 5 + Int((sin(a) * 2).rounded()), 0xB8651B)
            }
        case .vegetables:
            for y in 3...10 { for x in 6...14 where hypot(Double(x) - 10, Double(y) - 6.5) <= 3.8 { c.set(x, y, 0xA8432F) } }
            c.set(11, 2, 0x2F6B4F); c.set(12, 1, 0x2F6B4F)
        case .nap:
            for y in 2...9 { for x in 6...14 where hypot(Double(x) - 10, Double(y) - 5.5) <= 3.8 && hypot(Double(x) - 12.5, Double(y) - 4) > 3 { c.set(x, y, 0x6B4FA3) } }
        case .custom:
            c.polygon([(10, 1), (12, 5), (16, 5), (13, 8), (14, 11), (10, 9), (6, 11), (7, 8), (4, 5), (8, 5)], 0xD9A441)
        }
        return c
    }

    /// Флажок навыка на секторе с ростом (15B.1).
    static func banner() -> RGBACanvas {
        var c = RGBACanvas(width: 10, height: 16, fill: nil)
        for y in 1...15 { c.set(1, y, 0x5C3A1E) }
        c.polygon([(2, 1), (9, 4), (2, 7)], 0xB8651B)
        return c
    }

    /// Засохшее дерево пустоши (15B.1): то же дерево зоны, серо-коричневое.
    static func deadTree(_ zone: ClimateZone) -> RGBACanvas {
        let tree = tree(zone, dark: false)
        var c = RGBACanvas(width: tree.width, height: tree.height, fill: nil)
        for y in 0..<tree.height { for x in 0..<tree.width {
            guard let color = tree.color(x, y) else { continue }
            let r = Double((color >> 16) & 0xFF), g = Double((color >> 8) & 0xFF), b = Double(color & 0xFF)
            let grey = (r + g + b) / 3
            if (y + x) % 3 == 0 && y < tree.height - 3 { continue } // поредевшая крона
            c.set(x, y, UInt32(min(255, grey + 30)) << 16 | UInt32(min(255, grey + 14)) << 8 | UInt32(max(0, grey - 4)))
        } }
        return c
    }

    // MARK: 15D: шатёр торговца

    /// Шатёр торговца (15H: в 3,5 раза меньше прежнего — рядом с домиками города).
    static func merchantTent() -> RGBACanvas {
        var c = RGBACanvas(width: 28, height: 24, fill: nil)
        c.polygon([(1, 9), (14, 1), (27, 9)], 0xB8651B)
        for x in stride(from: 3, to: 26, by: 5) { c.polygon([(x, 9), (14, 2), (x + 2, 9)], 0xF4EFE4) }
        for y in 9...22 { for x in 3...24 { c.set(x, y, x > 14 ? 0x6A4024 : 0x7A4A2A) } }
        for y in 18...19 { for x in 3...24 { c.set(x, y, 0xD9A441) } }
        for y in 11...22 { for x in 11...16 { c.set(x, y, 0x3B2414) } }
        for cx in [6, 21] { for y in 14...17 { for x in (cx - 1)...(cx + 1) { c.set(x, y, 0xC9A57A) } } }
        return c
    }

    // MARK: 15C: клад, вход в пещеру, смотровая площадка

    static func treasureChest(opened: Bool) -> RGBACanvas {
        var c = RGBACanvas(width: 22, height: 18, fill: nil)
        for y in 7...16 { for x in 2...19 { c.set(x, y, 0x7A4A2A) } }
        for y in 7...9 { for x in 2...19 { c.set(x, y, 0xD9A441) } }
        for y in 9...13 { for x in 9...12 { c.set(x, y, 0xF2D27A) } }
        if opened {
            c.polygon([(2, 7), (6, 0), (21, 0), (19, 7)], 0x966038)
            for i in 0..<10 { c.set(5 + i, 6 - i % 3, 0xFFE278) }
        } else {
            for y in 3...7 { for x in 2...19 { c.set(x, y, 0x966038) } }
            for x in 2...19 { c.set(x, 3, 0xD9A441); c.set(x, 4, 0xD9A441) }
        }
        return c
    }

    /// Крестик клада на земле.
    static func treasureMark() -> RGBACanvas {
        var c = RGBACanvas(width: 12, height: 8, fill: nil)
        for k in 0..<8 {
            for w in 0..<2 { c.set(2 + k + w, k, 0xA8281E); c.set(9 - k + w, k, 0xA8281E) }
        }
        return c
    }

    static func caveEntrance() -> RGBACanvas {
        var c = RGBACanvas(width: 30, height: 26, fill: nil)
        c.polygon([(0, 25), (6, 6), (15, 0), (24, 6), (29, 25)], 0x7A7368)
        c.polygon([(15, 0), (24, 6), (29, 25), (15, 25)], 0x625C53)
        for y in 10...25 { for x in 8...22 where pow(Double(x) - 15, 2) / 49 + pow(Double(y) - 20, 2) / 100 <= 1 { c.set(x, y, 0x0E0C10) } }
        for y in 21...25 { for x in 7...9 { c.set(x, y, 0x5C3A1E) } }
        c.set(8, 20, 0xF2B35B)
        return c
    }

    static func lookout(used: Bool) -> RGBACanvas {
        var c = RGBACanvas(width: 24, height: 30, fill: nil)
        for y in 14...29 { for x in [3, 4, 5, 18, 19, 20] { c.set(x, y, 0x5C3A1E) } }
        c.polygon([(0, 14), (12, 9), (23, 14), (12, 19)], used ? 0xB89A70 : 0x9A7450)
        for x in 4...19 { c.set(x, 22, 0x6E5234) }
        for k in 0..<6 { c.set(12 - k / 2, 9 - k, 0x3C3C46); c.set(12 + k / 2, 9 - k, 0x3C3C46) }
        for k in 0..<11 { c.set(8 + k, 3 - k / 4, 0xD9A441); c.set(8 + k, 4 - k / 4, 0xD9A441) }
        return c
    }

    // MARK: Корабль

    /// Изометрический корабль, идущий вправо-вниз; влево — зеркало. frame 0…3 — парус «дышит», флаг вьётся.
    static func ship(frame: Int, sails: Int = 2) -> RGBACanvas {
        var c = RGBACanvas(width: 72, height: 64, fill: nil)
        let hull: UInt32 = 0x6B3F22, hullDark: UInt32 = 0x4E2E18, deck: UInt32 = 0xA87A4E, line: UInt32 = 0x3B2414
        let cx = 34, cy = 46
        let bow = (cx + 22, cy + 11), stern = (cx - 20, cy - 10)
        let half = 4
        let s1 = (stern.0 - half, stern.1 + half / 2), s2 = (stern.0 + half, stern.1 - half / 2)
        let m1 = (cx - half - 2, cy + half / 2 + 1), m2 = (cx + half + 2, cy - half / 2 - 1)
        let drop = 10
        let bottom = [(bow.0 - 6, bow.1 + drop - 3), (m1.0 + 2, m1.1 + drop), (s1.0 + 1, s1.1 + drop - 1)]
        c.polygon([s1, m1, bow] + bottom, hull)
        c.polygon([(s1.0, s1.1 + drop - 3), (m1.0, m1.1 + drop - 3), (bow.0 - 5, bow.1 + drop - 4)] + bottom, hullDark)
        let deckPoly = [s2, m2, bow, m1, s1]
        c.polygon(deckPoly, deck)
        // Доски палубы.
        for k in stride(from: -4, through: 4, by: 2) { for t in 0..<40 {
            let x = stern.0 + t - k, y = stern.1 + t / 2 + k / 2
            if c.color(x, y) == deck { c.set(x, y, Pix.shade(deck, 0.88)) }
        } }
        // Фальшборт.
        for k in deckPoly.indices { line2(&c, deckPoly[k], deckPoly[(k + 1) % deckPoly.count], line) }
        // Полоса с портами.
        for t in 0..<44 {
            let x = s1.0 + t, y = s1.1 + 2 + t / 2 - (t > 30 ? 1 : 0)
            if c.color(x, y) != nil { c.set(x, y, t % 5 == 0 ? 0x2A1A0E : 0xE3CF9A) }
        }
        // Надстройка на корме.
        for y in (stern.1 - 6)..<(stern.1 + 3) { for x in (stern.0 - 4)..<(stern.0 + 6) { c.set(x, y, x < stern.0 + 1 ? 0x7A4A2A : 0x5E3820) } }
        c.set(stern.0 - 2, stern.1 - 3, 0xF2B35B)
        let masts = [(cx + 6, cy + 1, 30)] + (sails > 1 ? [(cx - 9, cy - 6, 24)] : [])
        let bulge = [0, 1, 2, 1][frame % 4]
        for (mx, my, mh) in masts {
            for y in (my - mh)...my { c.set(mx, y, line) }
            for (y0, y1, w) in [(my - mh + 4, my - mh + 13, 9), (my - mh + 15, my - mh + 24, 11)] {
                for y in y0...min(y1, my - 2) {
                    let t = Double(y - y0) / Double(max(1, y1 - y0))
                    let b = Int((Double(bulge) * (1 - pow(2 * t - 1, 2))).rounded())
                    for x in (mx - w + b)...(mx + w + b) {
                        let yy = y + Int((Double(x - mx) / 5).rounded(.down))
                        let edge = x == mx - w + b || x == mx + w + b || y == y0
                        c.set(x, yy, edge ? 0xE3DCCB : (x < mx + b ? 0xFFFCF6 : 0xEDE6D6))
                    }
                }
            }
        }
        let (fx, fy, fh) = masts[0]
        for k in 0..<6 { for j in 0..<3 { c.set(fx + 1 + k, fy - fh + j + ((k + frame) % 4 == 0 ? 1 : 0), 0xA8432F) } }
        for k in 0..<8 { c.set(bow.0 + k, bow.1 - 2 - k / 2, line) }
        return c
    }

    /// Корабль носом вправо-вверх (15H, макет ExploreDirections): ближе к зрителю — корма с надстройкой и транцем,
    /// паруса с изнанки. Влево-вверх — зеркало.
    static func shipUp(frame: Int, sails: Int = 2) -> RGBACanvas {
        var c = RGBACanvas(width: 72, height: 64, fill: nil)
        let hull: UInt32 = 0x6B3F22, hullDark: UInt32 = 0x4E2E18, deck: UInt32 = 0xA87A4E, line: UInt32 = 0x3B2414
        let cx = 36, cy = 44
        let bow = (cx + 22, cy - 11), stern = (cx - 20, cy + 10)
        let s1 = (stern.0 + 4, stern.1 + 2), s2 = (stern.0 - 4, stern.1 - 2)
        let m1 = (cx + 6, cy + 3), m2 = (cx - 6, cy - 3)
        let drop = 10
        let bottom = [(bow.0 - 4, bow.1 + drop - 2), (m1.0 - 1, m1.1 + drop), (s1.0 - 2, s1.1 + drop - 2), (s2.0 + 1, s2.1 + drop)]
        c.polygon([s2, s1, m1, bow] + bottom, hull)
        c.polygon([(s2.0, s2.1 + drop - 3), (s1.0, s1.1 + drop - 3), (m1.0, m1.1 + drop - 3), (bow.0 - 3, bow.1 + drop - 4)] + bottom, hullDark)
        // Транец — плоская корма к зрителю, окна кают.
        c.polygon([s2, s1, (s1.0, s1.1 + 6), (s2.0, s2.1 + 6)], 0x5E3820)
        for x in stride(from: s2.0 + 2, to: s1.0 - 1, by: 3) { c.set(x, s2.1 + 3 + (x - s2.0) / 2, 0xF2B35B) }
        let deckPoly = [s2, m2, bow, m1, s1]
        c.polygon(deckPoly, deck)
        for k in stride(from: -4, through: 4, by: 2) { for t in 0..<40 {
            let x = stern.0 + t + k, y = stern.1 - t / 2 + k / 2
            if c.color(x, y) == deck { c.set(x, y, Pix.shade(deck, 0.88)) }
        } }
        for k in deckPoly.indices { line2(&c, deckPoly[k], deckPoly[(k + 1) % deckPoly.count], line) }
        // Надстройка на корме.
        for y in (stern.1 - 7)..<(stern.1 + 1) { for x in (stern.0 - 4)..<(stern.0 + 6) { c.set(x, y, x < stern.0 + 1 ? 0x7A4A2A : 0x5E3820) } }
        let masts = [(cx + 7, cy - 4, 30)] + (sails > 1 ? [(cx - 8, cy + 4, 24)] : [])
        let bulge = [0, 1, 2, 1][frame % 4]
        for (mx, my, mh) in masts.reversed() {
            for y in (my - mh)...my { c.set(mx, y, line) }
            for (y0, y1, w) in [(my - mh + 4, my - mh + 13, 9), (my - mh + 15, my - mh + 24, 11)] {
                for y in y0...min(y1, my - 2) {
                    let t = Double(y - y0) / Double(max(1, y1 - y0))
                    let b = Int((Double(bulge) * (1 - pow(2 * t - 1, 2))).rounded())
                    for x in (mx - w - b)...(mx + w - b) {
                        let yy = y - Int((Double(x - mx) / 5).rounded(.down))
                        let edge = x == mx - w - b || x == mx + w - b || y == y0
                        c.set(x, yy, edge ? 0xD5CCB8 : (x < mx ? 0xE9E1CF : 0xDCD3BF))
                    }
                    c.set(mx, y, line)
                }
            }
        }
        let (fx, fy, fh) = masts[0]
        for k in 0..<6 { for j in 0..<3 { c.set(fx + 1 + k, fy - fh + j + ((k + frame) % 4 == 0 ? 1 : 0), 0xA8432F) } }
        for k in 0..<8 { c.set(bow.0 + k, bow.1 - 3 - k / 2, line) }
        return c
    }

    // MARK: 15E: вид корабля — без парусов до квеста, улучшения верфи (макет ExploreShipyard)

    /// Перекрашивает и дополняет корабль: `bare` — без парусов (квест не выполнен); `up` — рисунок «носом вверх».
    static func dress(_ c: inout RGBACanvas, upgrades: Set<ShipUpgrade>, bare: Bool, up: Bool) {
        let sails: Set<UInt32> = up ? [0xE9E1CF, 0xDCD3BF, 0xD5CCB8] : [0xFFFCF6, 0xEDE6D6, 0xE3DCCB]
        let grey: [UInt32: UInt32] = up ? [0xE9E1CF: 0x969BA4, 0xDCD3BF: 0x868B94, 0xD5CCB8: 0x7A7F88]
                                         : [0xFFFCF6: 0xA8ADB5, 0xEDE6D6: 0x969BA4, 0xE3DCCB: 0x7A7F88]
        let hull: [UInt32: UInt32] = [0x6B3F22: 0x3A3A40, 0x4E2E18: 0x24242A]
        for y in 0..<c.height { for x in 0..<c.width {
            guard let color = c.color(x, y) else { continue }
            if sails.contains(color) {
                if bare { c.setAlpha(x, y, 0, alpha: 0) } else if upgrades.contains(.sails), let g = grey[color] { c.set(x, y, g) }
            } else if upgrades.contains(.hull), let h = hull[color] {
                c.set(x, y, h)
            }
        } }
        if upgrades.contains(.cannons) {
            for t in stride(from: 5, to: 33, by: 7) {
                let x = up ? 24 + t : 10 + t, y = up ? 59 - t * 9 / 16 : 40 + t / 2
                for k in 0..<4 {
                    c.set(x - k, y + 1 + k / 2, 0x18181E)
                    c.set(x - k, y + 2 + k / 2, 0x3C3C46)
                }
                c.set(x + 1, y, 0xE5482B)
            }
        }
        if upgrades.contains(.hold) {
            let boxes: [(Int, Int, UInt32)] = up ? [(26, 44, 0xB8651B), (32, 41, 0xC9A878), (38, 38, 0xB8651B)]
                                                 : [(17, 38, 0xB8651B), (23, 41, 0xC9A878), (29, 44, 0xB8651B), (20, 34, 0xC9A878)]
            for (bx, by, color) in boxes { for dy in 0..<5 { for dx in 0..<5 {
                c.set(bx + dx, by + dy, dx == 0 || dx == 4 || dy == 0 || dy == 4 ? 0x3B2414 : color)
            } } }
        }
        if upgrades.contains(.mast) {
            let (mx, top) = up ? (43, 8) : (40, 15)
            for dx in -4...4 {
                c.set(mx + dx, top, 0x3B2414); c.set(mx + dx, top + 1, 0x7A4A2A); c.set(mx + dx, top + 2, 0x3B2414)
            }
            for k in 0..<5 { c.set(mx + 2 + k, top - 1 - k / 2, 0xD9A441) }
            c.set(mx + 7, top - 3, 0xFFF8D2)
        }
    }

    /// Пиратский корабль (16.2): чёрные паруса с черепом, тёмно-красный борт.
    static func pirate(_ c: inout RGBACanvas) {
        let sails: [UInt32: UInt32] = [0xFFFCF6: 0x28262C, 0xEDE6D6: 0x1E1C22, 0xE3DCCB: 0x15131A]
        let hull: [UInt32: UInt32] = [0x6B3F22: 0x4A241E, 0x4E2E18: 0x321814]
        for y in 0..<c.height { for x in 0..<c.width {
            guard let color = c.color(x, y) else { continue }
            if let s = sails[color] { c.set(x, y, s) } else if let h = hull[color] { c.set(x, y, h) }
        } }
        for (x, y) in [(40, 26), (41, 26), (42, 26), (39, 27), (43, 27), (40, 28), (42, 28), (41, 29)] { c.set(x, y, 0xF4EFE4) }
    }

    /// Обломки в море: доски и бочка (15E.1).
    static func wreck() -> RGBACanvas {
        var c = RGBACanvas(width: 24, height: 14, fill: nil)
        for (x0, y0, n) in [(2, 7, 14), (6, 9, 14), (4, 4, 12)] {
            for i in 0..<n { c.set(x0 + i, y0 + i / 4, 0x8A5A34); c.set(x0 + i, y0 + i / 4 + 1, 0x6B4A2E) }
        }
        for (x, y) in [(8, 7), (14, 9), (12, 5)] { c.set(x, y, 0x3B2414) }
        for y in 2...6 { for x in 17...20 { c.set(x, y, y == 3 || y == 5 ? 0x5E3820 : 0xB8651B) } }
        return c
    }

    /// Морской змей (15E.1): три горба из воды и голова; frame — горбы «дышат».
    static func serpent(frame: Int) -> RGBACanvas {
        var c = RGBACanvas(width: 48, height: 28, fill: nil)
        for hump in 0..<3 {
            let cx = 8 + hump * 13, lift = (hump + frame) % 2
            for a in stride(from: 0, through: 180, by: 6) {
                for w in 0..<4 {
                    let r = Double(a) * .pi / 180
                    let x = Int((Double(cx) + cos(r) * (6 - Double(w) * 0.4)).rounded())
                    let y = Int((20 - Double(lift * 2) - sin(r) * Double(8 - w)).rounded())
                    c.set(x, y, w < 3 ? 0x2E6B4F : 0x9DB06A)
                }
            }
            for x in (cx - 6)...(cx + 6) { c.set(x, 21, 0xB8D3E6) }
        }
        for y in 4...10 { for x in 40...46 where (x - 43) * (x - 43) + (y - 7) * (y - 7) <= 11 { c.set(x, y, 0x2E6B4F) } }
        for y in 9...20 { c.set(41, y, 0x2E6B4F); c.set(42, y, 0x1F4A36) }
        c.set(44, 6, 0xE5482B)
        for x in stride(from: 40, to: 47, by: 2) { c.set(x, 3, 0xA8432F) }
        return c
    }

    // MARK: 15H: монстры — звери зон и «долги» (макет ExploreMonsters)

    /// Монстр 16×12, 2 кадра: второй — шаг (лапы) или колыхание (тень, лень).
    static func monster(_ kind: MonsterKind, frame: Int) -> RGBACanvas {
        let (rows, palette): ([String], [Character: UInt32]) = switch kind {
        case .wolf: (["....KK......KK..", "...KWWK....KWWK.", "...KWWWKKKKWWWK.", "..KWWWWWWWWWWWK.", "..KWEWWWWWWEWWK.",
                      ".KWWWWWWWWWWWWWK", "KWWWWnWWWWWWWWK.", ".KKWWWWWWWWWWK..", "...KWWKKKKWWK...", "...KWK....KWK...", "...KK......KK..."],
                     ["K": 0x2A2320, "W": 0xC9CED6, "E": 0xE5482B, "n": 0x2A2320])
        case .bear: (["..KK........KK..", ".KBBK......KBBK.", ".KBBBKKKKKKBBBK.", "KBBBBBBBBBBBBBBK", "KBBEBBBBBBBBEBBK",
                      "KBBBBBnnnBBBBBBK", "KBBBBBBBBBBBBBBK", ".KBBBBBBBBBBBBK.", ".KBBKKBBBBKKBBK.", ".KBK..KBBK..KBK.", ".KK....KK....KK."],
                     ["K": 0x2A2320, "B": 0x6B4A2E, "E": 0xF2D27A, "n": 0x2A2320])
        case .boar: (["................", "....KKKKKKKK....", "...KbbbbbbbbK...", "..KbbbbbbbbbbK..", ".KbEbbbbbbbbbbK.",
                      "KWbbbbbbbbbbbbK.", "KbbbbbbbbbbbbbK.", ".KKbbbbbbbbbbK..", "..KbbKKKKbbK....", "..KbK....KbK....", "..KK......KK...."],
                     ["K": 0x2A2320, "b": 0x8A5A34, "E": 0xE5482B, "W": 0xF4EFE4])
        case .jackal: (["..K.........K...", ".KJK.......KJK..", ".KJJKKKKKKKJJK..", "KJJJJJJJJJJJJK..", "KJEJJJJJJJEJJK..",
                        ".KJJJJnJJJJJJJK.", "..KJJJJJJJJJJJJK", "..KJJJJJJJJJJK..", "...KJJKKKKJJK...", "...KJK....KJK...", "...KK......KK..."],
                       ["K": 0x2A2320, "J": 0xC8AE7E, "E": 0x2A2320, "n": 0x2A2320])
        case .scorpion: (["..........KK....", ".........KSSK...", "..........KSK...", "...KK......KSK..", "..KSSK....KSSK..",
                          ".KSSSSKKKKSSK...", "KSESSSSSSSSK....", "KSSSSSSSSSSK....", ".KSKSKSKSKSK....", "..K.K.K.K.K.....", "................"],
                         ["K": 0x2A2320, "S": 0xB8651B, "E": 0xF2D27A])
        case .deadline: (["......KKKK......", ".....KNNNNK.....", "....KNNNNNNK....", "....KNEENEENK...", "...KNNNNNNNNK...",
                          "...KNNGGGGNNK...", "..KNNNNGGNNNNK..", "..KNNNGGGGNNNK..", ".KNNNNNNNNNNNNK.", ".KNKNKNKNKNKNNK.", "..K.K.K.K.K.KK.."],
                         ["K": 0x15131A, "N": 0x2B2B35, "E": 0xE5482B, "G": 0xD9A441])
        case .sloth: (["................", "................", "......KKKK......", "....KKllllKK....", "...KllllllllK...",
                       "..KllEllllEllK..", "..KlllllllllK...", ".KllllllnnllllK.", ".KllllllllllllK.", "KllllllllllllllK", ".KKKKKKKKKKKKKK."],
                      ["K": 0x2E4A36, "l": 0x7DB86A, "E": 0x1F2A44, "n": 0x2E4A36])
        case .lure: (["...K........K...", "...KK......KK...", "....KKKKKKKK....", "...KRRRRRRRRK...", "...KRYRRRRYRK...",
                      "...KRRRnnRRRK...", "....KRRRRRRK....", "...KRRRRRRRRK.K.", "..KRRKRRRRKRRKRK", "...KK.KRRK.KK.K.", "......KK.KK....."],
                     ["K": 0x2A1414, "R": 0xB5473A, "Y": 0xF2D27A, "n": 0x2A1414])
        }
        var c = RGBACanvas(width: 16, height: 13, fill: nil)
        // Тень под ногами.
        for x in 2...13 { c.setAlpha(x, 12, 0x141828, alpha: 0.25) }
        let lift = frame % 2
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let color = palette[ch] else { continue }
                // Шаг: нижние ряды (лапы) остаются, корпус приподнимается на 1 px.
                c.set(x, y + 1 - (y < 8 ? lift : 0), color)
            }
        }
        return c
    }

    private static func line2(_ c: inout RGBACanvas, _ a: (Int, Int), _ b: (Int, Int), _ color: UInt32) {
        let steps = max(abs(b.0 - a.0), abs(b.1 - a.1), 1)
        for k in 0...steps {
            let t = Double(k) / Double(steps)
            c.set(Int((Double(a.0) + Double(b.0 - a.0) * t).rounded()), Int((Double(a.1) + Double(b.1 - a.1) * t).rounded()), color)
        }
    }
}

// MARK: - Персонажи (на главном потоке: палитры героя)

enum ExploreCharacters {
    /// Размер кадра персонажа: рисунок 32×56 + поля для оружия (10 px с каждой стороны), тень и запас на шаг.
    static let frameSize = (width: 56, height: 61)
    /// Сдвиг рисунка в кадре по горизонтали.
    static let inset = 12
    /// Ноги на кадре — от низа, пикселей (для anchorPoint).
    static let feetFromBottom = 3

    enum Wear { case plain, fur, scarf }

    /// Сетка цветов героя (образ E со всеми деталями) или NPC.
    static func pixels(_ appearance: HeroAppearance, accent: UInt32, wear: Wear = .plain) -> [[UInt32?]] {
        var rows = HeroComposer.colors(appearance, accent: accent)
        guard wear != .plain else { return rows }
        let hair = appearance.hair.hex, hairDark = HeroPalette.shade(hair, 0.76), outline: UInt32 = 0x2A2320
        for y in 0..<rows.count { for x in 0..<rows[y].count {
            guard let c = rows[y][x] else {
                if wear == .scarf, (20...25).contains(y), [8, 9, 22, 23].contains(x) { rows[y][x] = 0xC8AE7E }
                continue
            }
            switch wear {
            case .fur:
                if (9...13).contains(y), c == hair || c == hairDark || ((12...13).contains(y) && c == outline && (8...23).contains(x)) {
                    rows[y][x] = (x + y) % 3 == 0 ? 0xC9C0B0 : 0xEDE7DC
                }
                if (24...25).contains(y), (9...22).contains(x), c != outline { rows[y][x] = (x + y) % 2 == 0 ? 0xC9C0B0 : 0xEDE7DC }
            case .scarf:
                if (8...22).contains(y), c == hair || c == hairDark { rows[y][x] = (x + y) % 4 == 0 ? 0xC8AE7E : 0xE9D7B0 }
            case .plain: break
            }
        } }
        return rows
    }

    /// 4 кадра шага: ноги по очереди, корпус качается на 1 px; контур (для NPC) и тень под ногами.
    static func frames(_ pixels: [[UInt32?]], outline: Bool,
                       weapon: (behind: [WeaponArt.Pixel], front: [WeaponArt.Pixel]) = ([], [])) -> [CGImage] {
        (0..<4).compactMap { frame in
            var c = RGBACanvas(width: frameSize.width, height: frameSize.height, fill: nil)
            // Тень.
            let cx = Double(inset + 16)
            for y in 54...59 { for x in (inset + 1)...(inset + 31) {
                let dx = (Double(x) - cx) / 15, dy = (Double(y) - 57) / 2.6
                if dx * dx + dy * dy <= 1 { c.setAlpha(x, y, 0x141828, alpha: 0.28) }
            } }
            let bob = frame % 2 == 1 ? 1 : 0
            var body = RGBACanvas(width: frameSize.width, height: frameSize.height, fill: nil)
            // Оружие позади тела (копьё за спиной).
            for pixel in weapon.behind { body.set(pixel.x + inset, pixel.y + 2 - bob, pixel.color) }
            for y in 0..<pixels.count { for x in 0..<pixels[y].count {
                guard let color = pixels[y][x] else { continue }
                var ny = y + 2 - bob
                if y >= 52 {
                    let left = x < 16
                    if frame == 1 { ny += left ? -1 : 1 } else if frame == 3 { ny += left ? 1 : -1 }
                }
                body.set(x + inset, ny, color)
            } }
            for pixel in weapon.front { body.set(pixel.x + inset, pixel.y + 2 - bob, pixel.color) }
            if outline {
                let source = body
                for y in 0..<source.height { for x in 0..<source.width where source.color(x, y) == nil {
                    if [(1, 0), (-1, 0), (0, 1), (0, -1)].contains(where: { source.color(x + $0.0, y + $0.1) != nil }) { body.set(x, y, 0x1F1C1A) }
                } }
            }
            c.draw(body, at: 0, 0)
            return c.image
        }
    }

    /// Вид со спины (15H, макет ExploreDirections): голова — затылок цвета волос, оружие — зеркально и за телом.
    /// Влево — зеркало (xScale узла), поэтому рисунков два: спереди (`frames`) и со спины.
    static func backFrames(_ pixels: [[UInt32?]], hair: UInt32, outline: Bool,
                           weapon: (behind: [WeaponArt.Pixel], front: [WeaponArt.Pixel]) = ([], [])) -> [CGImage] {
        var rows = pixels
        let line: UInt32 = 0x2A2320, dark = HeroPalette.shade(hair, 0.76)
        for y in 9...21 where y < rows.count {
            let xs = rows[y].indices.filter { rows[y][$0] != nil }
            guard let a = xs.first, let b = xs.last, b - a > 1 else { continue }
            for x in (a + 1)..<b where rows[y][x] != nil && rows[y][x] != line {
                rows[y][x] = (y >= 19 || (x + y) % 7 == 0) ? dark : hair
            }
        }
        let mirrored = (weapon.behind + weapon.front).map { WeaponArt.Pixel(x: 31 - $0.x, y: $0.y, color: $0.color) }
        return frames(rows, outline: outline, weapon: (mirrored, []))
    }

    /// Легенда (15H): полный комплект образа по месту в топе, волосы и кожа — по месту.
    static func legend(rank: Int) -> (front: [CGImage], back: [CGImage]) {
        let outfit = HeroAppearance.Outfit.allCases[rank % HeroAppearance.Outfit.allCases.count]
        let hairs: [HeroAppearance.Hair] = [.dark, .red, .blond, .black, .dark, .dark, .red, .black, .blond]
        let skins: [HeroAppearance.Skin] = [.light, .medium, .light, .tan, .deep, .light, .light, .medium, .tan]
        let accents: [UInt32] = [0x3E5C8A, 0xA8432F, 0x2F6B4F, 0x2B2B35, 0xD9772B, 0x2F6B4F, 0x6A4E8C, 0x2F6B4F, 0xD9A441]
        let look = HeroAppearance(hair: hairs[rank % 9], skin: skins[rank % 9], outfit: outfit, parts: .preset(outfit))
        let base = pixels(look, accent: accents[rank % 9])
        return (frames(base, outline: true), backFrames(base, hair: look.hair.hex, outline: true))
    }

    /// Босс Чёрной башни (16.5): воин в тёмном, катана, чёрная корона с алым камнем. Рисуется ×1,5 к NPC.
    static func boss() -> (front: [CGImage], back: [CGImage]) {
        var parts = HeroAppearance.Parts.preset(.warrior)
        parts.weapon = .katana
        let look = HeroAppearance(hair: .black, skin: .tan, outfit: .warrior, parts: parts)
        let accent: UInt32 = 0x2B2B35
        var rows = pixels(look, accent: accent)
        let crown: UInt32 = 0x18161C
        for x in 10...22 { for y in 8...9 where y < rows.count && x < rows[y].count { rows[y][x] = crown } }
        for x in [10, 13, 16, 19, 22] { for y in (4 + x % 2)...7 where x < rows[y].count { rows[y][x] = crown } }
        rows[7][16] = 0xE5482B
        rows[8][16] = 0xE5482B
        let weapon = HeroComposer.weaponLayers(look, accent: accent)
        return (frames(rows, outline: true, weapon: weapon), backFrames(rows, hair: look.hair.hex, outline: true, weapon: weapon))
    }

    /// Ночной NPC (15D.3): тёмный плащ поверх одежды, светящиеся глаза, фонарь.
    static func night(_ pixels: [[UInt32?]]) -> [[UInt32?]] {
        var rows = pixels
        for y in 0..<rows.count { for x in 0..<rows[y].count {
            guard let c = rows[y][x] else { continue }
            let grey = (Double((c >> 16) & 0xFF) + Double((c >> 8) & 0xFF) + Double(c & 0xFF)) / 3
            if (24...52).contains(y), (8...24).contains(x) { rows[y][x] = (x + y) % 5 == 0 ? 0x302A3E : 0x221E2E }
            else if y < 24, grey < 90 { rows[y][x] = 0x1C1824 }
        } }
        for (x, y) in [(13, 17), (14, 17), (18, 17), (19, 17)] where y < rows.count { rows[y][x] = 0xF2D27A }
        // Фонарь в правой руке.
        for y in 30...36 where y < rows.count { rows[y][28] = 0x5C3A1E }
        for y in 36...42 where y < rows.count { for x in 26...30 { rows[y][x] = 0xF2B35B } }
        return rows
    }

    /// NPC: одежда по типу, добавки по зоне; ночной — в плаще с фонарём.
    static func npc(tier: NPCTier, zone: ClimateZone, variant: Int, night isNight: Bool) -> (front: [CGImage], back: [CGImage]) {
        let outfit: HeroAppearance.Outfit = switch tier {
        case .acquaintance: .coder
        case .colleague: .archer
        case .regular: .warrior
        }
        let hairs: [HeroAppearance.Hair] = [.dark, .red, .black, .blond]
        let skins: [HeroAppearance.Skin] = [.light, .medium, .tan, .deep]
        let accents: [UInt32] = [0x7A8A6A, 0x3E5C8A, 0x8A4B3A, 0x6B4FA3]
        let look = HeroAppearance(hair: hairs[variant % hairs.count], skin: skins[(variant / 2) % skins.count], outfit: outfit)
        let wear: Wear = zone.isCold ? .fur : zone == .desert || zone == .steppe ? .scarf : .plain
        let base = isNight ? night(pixels(look, accent: accents[variant % accents.count], wear: wear))
                           : pixels(look, accent: accents[variant % accents.count], wear: wear)
        return (frames(base, outline: true), backFrames(base, hair: look.hair.hex, outline: true))
    }
}
