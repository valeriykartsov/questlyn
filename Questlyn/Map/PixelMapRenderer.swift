import CoreGraphics
import Foundation
import Domain

/// Пиксельный холст: рисуем в буфер, показываем как изображение без сглаживания.
struct PixelBuffer {
    let width: Int
    let height: Int
    private(set) var pixels: [UInt32]

    init(width: Int, height: Int, fill: UInt32) {
        self.width = width
        self.height = height
        pixels = Array(repeating: fill, count: width * height)
    }

    subscript(x: Int, y: Int) -> UInt32 {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    mutating func set(_ x: Int, _ y: Int, _ color: UInt32) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        pixels[y * width + x] = color
    }

    func get(_ x: Int, _ y: Int) -> UInt32? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        return pixels[y * width + x]
    }

    var image: CGImage? {
        // RGB → RGBA для CGImage.
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for (index, color) in pixels.enumerated() {
            bytes[index * 4] = UInt8((color >> 16) & 0xFF)
            bytes[index * 4 + 1] = UInt8((color >> 8) & 0xFF)
            bytes[index * 4 + 2] = UInt8(color & 0xFF)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

enum PixelColor {
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        [16, 8, 0].reduce(UInt32(0)) { result, shift in
            let ca = Double((a >> UInt32(shift)) & 0xFF), cb = Double((b >> UInt32(shift)) & 0xFF)
            return result | (UInt32((ca * (1 - t) + cb * t).rounded()) << UInt32(shift))
        }
    }
}

/// Детерминированный генератор: один и тот же день рисуется одинаково.
struct SeededRandom {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
    mutating func unit() -> Double { Double(next() % 10_000) / 10_000 }
    mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(max(bound, 1))) }
    mutating func pick<T>(_ items: [T]) -> T { items[int(items.count)] }
}

/// Цвета сезона. Осень и зима — по холсту 8.8–8.9; весна и лето — рабочая гипотеза в той же гамме.
struct Biome {
    let grass: [UInt32]
    let hills: (UInt32, UInt32)
    let road: (UInt32, UInt32, edge: UInt32)
    let leaves: [UInt32]
    let trunk: UInt32

    static func of(_ season: Season) -> Biome {
        switch season {
        case .autumn:
            Biome(grass: [0x9C8F5A, 0x8E8350, 0xAA9D66], hills: (0xA2976A, 0x8F8458), road: (0xE6D7B2, 0xDCCBA2, 0x8A7A5C),
                  leaves: [0xC46A3A, 0xD9A441, 0x9A5214], trunk: 0x5A3E2B)
        case .winter:
            Biome(grass: [0xF4F7F9, 0xE6ECF0, 0xEEF2F4], hills: (0xE9EEF1, 0xDCE4E9), road: (0xB9B1A3, 0xADA597, 0x9C9488),
                  leaves: [0xF4F7F9, 0xE3EAEE, 0xFFFFFF], trunk: 0x5A4A3E)
        case .spring:
            Biome(grass: [0x8DAE6A, 0x7E9E5E, 0x9BBB76], hills: (0x9AB67C, 0x86A46A), road: (0xE6D7B2, 0xDCCBA2, 0x8A7A5C),
                  leaves: [0xE8A9B8, 0x6A9A48, 0xF1C6CF], trunk: 0x5A3E2B)
        case .summer:
            Biome(grass: [0x7FA05A, 0x6E8F4C, 0x8DAE66], hills: (0x7E9A5E, 0x6E8A50), road: (0xE6D7B2, 0xDCCBA2, 0x8A7A5C),
                  leaves: [0x4E7D3A, 0x6A9A48, 0x3D6A2E], trunk: 0x5A3E2B)
        }
    }
}

enum MapStyle {
    static let wallLeft: UInt32 = 0xC9B48A
    static let wallRight: UInt32 = 0xE2D2AE
    static let window: UInt32 = 0x3E4A63
    static let windowLit: UInt32 = 0xF6D36B
    static let roofs: [UInt32] = [0xA8432F, 0x3E5C8A, 0x2F6B4F, 0x6B4FA3, 0xB8651B]
    static let pole: UInt32 = 0x3A2E26

    static func sky(_ light: DayLight) -> (top: UInt32, bottom: UInt32) {
        switch light {
        case .morning: (0xF2D3A6, 0xF7E6C8)
        case .day: (0xBFD6E2, 0xE3EDF1)
        case .evening: (0xE39A6B, 0xF1C99E)
        case .night: (0x1E2742, 0x34406A)
        }
    }

    static func tint(_ light: DayLight) -> (color: UInt32, amount: Double)? {
        switch light {
        case .morning: (0xFFD9A0, 0.10)
        case .day: nil
        case .evening: (0xE58A4A, 0.16)
        case .night: (0x1A2340, 0.5)
        }
    }

    static func moodColor(_ mood: Mood) -> UInt32 {
        switch mood {
        case .good: 0x2F6B4F
        case .neutral: 0x8E8576
        case .bad: 0x3E6FA3
        }
    }

    static func questColor(done: Bool) -> UInt32 { done ? 0x2F6B4F : 0x1F2A44 }
}

/// Рендер карты дня: 2D-полоса для «Сегодня» (холст 8.9) и изометрия для обзора (холст 8.8).
enum PixelMapRenderer {
    // MARK: Общие слои

    private static func finish(_ buffer: inout PixelBuffer, map: DayMap, light: DayLight, seed: UInt64, cloudsY: [Int]) {
        if let tint = MapStyle.tint(light) {
            for index in buffer.pixels.indices where !(light == .night && buffer.pixels[index] == MapStyle.windowLit) {
                buffer[index % buffer.width, index / buffer.width] = PixelColor.mix(buffer.pixels[index], tint.color, tint.amount)
            }
        }
        var random = SeededRandom(seed &+ 77)
        let cloudy = map.weather != .clear
        if cloudy {
            for (index, y) in cloudsY.enumerated() {
                let cx = (index * 2 + 1) * buffer.width / (cloudsY.count * 2) + random.int(10) - 5
                let rw = 10 + random.int(8)
                for dx in -rw...rw {
                    for dy in -3...3 where Double(dx * dx) / Double(rw * rw) + Double(dy * dy) / 12.25 < 1 {
                        if let p = buffer.get(cx + dx, y + dy) { buffer.set(cx + dx, y + dy, PixelColor.mix(p, 0xECEEF0, 0.7)) }
                    }
                }
            }
        }
        switch map.weather {
        case .rain:
            for _ in 0..<(buffer.width * buffer.height / 100) {
                let x = random.int(buffer.width), y = random.int(buffer.height)
                for k in 0..<3 {
                    if let p = buffer.get(x - k / 2, y + k) { buffer.set(x - k / 2, y + k, PixelColor.mix(p, 0x6E87AA, 0.7)) }
                }
            }
        case .snow:
            for _ in 0..<(buffer.width * buffer.height / 80) { buffer.set(random.int(buffer.width), random.int(buffer.height), 0xFFFFFF) }
        case .clear, .cloudy:
            break
        }
        if light == .night {
            for _ in 0..<25 { buffer.set(random.int(buffer.width), random.int(buffer.height / 3), 0xE8EEF2) }
        }
    }

    static func drawHero(_ buffer: inout PixelBuffer, appearance: HeroAppearance, accent: UInt32, centerX: Int, feetY: Int) {
        let rows = HeroComposer.half(appearance, accent: accent)
        for (ry, row) in rows.enumerated() {
            for (cx, color) in row.enumerated() {
                if let color { buffer.set(centerX - row.count / 2 + cx, feetY - rows.count + ry + 1, color) }
            }
        }
    }

    static func flag(_ buffer: inout PixelBuffer, x: Int, baseY: Int, height: Int, color: UInt32) {
        for k in 0..<height { buffer.set(x, baseY - k, MapStyle.pole) }
        for row in 0..<3 {
            for c in 0..<(4 - row) { buffer.set(x + 1 + c, baseY - height + 1 + row, color) }
        }
    }

    // MARK: 2D-полоса

    static let stripSize = (width: 180, height: 50)

    static func strip(_ map: DayMap, appearance: HeroAppearance?, accent: UInt32, farm: ClosedRange<Double>? = nil, aura: Int = 0) -> CGImage? {
        let (w, h) = stripSize
        let groundY = 36, roadTop = 39, roadBottom = 42
        let light = map.light
        let biome = Biome.of(map.season)
        var random = SeededRandom(UInt64(map.date.year * 10_000 + map.date.month * 100 + map.date.day))
        var sky = MapStyle.sky(light)
        if map.weather != .clear { sky = (PixelColor.mix(sky.top, 0xAAB0B8, 0.45), PixelColor.mix(sky.bottom, 0xCDD0D4, 0.45)) }
        var buffer = PixelBuffer(width: w, height: h, fill: sky.bottom)
        for y in 0..<groundY {
            for x in 0..<w { buffer[x, y] = PixelColor.mix(sky.top, sky.bottom, Double(y) / Double(groundY)) }
        }
        for x in 0..<w {
            let h1 = Int(28 + 3 * sin(Double(x) / 17) + 2 * sin(Double(x) / 7))
            let h2 = Int(31 + 2 * sin(Double(x) / 11 + 2))
            for y in h1..<groundY { buffer[x, y] = biome.hills.0 }
            for y in h2..<groundY { buffer[x, y] = biome.hills.1 }
        }
        for y in groundY..<h { for x in 0..<w { buffer[x, y] = random.pick(biome.grass) } }
        for y in roadTop..<roadBottom { for x in 0..<w { buffer[x, y] = (x / 3) % 2 == 0 ? biome.road.1 : biome.road.0 } }
        for x in 0..<w { buffer[x, roadBottom] = biome.road.edge }

        func x(_ hour: Double) -> Int { Int((4 + hour / 24 * Double(w - 8)).rounded()) }
        // «Фарм» — янтарный пунктир по дороге (9.3).
        if let farm {
            for px in x(farm.lowerBound)..<x(farm.upperBound) where (px / 3) % 2 == 0 { buffer.set(px, roadTop + 1, 0xB8651B) }
        }

        // Деревья там, где нет поселений.
        let occupied = map.settlements.map { (x($0.startHour) - 3, max(x($0.startHour) + 8, x($0.endHour)) + 4) }
        for tx in stride(from: 6, to: w, by: 14) where !occupied.contains(where: { tx >= $0.0 && tx <= $0.1 }) {
            let tree = tx + random.int(5) - 2
            for y in (groundY - 6)...groundY { buffer.set(tree, y, biome.trunk) }
            for dy in -4...2 {
                for dx in -3...3 where Double(dx * dx) / 9 + Double(dy * dy) / 10 < 1 && random.unit() < 0.85 {
                    buffer.set(tree + dx, groundY - 9 + dy, random.pick(biome.leaves))
                }
            }
        }

        let night = light == .night
        for (index, settlement) in map.settlements.enumerated() {
            let x0 = x(settlement.startHour)
            let roof = MapStyle.roofs[index % MapStyle.roofs.count]
            let buildings: [(dx: Int, w: Int, h: Int)] = switch (settlement.kind, settlement.density) {
            case (.village, _): [(0, 7, 7)]
            case (.city, 1): [(0, 7, 12), (6, 7, 17), (12, 6, 11)]
            default: [(-2, 6, 13), (3, 7, 20), (9, 7, 16), (15, 6, 12)]
            }
            for building in buildings {
                let bx = x0 + building.dx, base = roadTop - 1
                for y in (base - building.h)..<base {
                    for px in bx..<(bx + building.w) { buffer.set(px, y, px > bx ? MapStyle.wallRight : MapStyle.wallLeft) }
                }
                for k in 0..<3 {
                    for px in (bx - 1 + k)..<(bx + building.w + 1 - k) { buffer.set(px, base - building.h - 1 - k, roof) }
                }
                for wy in stride(from: base - building.h + 2, to: base - 2, by: 4) {
                    for wx in stride(from: bx + 2, to: bx + building.w - 1, by: 3) {
                        let color = night ? MapStyle.windowLit : MapStyle.window
                        buffer.set(wx, wy, color)
                        buffer.set(wx, wy + 1, color)
                    }
                }
            }
        }
        for marker in map.questMarkers {
            flag(&buffer, x: x(marker.hour), baseY: roadBottom + 1, height: 9, color: MapStyle.questColor(done: marker.isDone))
        }
        for mood in map.moodFlags {
            flag(&buffer, x: x(mood.hour), baseY: roadTop, height: 7, color: MapStyle.moodColor(mood.mood))
        }
        if let hour = map.heroHour, let appearance {
            AuraArt.draw(&buffer, tier: aura, centerX: x(hour), feetY: roadBottom, rx: 6, ry: 1.4)
            drawHero(&buffer, appearance: appearance, accent: accent, centerX: x(hour), feetY: roadBottom)
        }
        finish(&buffer, map: map, light: light, seed: UInt64(map.date.day), cloudsY: [6, 4, 8])
        return buffer.image
    }

    // MARK: Изометрия

    /// Поле вытянуто вдоль дороги: 18 клеток по времени и 10 поперёк — поселениям хватает места.
    private static let gridI = 18
    private static let gridJ = 10
    private static let tile = (w: 16, h: 8)
    private static let origin = (x: gridJ * 8 + 4, y: 30)
    static let isoSize = (width: (gridI + gridJ) * 8 + 8, height: 30 + (gridI + gridJ) * 4 + 6)
    private static let roadJ = (4, 5)

    private static func iso(_ i: Double, _ j: Double) -> (x: Int, y: Int) {
        (Int((Double(origin.x) + (i - j) * Double(tile.w) / 2).rounded()), Int((Double(origin.y) + (i + j) * Double(tile.h) / 2).rounded()))
    }

    /// Видимая часть дня (как шкала в макете 3.5): от первого до последнего дела ± час, не меньше 8 часов.
    /// «Сейчас» расширяет её, только если рядом (до 3 часов); иначе герой стоит на краю дороги.
    static func window(for map: DayMap) -> ClosedRange<Double> {
        let hours = map.settlements.flatMap { [$0.startHour, $0.endHour] } + map.questMarkers.map(\.hour) + map.moodFlags.map(\.hour)
        var range: ClosedRange<Double>
        if let first = hours.min(), let last = hours.max() {
            range = max(0, (first - 1).rounded(.down))...min(24, (last + 1).rounded(.up))
        } else if let hero = map.heroHour {
            range = max(0, hero - 4)...min(24, hero + 4)
        } else {
            return 0...24
        }
        if let hero = map.heroHour, !range.contains(hero) {
            let gap = hero < range.lowerBound ? range.lowerBound - hero : hero - range.upperBound
            if gap <= 3 { range = min(range.lowerBound, (hero - 0.5).rounded(.down))...max(range.upperBound, (hero + 0.5).rounded(.up)) }
        }
        var lo = max(0, range.lowerBound), hi = min(24, range.upperBound)
        let minimum = 8.0
        if hi - lo < minimum {
            let middle = (lo + hi) / 2
            lo = max(0, middle - minimum / 2)
            hi = min(24, lo + minimum)
            lo = max(0, hi - minimum)
        }
        return lo...hi
    }

    /// Положение часа на дороге в пределах видимой части дня.
    static func roadI(hour: Double, window: ClosedRange<Double>) -> Double {
        let share = (min(max(hour, window.lowerBound), window.upperBound) - window.lowerBound) / max(window.upperBound - window.lowerBound, 1)
        return 1 + share * Double(gridI - 3)
    }

    /// Точка у поселения в пикселях изометрии — для подписей поверх картинки.
    struct Anchor: Hashable {
        let x: Int
        let y: Int
        let title: String
        let isCity: Bool
        /// Над дорогой — подпись над домами, под дорогой — под ними.
        let above: Bool
    }

    struct Isometric {
        let image: CGImage?
        let anchors: [Anchor]
        let window: ClosedRange<Double>
        /// Где стоит герой и не вышло ли «сейчас» за видимую часть дня.
        let hero: (x: Int, y: Int, outside: Bool)?
    }

    private static func diamond(_ buffer: inout PixelBuffer, _ i: Int, _ j: Int, _ color: UInt32, edge: UInt32? = nil) {
        let (sx, sy) = iso(Double(i), Double(j))
        for row in 0..<tile.h {
            let hw = (row < tile.h / 2 ? row : tile.h - 1 - row) * 2 + 2
            for x in (sx - hw)..<(sx + hw) { buffer.set(x, sy + row, color) }
            if let edge, row >= tile.h / 2 {
                buffer.set(sx - hw, sy + row, edge)
                buffer.set(sx + hw - 1, sy + row, edge)
            }
        }
    }

    private static func box(_ buffer: inout PixelBuffer, _ i: Int, _ j: Int, height: Int, roof: UInt32, lit: Bool) {
        let (sx, sy) = iso(Double(i), Double(j))
        for x in (sx - 7)..<(sx + 7) {
            let bottom = sy + tile.h - 1 - Int(abs(Double(x - sx) + 0.5) / 2)
            for y in (bottom - height)...bottom { buffer.set(x, y, x < sx ? MapStyle.wallLeft : MapStyle.wallRight) }
        }
        for row in 0..<tile.h {
            let hw = (row < tile.h / 2 ? row : tile.h - 1 - row) * 2 + 2
            for x in (sx - hw)..<(sx + hw) { buffer.set(x, sy + row - height - 1, roof) }
        }
        for k in 0..<3 {
            for x in (sx - 4 + k)..<(sx + 4 - k) { buffer.set(x, sy - height - 1 + tile.h / 2 - 2 - k, roof) }
        }
        let window = lit ? MapStyle.windowLit : MapStyle.window
        for wx in [sx - 5, sx - 2, sx + 2, sx + 5] {
            let bottom = sy + tile.h - 1 - Int(abs(Double(wx - sx) + 0.5) / 2)
            for wy in stride(from: bottom - height + 2, to: bottom - 1, by: 4) {
                buffer.set(wx, wy, window)
                buffer.set(wx, wy + 1, window)
            }
        }
    }

    private static func tree(_ buffer: inout PixelBuffer, _ i: Int, _ j: Int, biome: Biome, random: inout SeededRandom) {
        let (sx, top) = iso(Double(i), Double(j))
        let sy = top + 3
        for y in (sy - 6)...sy { buffer.set(sx, y, biome.trunk) }
        for dy in -12 ... -6 {
            for dx in -3...3 where abs(dx) + abs(dy + 8) <= 4 && random.unit() < 0.8 { buffer.set(sx + dx, sy + dy, random.pick(biome.leaves)) }
        }
    }

    private static let villagers: [HeroAppearance] = [
        HeroAppearance(hair: .red, skin: .light, outfit: .archer), HeroAppearance(hair: .blond, skin: .tan, outfit: .warrior),
        HeroAppearance(hair: .black, skin: .deep, outfit: .mage), HeroAppearance(hair: .dark, skin: .medium, outfit: .baller),
    ]

    /// Дома поселения: смещения (по времени, от дороги) и высоты. Плотный город — больше и выше.
    private static func footprint(_ settlement: Settlement) -> [(di: Int, away: Int, height: Int)] {
        switch (settlement.kind, settlement.density) {
        case (.village, _): [(0, 0, 6)]
        case (.city, 1): [(0, 0, 10), (1, 0, 13), (0, 1, 8)]
        default: [(0, 0, 12), (1, 0, 15), (1, 1, 10), (0, 1, 8), (2, 0, 9)]
        }
    }

    static func isometric(_ map: DayMap, appearance: HeroAppearance?, accent: UInt32) -> Isometric {
        let light = map.light
        let window = window(for: map)
        func roadI(_ hour: Double) -> Double { Self.roadI(hour: hour, window: window) }
        let biome = Biome.of(map.season)
        var random = SeededRandom(UInt64(map.date.year * 10_000 + map.date.month * 100 + map.date.day))
        var sky = MapStyle.sky(light)
        if map.weather != .clear { sky = (PixelColor.mix(sky.top, 0xAAB0B8, 0.45), PixelColor.mix(sky.bottom, 0xCDD0D4, 0.45)) }
        var buffer = PixelBuffer(width: isoSize.width, height: isoSize.height, fill: sky.bottom)
        for y in 0..<isoSize.height {
            for x in 0..<isoSize.width { buffer[x, y] = PixelColor.mix(sky.top, sky.bottom, Double(y) / Double(isoSize.height)) }
        }
        for sum in 0..<(gridI + gridJ) {
            for i in 0..<gridI {
                let j = sum - i
                guard j >= 0, j < gridJ else { continue }
                if (j == roadJ.0 || j == roadJ.1), i > 0, i < gridI - 1 {
                    diamond(&buffer, i, j, (i + j) % 2 == 0 ? biome.road.1 : biome.road.0, edge: j == roadJ.1 ? biome.road.edge : nil)
                } else {
                    diamond(&buffer, i, j, random.pick(biome.grass))
                }
            }
        }

        enum Item { case house(Int, Int, Int, UInt32), tree(Int, Int), person(Double, Double, HeroAppearance, UInt32), hero(Double, Double) }
        var items: [(depth: Double, item: Item)] = []
        var anchors: [Anchor] = []
        var used = Set<[Int]>()
        for j in [roadJ.0, roadJ.1] { for i in 0..<gridI { used.insert([i, j]) } }

        // Поселение ставим в середину его времени; сторона — по очереди, а если занято — другая сторона или ряд дальше.
        var preferAbove = true
        for (index, settlement) in map.settlements.enumerated() {
            let center = Int(roadI((settlement.startHour + settlement.endHour) / 2).rounded())
            let shape = footprint(settlement)
            var placed: (above: Bool, tiles: [[Int]], heights: [Int])?
            search: for above in [preferAbove, !preferAbove] {
                for shift in 0..<3 {
                    for nudge in [0, -1, 1] {
                        let tiles = shape.map { part -> [Int] in
                            let away = part.away + shift
                            return [center + part.di + nudge, above ? roadJ.0 - 1 - away : roadJ.1 + 1 + away]
                        }
                        let fits = tiles.allSatisfy { $0[0] >= 0 && $0[0] < gridI && $0[1] >= 0 && $0[1] < gridJ && !used.contains($0) }
                        if fits {
                            placed = (above, tiles, shape.map(\.height))
                            break search
                        }
                    }
                }
            }
            guard let placed else { continue }
            preferAbove = !placed.above
            let roof = MapStyle.roofs[index % MapStyle.roofs.count]
            for (tile, height) in zip(placed.tiles, placed.heights) {
                used.insert(tile)
                items.append((Double(tile[0] + tile[1]), .house(tile[0], tile[1], height, roof)))
            }
            let near = placed.tiles[0]
            let point = iso(Double(near[0]), Double(near[1]))
            let tallest = placed.heights.max() ?? 6
            anchors.append(Anchor(x: point.x + 4, y: placed.above ? point.y - tallest - 8 : point.y + tile.h + 12,
                                  title: settlement.titles.joined(separator: " + "), isCity: settlement.kind == .city, above: placed.above))
            // Участники стоят за домами своего поселения — видны над крышами и не закрывают дома (не больше двух).
            for k in 0..<min(settlement.attendees, 2) {
                let pj = placed.above ? Double(near[1]) - 0.9 : Double(roadJ.1) + 0.2
                let pi = Double(near[0]) + 0.2 + Double(k) * 0.55
                items.append((pi + pj, .person(pi, pj, villagers[(index + k) % villagers.count],
                                                     MapStyle.roofs[(index + k + 1) % MapStyle.roofs.count])))
            }
        }
        // Деревья — на свободных клетках.
        var trees = 0
        while trees < 16 {
            let i = random.int(gridI), j = random.int(gridJ)
            guard !used.contains([i, j]) else { continue }
            used.insert([i, j])
            items.append((Double(i + j), .tree(i, j)))
            trees += 1
        }

        var heroPoint: (x: Int, y: Int, outside: Bool)?
        if let hour = map.heroHour {
            let outside = !window.contains(hour)
            let i = outside ? (hour < window.lowerBound ? 0.6 : Double(gridI) - 1.6) : roadI(hour)
            let point = iso(i, 4.5)
            heroPoint = (point.x, point.y + 6, outside)
            items.append((i + 4.5 + 0.6, .hero(i, 4.5)))
        }
        items.sort { $0.depth < $1.depth }

        let night = light == .night
        for marker in map.questMarkers {
            let (x, y) = iso(roadI(marker.hour), 5.3)
            flag(&buffer, x: x, baseY: y + 4, height: 9, color: MapStyle.questColor(done: marker.isDone))
        }
        for mood in map.moodFlags {
            let (x, y) = iso(roadI(mood.hour), 3.9)
            flag(&buffer, x: x, baseY: y + 4, height: 7, color: MapStyle.moodColor(mood.mood))
        }
        for (_, item) in items {
            switch item {
            case let .house(i, j, height, roof): box(&buffer, i, j, height: height, roof: roof, lit: night)
            case let .tree(i, j): tree(&buffer, i, j, biome: biome, random: &random)
            case let .person(i, j, look, color):
                let (x, y) = iso(i, j)
                drawHero(&buffer, appearance: look, accent: color, centerX: x, feetY: y + 4)
            case let .hero(i, j):
                if let appearance {
                    let (x, y) = iso(i, j)
                    drawHero(&buffer, appearance: appearance, accent: accent, centerX: x, feetY: y + 6)
                }
            }
        }
        finish(&buffer, map: map, light: light, seed: UInt64(map.date.day), cloudsY: [12, 8, 18])
        return Isometric(image: buffer.image, anchors: anchors, window: window, hero: heroPoint)
    }
}
