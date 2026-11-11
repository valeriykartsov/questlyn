import CoreGraphics
import Foundation
import Domain

/// Изометрическая дорога недели (02 от 11.11.2026): семь дней подряд, привалы сна, поселения, погода по дням.
/// Рисуется один раз на неделю; экран показывает окно вокруг точки ползунка.
enum WeekMapRenderer {
    static let tilesPerDay = 16
    static let gridI = 7 * tilesPerDay + 4
    /// Поле шире по краям дороги: карта занимает весь экран (8.16).
    static let gridJ = 24
    static let tile = (w: 16, h: 8)
    /// Запас картинки вокруг поля: в начале и в конце недели окно экрана не выходит за край.
    static let margin = (x: 160, y: 380)
    static let origin = (x: margin.x + gridJ * 8 + 4, y: margin.y + 34)
    static let size = (width: (gridI + gridJ) * 8 + 8 + 2 * margin.x, height: 34 + (gridI + gridJ) * 4 + 8 + 2 * margin.y)
    /// Окно на экране — как прежний обзор дня.
    static let viewport = (width: 232, height: 150)
    static let roadJ = (10, 11)
    /// Река вдоль дороги — текстура мира, ни на что не влияет.
    static let riverJ = 15
    private static var roadMid: Double { Double(roadJ.0) + 0.5 }

    static func iso(_ i: Double, _ j: Double) -> (x: Int, y: Int) {
        (Int((Double(origin.x) + (i - j) * Double(tile.w) / 2).rounded()), Int((Double(origin.y) + (i + j) * Double(tile.h) / 2).rounded()))
    }

    /// Час недели → клетка вдоль дороги.
    static func roadI(_ weekHour: Double) -> Double { 2 + min(max(weekHour, 0), WeekMap.hours) / WeekMap.hours * Double(7 * tilesPerDay) }

    /// Центр дороги в пикселях для часа недели — сюда наводится окно.
    static func roadPoint(_ weekHour: Double) -> (x: Int, y: Int) { iso(roadI(weekHour), roadMid) }

    struct Label: Hashable {
        enum Kind: Hashable { case settlement(city: Bool), camp(known: Bool), day }
        let x: Int
        let y: Int
        let title: String
        let kind: Kind
    }

    struct Rendered {
        let image: CGImage?
        let labels: [Label]
    }

    // MARK: Рисование

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

    private static func box(_ buffer: inout PixelBuffer, _ i: Int, _ j: Int, height: Int, roof: UInt32) {
        let (sx, sy) = iso(Double(i), Double(j))
        for x in (sx - 7)..<(sx + 7) {
            let bottom = sy + tile.h - 1 - Int(abs(Double(x - sx) + 0.5) / 2)
            for y in (bottom - height)...bottom {
                let wall = x < sx ? MapStyle.wallLeft : MapStyle.wallRight
                // Кладка: шов каждые 4 пикселя.
                buffer.set(x, y, (bottom - y) % 4 == 0 && y != bottom ? PixelColor.mix(wall, 0x786446, 0.18) : wall)
            }
        }
        let roofDark = PixelColor.mix(roof, 0x000000, 0.25)
        for row in 0..<tile.h {
            let hw = (row < tile.h / 2 ? row : tile.h - 1 - row) * 2 + 2
            for x in (sx - hw)..<(sx + hw) { buffer.set(x, sy + row - height - 1, row % 2 == 0 ? roof : roofDark) }
        }
        for k in 0..<3 {
            for x in (sx - 4 + k)..<(sx + 4 - k) { buffer.set(x, sy - height - 1 + tile.h / 2 - 2 - k, k % 2 == 0 ? roof : roofDark) }
        }
        // Дверь на правой стене и труба с дымком.
        let doorBottom = sy + tile.h - 1 - Int(abs(3.5) / 2)
        for y in (doorBottom - 4)...doorBottom { buffer.set(sx + 2, y, 0x6B4A2E); buffer.set(sx + 3, y, 0x6B4A2E) }
        if height >= 8 {
            for y in (sy - height - 8)..<(sy - height - 2) { buffer.set(sx + 3, y, 0x8E5A3A); buffer.set(sx + 4, y, 0x8E5A3A) }
            buffer.set(sx + 3, sy - height - 10, 0xC9C3B8)
            buffer.set(sx + 4, sy - height - 11, 0xDCD6CC)
        }
        for wx in [sx - 5, sx - 2, sx + 2, sx + 5] {
            let bottom = sy + tile.h - 1 - Int(abs(Double(wx - sx) + 0.5) / 2)
            for wy in stride(from: bottom - height + 2, to: bottom - 1, by: 4) {
                buffer.set(wx, wy, MapStyle.window)
                buffer.set(wx, wy + 1, MapStyle.window)
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

    // MARK: Текстуры (8.16)

    private static func speckle(_ buffer: inout PixelBuffer, _ i: Int, _ j: Int, colors: [UInt32], count: Int, random: inout SeededRandom) {
        let (sx, sy) = iso(Double(i), Double(j))
        for _ in 0..<count { buffer.set(sx - 6 + random.int(12), sy + 1 + random.int(6), random.pick(colors)) }
    }

    /// Травинки, редкие цветы и камешки.
    private static func grassDetail(_ buffer: inout PixelBuffer, _ i: Int, _ j: Int, biome: Biome, random: inout SeededRandom) {
        let (sx, sy) = iso(Double(i), Double(j))
        let blades = [PixelColor.mix(biome.grass[0], 0xFFFFFF, 0.18), PixelColor.mix(biome.grass[0], 0x000000, 0.18)]
        for _ in 0..<4 {
            let x = sx - 6 + random.int(12), y = sy + 1 + random.int(6), c = random.pick(blades)
            buffer.set(x, y, c)
            if random.unit() < 0.5 { buffer.set(x, y - 1, c) }
        }
        if random.unit() < 0.1 { buffer.set(sx - 4 + random.int(8), sy + 2 + random.int(4), random.pick([0xE8D8A0, 0xD9A441, 0xC46A3A, 0xF1C6CF])) }
        if random.unit() < 0.06 {
            let x = sx - 4 + random.int(7), y = sy + 2 + random.int(4)
            for (dx, dy, c) in [(0, 0, 0x8E8C86), (1, 0, 0xA8A69E), (0, 1, 0x6E6C66), (1, 1, 0x8E8C86)] as [(Int, Int, UInt32)] { buffer.set(x + dx, y + dy, c) }
        }
    }

    private static func ripples(_ buffer: inout PixelBuffer, _ i: Int, _ j: Int, random: inout SeededRandom) {
        let (sx, sy) = iso(Double(i), Double(j))
        for _ in 0..<2 {
            let x = sx - 5 + random.int(8), y = sy + 2 + random.int(4)
            for k in 0..<3 { buffer.set(x + k, y, 0x9CC3DC) }
        }
    }

    private static func bush(_ buffer: inout PixelBuffer, _ i: Int, _ j: Int, random: inout SeededRandom) {
        let (sx, top) = iso(Double(i), Double(j))
        let sy = top + 4
        for dy in -4...0 {
            for dx in -3...3 where Double(dx * dx) / 9 + Double(dy * dy) / 5 < 1 && random.unit() < 0.9 {
                buffer.set(sx + dx, sy + dy, random.pick([0x6E7A3E, 0x7E8A48, 0x5E6A34]))
            }
        }
    }

    /// Забор вдоль дороги — три пролёта.
    private static func fence(_ buffer: inout PixelBuffer, from i: Int, j: Int) {
        for k in 0..<3 {
            let (sx, top) = iso(Double(i + k), Double(j))
            let sy = top + 5
            for y in (sy - 5)...sy { buffer.set(sx, y, 0x6B4A2E) }
            for x in 0..<8 {
                buffer.set(sx + x, sy - 4 + x / 2, 0x8A5A34)
                buffer.set(sx + x, sy - 2 + x / 2, 0x8A5A34)
            }
        }
    }

    /// Привал: палатка и костёр у дороги. Без данных о сне — палатка бледнее, костёр не горит.
    private static func camp(_ buffer: inout PixelBuffer, x: Int, y: Int, known: Bool) {
        let canvas: UInt32 = known ? 0xD8C7A0 : 0xC9BFA9, shade: UInt32 = known ? 0xB9A57E : 0xAFA690, outline: UInt32 = 0x5A4636
        // Палатка 13 × 9.
        for row in 0..<9 {
            let half = row * 6 / 8
            for dx in -half...half {
                let edge = dx == -half || dx == half || row == 8
                buffer.set(x - 6 + 6 + dx - 4, y - 8 + row, edge ? outline : (dx < 0 ? shade : canvas))
            }
        }
        for row in 3..<9 { buffer.set(x - 4, y - 8 + row, 0x3A2E26) }
        // Костёр справа.
        let fx = x + 6
        for dx in -2...2 { buffer.set(fx + dx, y, 0x6B4A2E) }
        buffer.set(fx - 1, y - 1, 0x8A5A34)
        buffer.set(fx + 1, y - 1, 0x8A5A34)
        if known {
            for (dx, dy, color) in [(0, -2, 0xE58A2B), (-1, -2, 0xD9772B), (1, -2, 0xD9772B), (0, -3, 0xF2B544), (0, -4, 0xF6D36B),
                                    (-1, -3, 0xE58A2B), (1, -4, 0xF2B544)] as [(Int, Int, UInt32)] {
                buffer.set(fx + dx, y + dy, color)
            }
            // Отблеск на земле.
            for dx in -4...4 { if let p = buffer.get(fx + dx, y + 1) { buffer.set(fx + dx, y + 1, PixelColor.mix(p, 0xF2B544, 0.35)) } }
        } else {
            for (dx, dy) in [(0, -2), (-1, -3), (1, -4)] { buffer.set(fx + dx, y + dy, 0x9A9A9A) }
        }
    }

    /// Столб с табличкой на полуночи — граница дней.
    private static func signpost(_ buffer: inout PixelBuffer, x: Int, y: Int) {
        for k in 0..<12 { buffer.set(x, y - k, 0x5A3E2B) }
        for dy in 0..<4 { for dx in -3...4 { buffer.set(x + dx, y - 12 + dy, dy == 0 || dy == 3 ? 0x6B4A2E : 0xD9C9A3) } }
    }

    private static let villagers: [HeroAppearance] = [
        HeroAppearance(hair: .red, skin: .light, outfit: .archer), HeroAppearance(hair: .blond, skin: .tan, outfit: .warrior),
        HeroAppearance(hair: .black, skin: .deep, outfit: .mage), HeroAppearance(hair: .dark, skin: .medium, outfit: .baller),
    ]

    private static func footprint(_ settlement: Settlement) -> [(di: Int, away: Int, height: Int)] {
        switch (settlement.kind, settlement.density) {
        case (.village, _): [(0, 0, 6)]
        case (.city, 1): [(0, 0, 10), (1, 0, 13), (0, 1, 8)]
        default: [(0, 0, 12), (1, 0, 15), (1, 1, 10), (0, 1, 8), (2, 0, 9)]
        }
    }

    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) ч" : h == 0 ? "\(m) мин" : "\(h) ч \(m) мин"
    }

    // MARK: Неделя

    static func render(_ week: WeekMap, appearance: HeroAppearance?, accent: UInt32, timeZone: TimeZone) -> Rendered {
        var random = SeededRandom(UInt64(week.start.year * 10_000 + week.start.month * 100 + week.start.day))
        var buffer = PixelBuffer(width: size.width, height: size.height, fill: 0x8E8350)
        func dayIndex(_ i: Int) -> Int { min(6, max(0, (i - 2) / tilesPerDay)) }
        let biomes = week.days.map { Biome.of($0.season) }
        func biome(_ i: Int) -> Biome { biomes.isEmpty ? Biome.of(.autumn) : biomes[min(dayIndex(i), biomes.count - 1)] }

        // Клетки за пределами поля тоже рисуются: углы картинки не остаются плоской заливкой.
        let ext = gridI + gridJ + 100
        func onScreen(_ i: Int, _ j: Int) -> Bool {
            let (x, y) = iso(Double(i), Double(j))
            return x > -tile.w && x < size.width + tile.w && y > -tile.h && y < size.height + tile.h
        }
        for sum in -ext...(2 * ext) {
            for i in -ext...(gridI + ext) {
                let j = sum - i
                guard j >= -ext, j <= gridJ + ext, onScreen(i, j) else { continue }
                let b = biome(i)
                if j == roadJ.0 || j == roadJ.1 {
                    diamond(&buffer, i, j, (i + j) % 2 == 0 ? b.road.1 : b.road.0, edge: j == roadJ.1 ? b.road.edge : nil)
                    speckle(&buffer, i, j, colors: [PixelColor.mix(b.road.0, 0x000000, 0.1), PixelColor.mix(b.road.0, 0xFFFFFF, 0.25)], count: 3, random: &random)
                } else if j == riverJ {
                    diamond(&buffer, i, j, (i + j) % 2 == 0 ? 0x5E86A8 : 0x55809F)
                    ripples(&buffer, i, j, random: &random)
                } else {
                    diamond(&buffer, i, j, random.pick(b.grass))
                    grassDetail(&buffer, i, j, biome: b, random: &random)
                }
            }
        }

        enum Item { case house(Int, Int, Int, UInt32), tree(Int, Int), person(Double, Double, HeroAppearance, UInt32), hero(Double), camp(Int, Int, Bool), sign(Int, Int), bush(Int, Int), fence(Int, Int) }
        var items: [(depth: Double, item: Item)] = []
        var labels: [Label] = []
        var used = Set<[Int]>()
        for j in [roadJ.0, roadJ.1, riverJ] { for i in 0..<gridI { used.insert([i, j]) } }

        // Границы дней — столбы у дороги и подписи.
        for (index, day) in week.days.enumerated() {
            let i = Int(roadI(Double(index) * 24).rounded())
            let sign = iso(Double(i), Double(roadJ.0) - 0.4)
            items.append((Double(i) + Double(roadJ.0) - 0.4, .sign(sign.x, sign.y + 4)))
            if let date = day.date.date {
                labels.append(Label(x: sign.x, y: sign.y - 14,
                                    title: date.formatted(.dateTime.weekday(.abbreviated).day().locale(Locale(identifier: "ru_RU"))), kind: .day))
            }
        }

        // Привалы — ближе к дороге, на свободной стороне.
        for camp in week.camps {
            let startHour = WeekMap.hour(of: camp.start, weekStart: week.start, timeZone: timeZone)
            let endHour = WeekMap.hour(of: camp.end, weekStart: week.start, timeZone: timeZone)
            let center = Int(roadI((startHour + endHour) / 2).rounded())
            guard let spot = [[center, roadJ.1 + 1], [center, roadJ.0 - 1], [center + 1, roadJ.1 + 1]].first(where: { !used.contains($0) }) else { continue }
            used.insert(spot)
            let point = iso(Double(spot[0]), Double(spot[1]))
            items.append((Double(spot[0] + spot[1]) + 0.5, .camp(point.x, point.y + 6, camp.source != nil)))
            let from = camp.start.formatted(date: .omitted, time: .shortened), to = camp.end.formatted(date: .omitted, time: .shortened)
            labels.append(Label(x: point.x + 2, y: spot[1] > roadJ.1 ? point.y + 18 : point.y - 16,
                                title: camp.source == nil ? "\(from)–\(to) · нет данных" : "\(from)–\(to) · \(duration(camp.minutes))",
                                kind: .camp(known: camp.source != nil)))
        }

        // Поселения, квесты и флажки каждого дня.
        var preferAbove = true
        for (dayIndex, day) in week.days.enumerated() {
            let offset = Double(dayIndex) * 24
            for (index, settlement) in day.settlements.enumerated() {
                let center = Int(roadI(offset + (settlement.startHour + settlement.endHour) / 2).rounded())
                let shape = footprint(settlement)
                var placed: (above: Bool, tiles: [[Int]], heights: [Int])?
                search: for above in [preferAbove, !preferAbove] {
                    for shift in 0..<3 {
                        for nudge in [0, -1, 1, 2] {
                            let tiles = shape.map { part -> [Int] in
                                [center + part.di + nudge, above ? roadJ.0 - 1 - part.away - shift : roadJ.1 + 1 + part.away + shift]
                            }
                            if tiles.allSatisfy({ $0[0] >= 0 && $0[0] < gridI && $0[1] >= 0 && $0[1] < gridJ && !used.contains($0) }) {
                                placed = (above, tiles, shape.map(\.height))
                                break search
                            }
                        }
                    }
                }
                guard let placed else { continue }
                preferAbove = !placed.above
                let roof = MapStyle.roofs[(dayIndex + index) % MapStyle.roofs.count]
                for (tile, height) in zip(placed.tiles, placed.heights) {
                    used.insert(tile)
                    items.append((Double(tile[0] + tile[1]), .house(tile[0], tile[1], height, roof)))
                }
                let near = placed.tiles[0]
                let point = iso(Double(near[0]), Double(near[1]))
                labels.append(Label(x: point.x + 4, y: placed.above ? point.y - (placed.heights.max() ?? 6) - 8 : point.y + tile.h + 12,
                                    title: settlement.titles.joined(separator: " + "), kind: .settlement(city: settlement.kind == .city)))
                for k in 0..<min(settlement.attendees, 2) {
                    let pj = placed.above ? Double(near[1]) - 0.9 : Double(roadJ.1) + 0.2
                    let pi = Double(near[0]) + 0.2 + Double(k) * 0.55
                    items.append((pi + pj, .person(pi, pj, villagers[(index + k) % villagers.count], MapStyle.roofs[(index + k + 1) % MapStyle.roofs.count])))
                }
            }
            for marker in day.questMarkers {
                let (x, y) = iso(roadI(offset + marker.hour), Double(roadJ.1) + 0.3)
                PixelMapRenderer.flag(&buffer, x: x, baseY: y + 4, height: 9, color: MapStyle.questColor(done: marker.isDone))
            }
            for mood in day.moodFlags {
                let (x, y) = iso(roadI(offset + mood.hour), Double(roadJ.0) - 0.1)
                PixelMapRenderer.flag(&buffer, x: x, baseY: y + 4, height: 7, color: MapStyle.moodColor(mood.mood))
            }
        }

        // Кусты и заборы у дороги.
        for _ in 0..<(gridI / 2) {
            let i = random.int(gridI), j = random.int(gridJ)
            guard !used.contains([i, j]) else { continue }
            used.insert([i, j])
            items.append((Double(i + j), .bush(i, j)))
        }
        for _ in 0..<(gridI / 12) {
            let i = random.int(gridI - 3), j = random.pick([roadJ.0 - 2, roadJ.1 + 2])
            guard (0..<3).allSatisfy({ !used.contains([i + $0, j]) }) else { continue }
            for k in 0..<3 { used.insert([i + k, j]) }
            items.append((Double(i + j), .fence(i, j)))
        }
        // Деревья — на свободных клетках поля.
        var trees = 0, attempts = 0
        while trees < gridI * 3, attempts < gridI * 40 {
            attempts += 1
            let i = random.int(gridI), j = random.int(gridJ)
            guard !used.contains([i, j]) else { continue }
            used.insert([i, j])
            items.append((Double(i + j), .tree(i, j)))
            trees += 1
        }
        // Лес и кусты за краями поля — сплошная текстура по всему экрану.
        for _ in 0..<(gridI * 40) {
            let i = random.int(gridI + 2 * ext) - ext, j = random.int(gridJ + 2 * ext) - ext
            let outside = i < 0 || i >= gridI || j < 0 || j >= gridJ
            guard outside, j != roadJ.0, j != roadJ.1, j != riverJ, onScreen(i, j), !used.contains([i, j]) else { continue }
            used.insert([i, j])
            items.append((Double(i + j), random.int(4) == 0 ? .bush(i, j) : .tree(i, j)))
        }
        if let hour = week.heroHour { items.append((roadI(hour) + roadMid + 0.6, .hero(hour))) }
        items.sort { $0.depth < $1.depth }

        for (_, item) in items {
            switch item {
            case let .house(i, j, height, roof): box(&buffer, i, j, height: height, roof: roof)
            case let .tree(i, j): tree(&buffer, i, j, biome: biome(i), random: &random)
            case let .person(i, j, look, color):
                let (x, y) = iso(i, j)
                PixelMapRenderer.drawHero(&buffer, appearance: look, accent: color, centerX: x, feetY: y + 4)
            case let .hero(hour):
                if let appearance {
                    let (x, y) = iso(roadI(hour), roadMid)
                    PixelMapRenderer.drawHero(&buffer, appearance: appearance, accent: accent, centerX: x, feetY: y + 6)
                }
            case let .camp(x, y, known): camp(&buffer, x: x, y: y, known: known)
            case let .sign(x, y): signpost(&buffer, x: x, y: y)
            case let .bush(i, j): bush(&buffer, i, j, random: &random)
            case let .fence(i, j): fence(&buffer, from: i, j: j)
            }
        }

        // Погода по дням: облака, дождь или снег над участком дня.
        for (index, day) in week.days.enumerated() where day.weather != .clear {
            let i0 = Double(index * tilesPerDay + 2), i1 = i0 + Double(tilesPerDay)
            for _ in 0..<3 {
                let point = iso(i0 + random.unit() * (i1 - i0), random.unit() * Double(gridJ))
                let cy = point.y - 40, rw = 12 + random.int(8)
                for dx in -rw...rw {
                    for dy in -3...3 where Double(dx * dx) / Double(rw * rw) + Double(dy * dy) / 12.25 < 1 {
                        if let p = buffer.get(point.x + dx, cy + dy) { buffer.set(point.x + dx, cy + dy, PixelColor.mix(p, 0xECEEF0, 0.7)) }
                    }
                }
            }
            guard day.weather == .rain || day.weather == .snow else { continue }
            for _ in 0..<500 {
                let point = iso(i0 + random.unit() * (i1 - i0), random.unit() * Double(gridJ))
                let y = point.y - random.int(50)
                if day.weather == .snow {
                    buffer.set(point.x, y, 0xFFFFFF)
                } else {
                    for k in 0..<3 { if let p = buffer.get(point.x - k / 2, y + k) { buffer.set(point.x - k / 2, y + k, PixelColor.mix(p, 0x6E87AA, 0.7)) } }
                }
            }
        }
        return Rendered(image: buffer.image, labels: labels)
    }
}
