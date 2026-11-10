import CoreGraphics
import Foundation
import Domain

/// Изометрическая дорога недели (02 от 11.11.2026): семь дней подряд, привалы сна, поселения, погода по дням.
/// Рисуется один раз на неделю; экран показывает окно вокруг точки ползунка.
enum WeekMapRenderer {
    static let tilesPerDay = 16
    static let gridI = 7 * tilesPerDay + 4
    static let gridJ = 10
    static let tile = (w: 16, h: 8)
    static let origin = (x: gridJ * 8 + 4, y: 34)
    static let size = (width: (gridI + gridJ) * 8 + 8, height: 34 + (gridI + gridJ) * 4 + 8)
    /// Окно на экране — как прежний обзор дня.
    static let viewport = (width: 232, height: 150)
    static let roadJ = (4, 5)

    static func iso(_ i: Double, _ j: Double) -> (x: Int, y: Int) {
        (Int((Double(origin.x) + (i - j) * Double(tile.w) / 2).rounded()), Int((Double(origin.y) + (i + j) * Double(tile.h) / 2).rounded()))
    }

    /// Час недели → клетка вдоль дороги.
    static func roadI(_ weekHour: Double) -> Double { 2 + min(max(weekHour, 0), WeekMap.hours) / WeekMap.hours * Double(7 * tilesPerDay) }

    /// Центр дороги в пикселях для часа недели — сюда наводится окно.
    static func roadPoint(_ weekHour: Double) -> (x: Int, y: Int) { iso(roadI(weekHour), 4.5) }

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
            for y in (bottom - height)...bottom { buffer.set(x, y, x < sx ? MapStyle.wallLeft : MapStyle.wallRight) }
        }
        for row in 0..<tile.h {
            let hw = (row < tile.h / 2 ? row : tile.h - 1 - row) * 2 + 2
            for x in (sx - hw)..<(sx + hw) { buffer.set(x, sy + row - height - 1, roof) }
        }
        for k in 0..<3 {
            for x in (sx - 4 + k)..<(sx + 4 - k) { buffer.set(x, sy - height - 1 + tile.h / 2 - 2 - k, roof) }
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
        var buffer = PixelBuffer(width: size.width, height: size.height, fill: 0xE7DCC4)
        func dayIndex(_ i: Int) -> Int { min(6, max(0, (i - 2) / tilesPerDay)) }
        let biomes = week.days.map { Biome.of($0.season) }
        func biome(_ i: Int) -> Biome { biomes.isEmpty ? Biome.of(.autumn) : biomes[min(dayIndex(i), biomes.count - 1)] }

        for sum in 0..<(gridI + gridJ) {
            for i in 0..<gridI {
                let j = sum - i
                guard j >= 0, j < gridJ else { continue }
                let b = biome(i)
                if j == roadJ.0 || j == roadJ.1 {
                    diamond(&buffer, i, j, (i + j) % 2 == 0 ? b.road.1 : b.road.0, edge: j == roadJ.1 ? b.road.edge : nil)
                } else {
                    diamond(&buffer, i, j, random.pick(b.grass))
                }
            }
        }

        enum Item { case house(Int, Int, Int, UInt32), tree(Int, Int), person(Double, Double, HeroAppearance, UInt32), hero(Double), camp(Int, Int, Bool), sign(Int, Int) }
        var items: [(depth: Double, item: Item)] = []
        var labels: [Label] = []
        var used = Set<[Int]>()
        for j in [roadJ.0, roadJ.1] { for i in 0..<gridI { used.insert([i, j]) } }

        // Границы дней — столбы у дороги и подписи.
        for (index, day) in week.days.enumerated() {
            let i = Int(roadI(Double(index) * 24).rounded())
            let sign = iso(Double(i), 3.6)
            items.append((Double(i) + 3.6, .sign(sign.x, sign.y + 4)))
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
                let (x, y) = iso(roadI(offset + marker.hour), 5.3)
                PixelMapRenderer.flag(&buffer, x: x, baseY: y + 4, height: 9, color: MapStyle.questColor(done: marker.isDone))
            }
            for mood in day.moodFlags {
                let (x, y) = iso(roadI(offset + mood.hour), 3.9)
                PixelMapRenderer.flag(&buffer, x: x, baseY: y + 4, height: 7, color: MapStyle.moodColor(mood.mood))
            }
        }

        // Деревья — на свободных клетках, примерно как раньше по плотности.
        var trees = 0, attempts = 0
        while trees < gridI, attempts < gridI * 20 {
            attempts += 1
            let i = random.int(gridI), j = random.int(gridJ)
            guard !used.contains([i, j]) else { continue }
            used.insert([i, j])
            items.append((Double(i + j), .tree(i, j)))
            trees += 1
        }
        if let hour = week.heroHour { items.append((roadI(hour) + 4.5 + 0.6, .hero(hour))) }
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
                    let (x, y) = iso(roadI(hour), 4.5)
                    PixelMapRenderer.drawHero(&buffer, appearance: appearance, accent: accent, centerX: x, feetY: y + 6)
                }
            case let .camp(x, y, known): camp(&buffer, x: x, y: y, known: known)
            case let .sign(x, y): signpost(&buffer, x: x, y: y)
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
