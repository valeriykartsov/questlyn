import CoreGraphics
import Foundation
import Domain

/// Рисование острова «Побродить» (8B): изометрия клеток 16×8 в стиле большой карты, спрайты с прозрачностью.
enum ExploreRenderer {
    nonisolated static let tileW = 16
    nonisolated static let tileH = 8
    nonisolated static let padding = 40

    /// Размер картинки острова в пикселях.
    nonisolated static func imageSize(side: Int) -> (width: Int, height: Int) {
        (side * tileW + padding * 2, side * tileH + padding * 2)
    }

    /// Центр клетки в пикселях картинки (y вниз).
    nonisolated static func pixel(x: Double, y: Double, side: Int) -> (x: Double, y: Double) {
        let originX = Double(side * tileW / 2 + padding)
        let originY = Double(padding)
        return (originX + (x - y) * Double(tileW / 2), originY + (x + y) * Double(tileH / 2) + Double(tileH / 2))
    }

    /// Обратное преобразование: пиксель картинки → клетка (дробная).
    nonisolated static func tile(px: Double, py: Double, side: Int) -> (x: Double, y: Double) {
        let originX = Double(side * tileW / 2 + padding)
        let u = (px - originX) / Double(tileW / 2)
        let v = (py - Double(padding) - Double(tileH / 2)) / Double(tileH / 2)
        return ((u + v) / 2, (v - u) / 2)
    }

    // MARK: Остров — с 15A рисуется кусками (ExploreGround), постройки и деревья — ExploreSprites.

    // MARK: Мини-карта

    /// Вид сверху: клетка — пиксель; цвета зон, горы, дороги (15A).
    static func minimap(_ island: Island, opened: Set<Int> = [], lit: Set<Int> = [], ships: [TilePoint] = []) -> CGImage? {
        var canvas = RGBACanvas(width: island.side, height: island.side, fill: 0x3F6E9C)
        for index in island.terrain.indices {
            let point = TilePoint(index % island.side, index / island.side)
            if let color = mapColor(island, point) { canvas.set(point.x, point.y, color) }
        }
        for city in island.cities {
            for dx in -1...1 { for dy in -1...1 { canvas.set(city.center.x + dx, city.center.y + dy, 0x1F2A44) } }
        }
        // Неоткрытые сундуки и незажжённые костры (8C.9).
        for chest in island.chests where !opened.contains(chest.id) {
            for dx in 0...1 { for dy in 0...1 { canvas.set(chest.position.x + dx, chest.position.y + dy, 0xB8651B) } }
        }
        for fire in island.campfires where !lit.contains(fire.id) {
            for dx in 0...1 { for dy in 0...1 { canvas.set(fire.position.x + dx, fire.position.y + dy, 0xE5482B) } }
        }
        // Корабли (12B): коричневый корпус с белым парусом.
        let mark = max(2, island.side / 60)
        for ship in ships {
            for dx in -mark...mark { for dy in 0...mark { canvas.set(ship.x + dx, ship.y + dy, 0x6B3F22) } }
            for dy in 1...(mark + 1) { canvas.set(ship.x, ship.y - dy, 0xFFFCF6) }
        }
        return canvas.image
    }

    /// Цвет клетки на картах: nil — вода (фон).
    static func mapColor(_ island: Island, _ point: TilePoint) -> UInt32? {
        let zone = island.zone(at: point)
        let grass: [ClimateZone: (UInt32, UInt32)] = [.tundra: (0xE6ECF0, 0x3F5E4A), .taiga: (0x7E9A6A, 0x2E5A3E), .temperate: (0x9DB06A, 0x5F8A43),
                                                       .steppe: (0xC2B56E, 0x8E8A4E), .desert: (0xE8CF8E, 0xB89E62)]
        if island.road(at: point) != nil { return 0x9A7A4E }
        switch island.terrain(at: point) {
        case .water: return nil
        case .sand: return 0xE3CF9A
        case .grass: return grass[zone]!.0
        case .forest: return grass[zone]!.1
        case .mountain: return island.height(at: point) >= ExploreRules.snowLineHeight ? 0xF2F4F6 : (zone == .desert ? 0xA8865E : 0x7A7368)
        }
    }

    /// Карта мира (15A.3) в изометрии, как на экране: клетка — 2 px по ширине; неоткрытая суша — под туманом.
    static func worldMap(_ island: Island, explored: [Bool]) -> CGImage? {
        let side = island.side
        var canvas = RGBACanvas(width: side * 2, height: side + 1, fill: 0x3F6E9C)
        for index in island.terrain.indices {
            let x = index % side, y = index / side
            let px = x - y + side - 1, py = (x + y) / 2
            var color = mapColor(island, TilePoint(x, y)) ?? (index % 7 == 0 ? 0x4A7BAA : 0x3F6E9C)
            // Море известно всегда; под туманом — неоткрытая суша.
            if island.terrain[index] != .water, !(explored.indices.contains(index) && explored[index]) {
                color = (px + py) % 6 == 0 ? 0xD8CDB6 : PixelColor.mix(color, 0xE9E1D0, 0.86)
            }
            canvas.set(px, py, color)
            canvas.set(px + 1, py, color)
        }
        return canvas.image
    }

    /// Точка клетки на карте мира: доли ширины и высоты картинки.
    static func worldMapPoint(_ point: TilePoint, side: Int) -> (x: Double, y: Double) {
        (Double(point.x - point.y + side) / Double(side * 2), Double(point.x + point.y) / 2 / Double(side + 1))
    }

    // MARK: Спрайты

    /// Герой или житель в половинном масштабе (16×28), с прозрачным фоном.
    static func person(_ appearance: HeroAppearance, accent: UInt32) -> CGImage? {
        let rows = HeroComposer.half(appearance, accent: accent)
        let width = rows.map(\.count).max() ?? 16
        var canvas = RGBACanvas(width: width, height: rows.count, fill: nil)
        for (y, row) in rows.enumerated() { for (x, color) in row.enumerated() { if let color { canvas.set(x, y, color) } } }
        return canvas.image
    }

    /// Призрак просроченной задачи (9.6): полупрозрачный, с глазами.
    static func ghost() -> CGImage? {
        let rows = ["..XXXX..", ".XXXXXX.", "XXXXXXXX", "XX.XX.XX", "XXXXXXXX", "XXXXXXXX", "XXXXXXXX", "X.XX.XX.", "..X..X.."]
        var canvas = RGBACanvas(width: 8, height: rows.count, fill: nil)
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                if ch == "X" { canvas.setAlpha(x, y, 0xEEF2F7, alpha: 0.88) } else if y == 3 { canvas.set(x, y, 0x1F2A44) }
            }
        }
        return canvas.image
    }

    /// Спрайт по строкам: символ → цвет, «.» — прозрачно (этап 14).
    static func pattern(_ rows: [String], _ palette: [Character: UInt32]) -> CGImage? {
        var canvas = RGBACanvas(width: rows.map(\.count).max() ?? 0, height: rows.count, fill: nil)
        for (y, row) in rows.enumerated() { for (x, char) in row.enumerated() { if let color = palette[char] { canvas.set(x, y, color) } } }
        return canvas.image
    }

    /// Бутылка с письмом в воде.
    static func bottle() -> CGImage? {
        pattern(["...cc...", "...gg...", "..gwwg..", ".gwppwg.", ".gwppwg.", ".gwwwwg.", "..gggg..", "~~~~~~~~"],
                ["c": 0x7A4A2A, "g": 0x3E6FA3, "w": 0xC8E6F0, "p": 0xFFFCF6, "~": 0xDDE8F2])
    }

    /// Чёрная башня-подземелье Epic; взятая — с белым флагом.
    static func tower(conquered: Bool) -> CGImage? {
        pattern(["..f.f.f.f.f..", "..bbbbbbbbb..", "..bbbbbbbbb..", "...bbbbbbb...", "...bbbrbbbb...", "...bbbbbbb...", "...bbbbbbb...",
                 "...bbrbbbb...", "...bbbbbbb...", "...bbbbbbb...", "...bbbbbbb...", "...bbbbbbb...", "...bbddbbb...", "...bbddbbb...",
                 "..bbbddbbbb..", ".bbbbddbbbbb."],
                ["b": 0x1B1B22, "f": conquered ? 0xFFFCF6 : 0x1B1B22, "r": conquered ? 0x8A8B92 : 0xE5482B, "d": 0x7A2E2E])
    }

    /// Маяк привычки; зажжённый — с огнём.
    static func lighthouse(lit: Bool) -> CGImage? {
        pattern(["...yyy...", "..yyyyy..", "...lll...", "...www...", "...rrr...", "...www...", "..rrrrr..", "..wwwww..", "..rrrrr..",
                 "..wwwww..", ".sssssss."],
                (lit ? ["y": 0xF2D27A] : [:]).merging(["l": lit ? 0xF7D898 : 0x8E8576, "w": 0xFFFCF6, "r": 0xA8432F, "s": 0x8E8576]) { a, _ in a })
    }

    /// Доска заданий у города.
    static func board() -> CGImage? {
        pattern(["oooooooooo", "oppopppppo", "oppoppoppo", "oooooooooo", "....tt....", "....tt....", "....tt...."],
                ["o": 0x5C3410, "p": 0xF5F0E6, "t": 0x5C3410])
    }

    static func chest(opened: Bool) -> CGImage? {
        var canvas = RGBACanvas(width: 10, height: 9, fill: nil)
        for y in 2..<9 { for x in 0..<10 { canvas.set(x, y, y == 2 || y == 8 || x == 0 || x == 9 ? 0x5C3410 : 0xB8651B) } }
        if opened { for x in 1..<9 { canvas.set(x, 3, 0x2B1A0A); canvas.set(x, 4, 0x2B1A0A) } }
        else { for x in 0..<10 { canvas.set(x, 0, 0x5C3410); canvas.set(x, 1, 0x9A5214) } }
        canvas.set(4, 5, 0xF2D27A); canvas.set(5, 5, 0xF2D27A)
        return canvas.image
    }

    /// Фрегат (12B, макет ExploreArchipelago): корпус с полосой портов, корма, бушприт, три мачты с прямыми парусами, флаг.
    static func frigate() -> CGImage? {
        let width = 48, height = 40
        var canvas = RGBACanvas(width: width, height: height, fill: nil)
        let hull: UInt32 = 0x6B3F22, wood: UInt32 = 0x7A4A2A, line: UInt32 = 0x3B2414
        let sail: UInt32 = 0xFFFCF6, shade: UInt32 = 0xE3DCCB, port: UInt32 = 0x2A1A0E, stripe: UInt32 = 0xE3CF9A
        // Мачты: фок, грот, бизань.
        for (x, top) in [(14, 6), (25, 2), (37, 9)] { for y in top...28 { canvas.set(x, y, line) } }
        // Прямые паруса — по два на мачту.
        for (left, right, rows) in [(9, 19, [(8, 14), (16, 22)]), (19, 31, [(4, 11), (13, 21)]), (32, 42, [(11, 16), (18, 22)])] {
            for (top, bottom) in rows {
                for y in top...bottom { for x in left...right {
                    canvas.set(x, y, y == bottom || x == left || x == right ? shade : sail)
                } }
            }
        }
        // Кливер от бушприта к фок-мачте.
        for y in 10...26 {
            let from = 13 - (y - 10) * 11 / 16
            for x in from...13 { canvas.set(x, y, x == from ? shade : sail) }
        }
        // Флаг.
        for y in 0...2 { for x in 26...30 { canvas.set(x, y, 0xA8432F) } }
        // Корма.
        for y in 22...28 { for x in 35...46 { canvas.set(x, y, y == 22 || x == 35 || x == 46 ? line : wood) } }
        // Корпус: сужается к килю, нос — слева.
        for y in 28...35 {
            let left = 3 + (y - 28), right = 46 - (y - 28) / 2
            for x in left...right { canvas.set(x, y, y == 35 || x == left || x == right ? line : hull) }
        }
        for x in 4...45 { canvas.set(x, 28, line) }
        // Полоса орудийных портов.
        for x in 8...42 { canvas.set(x, 30, x % 4 == 0 ? port : stripe) }
        // Бушприт.
        for k in 0...6 { canvas.set(3 - k / 2, 28 - k, line) }
        // Пена у борта.
        for x in stride(from: 5, through: 44, by: 3) { canvas.set(x, 36, 0xDDE8F2); canvas.set(x + 1, 36, 0xDDE8F2) }
        return canvas.image
    }

    static func campfire(lit: Bool) -> CGImage? {
        var canvas = RGBACanvas(width: 12, height: 12, fill: nil)
        for x in 1..<11 { canvas.set(x, 10, 0x5C3A1E); canvas.set(x, 11, 0x3D2614) }
        if lit {
            let flame: [(Int, Int, UInt32)] = [(5, 3, 0xF2D27A), (6, 4, 0xF2B35B), (5, 5, 0xF2B35B), (4, 6, 0xE58A2B), (6, 6, 0xE58A2B),
                                               (5, 7, 0xE58A2B), (4, 8, 0xA8432F), (5, 8, 0xE58A2B), (6, 8, 0xA8432F), (7, 7, 0xE58A2B), (3, 7, 0xE58A2B)]
            for (x, y, c) in flame { canvas.set(x, y, c) }
        } else {
            for x in 3..<9 { canvas.set(x, 9, 0x8E8576) }
        }
        return canvas.image
    }

    /// Туман: тёмная плоскость с прозрачным кругом в центре (радиус — `hole` пикселей).
    static func fog(size: Int, hole: Double) -> CGImage? {
        var canvas = RGBACanvas(width: size, height: size, fill: nil)
        let center = Double(size) / 2
        for y in 0..<size { for x in 0..<size {
            let distance = hypot(Double(x) - center, Double(y) - center)
            let alpha = min(1, max(0, (distance - hole) / (hole * 0.35)))
            if alpha > 0 { canvas.setAlpha(x, y, 0x0F1424, alpha: alpha * 0.55) }
        } }
        return canvas.image
    }
}

enum PixelShade {
    static func darken(_ color: UInt32, _ amount: Double) -> UInt32 { PixelColor.mix(color, 0x000000, amount) }
}

/// RGBA-холст: прозрачный фон для спрайтов.
nonisolated struct RGBACanvas: Sendable {
    let width: Int
    let height: Int
    private(set) var bytes: [UInt8]

    init(width: Int, height: Int, fill: UInt32?) {
        self.width = width
        self.height = height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        if let fill { for y in 0..<height { for x in 0..<width { set(x, y, fill) } } }
    }

    mutating func set(_ x: Int, _ y: Int, _ color: UInt32) { setAlpha(x, y, color, alpha: 1) }

    mutating func setAlpha(_ x: Int, _ y: Int, _ color: UInt32, alpha: Double) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let i = (y * width + x) * 4, a = UInt8((alpha * 255).rounded())
        // Premultiplied alpha.
        bytes[i] = UInt8(Double((color >> 16) & 0xFF) * alpha)
        bytes[i + 1] = UInt8(Double((color >> 8) & 0xFF) * alpha)
        bytes[i + 2] = UInt8(Double(color & 0xFF) * alpha)
        bytes[i + 3] = a
    }

    var image: CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
