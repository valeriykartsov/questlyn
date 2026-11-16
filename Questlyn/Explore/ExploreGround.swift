import CoreGraphics
import Foundation
import Domain

/// Земля острова кусками (15A.5): кусок — 16×16 клеток, рисуется в фоне и только рядом с камерой.
/// Автотайлинг переходов дизерингом, глубина воды и пена, горы со склонами, дороги по износу, деревья и постройки зон.
nonisolated final class ExploreGround: Sendable {
    static let chunk = 16
    /// Запас над куском для гор, деревьев и построек, px.
    static let topMargin = 64
    static let deepWater: UInt32 = 0x2B5884

    let island: Island
    let side: Int
    let chunksPerSide: Int
    /// Для воды — расстояние до суши, для суши — до воды (не больше 9).
    private let distance: [UInt8]
    private let plaza: Set<Int>
    private let sprites: [RGBACanvas]
    /// Предметы куска: глубина, низ-центр в пикселях острова, номер спрайта.
    private let items: [Int: [(depth: Double, x: Int, y: Int, sprite: Int)]]

    init(island: Island) {
        self.island = island
        side = island.side
        chunksPerSide = (island.side + Self.chunk - 1) / Self.chunk
        let side = island.side
        var dist = [Int](repeating: Int.max, count: side * side)
        var queue: [Int] = [], head = 0
        // Два поля сразу: источники — клетки на границе вода/суша.
        for index in 0..<(side * side) {
            let x = index % side, y = index / side, water = island.terrain[index] == .water
            let border = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { dx, dy in
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < side, ny < side else { return !water }
                return (island.terrain[ny * side + nx] == .water) != water
            }
            if border { dist[index] = 1; queue.append(index) }
        }
        while head < queue.count {
            let current = queue[head]; head += 1
            let x = current % side, y = current / side, water = island.terrain[current] == .water
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < side, ny < side else { continue }
                let next = ny * side + nx
                guard (island.terrain[next] == .water) == water, dist[next] > dist[current] + 1 else { continue }
                dist[next] = dist[current] + 1
                queue.append(next)
            }
        }
        distance = dist.map { UInt8(min(9, $0)) }

        // Спрайты: деревья 5 зон × 2, дома 5 × 2, затем колодец, прилавки, храмы, доска, кол.
        var sprites: [RGBACanvas] = []
        for zone in ClimateZone.allCases { sprites.append(ExploreSprites.tree(zone, dark: false)); sprites.append(ExploreSprites.tree(zone, dark: true)) }
        for zone in ClimateZone.allCases { sprites += ExploreSprites.houses(zone) }
        let well = sprites.count; sprites.append(ExploreSprites.well())
        let stalls = sprites.count; sprites.append(ExploreSprites.stall(0xA8432F)); sprites.append(ExploreSprites.stall(0x3E5C8A))
        let temples = sprites.count; for zone in ClimateZone.allCases { sprites.append(ExploreSprites.temple(zone)) }
        let board = sprites.count; sprites.append(ExploreSprites.boardPost())
        let stake = sprites.count; sprites.append(ExploreSprites.stake())
        self.sprites = sprites

        var items: [Int: [(depth: Double, x: Int, y: Int, sprite: Int)]] = [:]
        var plaza = Set<Int>()
        let chunks = chunksPerSide
        func add(_ tile: TilePoint, _ sprite: Int, dx: Int = 0, dy: Int = 0, depthShift: Double = 0) {
            guard tile.x >= 0, tile.y >= 0, tile.x < side, tile.y < side else { return }
            let p = ExploreRenderer.pixel(x: Double(tile.x), y: Double(tile.y), side: side)
            let key = (tile.y / Self.chunk) * chunks + tile.x / Self.chunk
            items[key, default: []].append((Double(tile.x + tile.y) + depthShift, Int(p.x) + dx, Int(p.y) + dy, sprite))
        }
        func walkable(_ tile: TilePoint) -> Bool { island.isWalkable(tile) }
        // Город (15A.7): площадь 3×3 с колодцем, прилавки, доска, храм, дома вокруг, частокол по задним сторонам.
        var built = Set<Int>()
        for city in island.cities {
            let c = city.center, zone = island.zone(at: c)
            for dy in -1...1 { for dx in -1...1 where walkable(TilePoint(c.x + dx, c.y + dy)) {
                plaza.insert((c.y + dy) * side + c.x + dx)
            } }
            add(c, well, dy: 4)
            add(TilePoint(c.x - 1, c.y + 1), stalls, dy: 3, depthShift: 0.2)
            add(TilePoint(c.x + 1, c.y - 1), stalls + 1, dy: 3, depthShift: 0.1)
            add(TilePoint(c.x - 1, c.y - 1), board, dy: 2)
            let templeTile = TilePoint(c.x - 3, c.y - 3)
            if walkable(templeTile) { add(templeTile, temples + zone.rawValue, dy: 3); built.insert(templeTile.y * side + templeTile.x) }
            let count = city.houses >= 10 ? 8 : city.houses >= 6 ? 6 : 4
            let offsets = [(-3, 0), (0, -3), (3, -1), (-1, 3), (3, 2), (2, 3), (-3, 2), (2, -3)]
            for (k, offset) in offsets.prefix(count).enumerated() {
                let tile = TilePoint(c.x + offset.0, c.y + offset.1)
                guard walkable(tile) else { continue }
                add(tile, 10 + zone.rawValue * 2 + k % 2, dy: 3)
                built.insert(tile.y * side + tile.x)
            }
            for k in -4...4 where abs(k) > 1 {
                let left = TilePoint(c.x - 4, c.y + k), back = TilePoint(c.x + k, c.y - 4)
                // Частокол сплошной: по 4 кола на клетку вдоль края.
                for step in 0..<4 {
                    if walkable(left) { add(left, stake, dx: -4 - step * 2, dy: -2 + step, depthShift: -0.6) }
                    if walkable(back) { add(back, stake, dx: 4 + step * 2, dy: -2 + step, depthShift: -0.6) }
                }
            }
        }
        for village in island.villages {
            let zone = island.zone(at: village.center)
            for (k, offset) in [(0, 0), (1, 1)].enumerated() {
                let tile = TilePoint(village.center.x + offset.0, village.center.y + offset.1)
                guard walkable(tile) else { continue }
                add(tile, 10 + zone.rawValue * 2 + k % 2, dy: 3)
                built.insert(tile.y * side + tile.x)
            }
        }
        // Деревья — на лесных клетках, густота по зоне; на дорогах и площадях — нет.
        let density: [ClimateZone: Double] = [.tundra: 0.35, .taiga: 0.75, .temperate: 0.6, .steppe: 0.18, .desert: 0.1]
        for y in 0..<side { for x in 0..<side where island.terrain[y * side + x] == .forest {
            let index = y * side + x
            guard island.roadAt.isEmpty || island.roadAt[index] < 0, !plaza.contains(index), !built.contains(index) else { continue }
            let zone = island.zone(at: TilePoint(x, y))
            guard Pix.hash(x, y, 31) < density[zone] ?? 0.5 else { continue }
            add(TilePoint(x, y), zone.rawValue * 2 + (Pix.hash(x, y, 32) < 0.5 ? 1 : 0), dy: 1)
        } }
        for key in items.keys { items[key]?.sort { $0.depth < $1.depth } }
        self.items = items
        self.plaza = plaza
    }

    // MARK: Кусок

    struct Chunk: Sendable {
        let image: CGImage?
        /// Левый верхний угол в пикселях острова.
        let left: Int
        let top: Int
    }

    /// Нарисовать кусок (cx, cy); nil — сплошная глубокая вода (её даёт фон сцены).
    func render(cx: Int, cy: Int) -> Chunk? {
        let k = Self.chunk, x0 = cx * k, y0 = cy * k
        guard x0 < side, y0 < side else { return nil }
        var empty = true
        for y in y0..<min(side, y0 + k) { for x in x0..<min(side, x0 + k) {
            let i = y * side + x
            if island.terrain[i] != .water || distance[i] < 6 { empty = false; break }
        } }
        guard !empty else { return nil }
        let origin = ExploreRenderer.pixel(x: Double(x0), y: Double(y0 + k - 1), side: side)
        let top = ExploreRenderer.pixel(x: Double(x0), y: Double(y0), side: side)
        let left = Int(origin.x) - ExploreRenderer.tileW / 2
        let topY = Int(top.y) - ExploreRenderer.tileH / 2 - Self.topMargin
        var canvas = RGBACanvas(width: k * ExploreRenderer.tileW, height: k * ExploreRenderer.tileH + Self.topMargin, fill: nil)
        for d in 0..<(2 * k - 1) {
            for lx in 0...d where lx < k {
                let ly = d - lx
                guard ly < k else { continue }
                let x = x0 + lx, y = y0 + ly
                guard x < side, y < side else { continue }
                let p = ExploreRenderer.pixel(x: Double(x), y: Double(y), side: side)
                drawTile(&canvas, x: x, y: y, cx: Int(p.x) - left, cy: Int(p.y) - topY)
            }
        }
        for item in items[cy * chunksPerSide + cx] ?? [] {
            let sprite = sprites[item.sprite]
            canvas.draw(sprite, at: item.x - left - sprite.width / 2, item.y - topY - sprite.height + 1)
        }
        return Chunk(image: canvas.image, left: left, top: topY)
    }

    private enum Kind: Equatable { case water, sand, ground, mountain }

    private func kind(_ x: Int, _ y: Int) -> Kind {
        guard x >= 0, y >= 0, x < side, y < side else { return .water }
        switch island.terrain[y * side + x] {
        case .water: return .water
        case .sand: return .sand
        case .mountain: return .mountain
        case .grass, .forest: return .ground
        }
    }

    private static let palettes: [ClimateZone: (g0: UInt32, g1: UInt32, detail: UInt32)] = [
        .tundra: (0xE6ECF0, 0xDCE3E8, 0xC5CFD6), .taiga: (0x7E9A6A, 0x75915F, 0x5E7A50), .temperate: (0x7FA552, 0x76994B, 0x5E8540),
        .steppe: (0xC2B56E, 0xB8AA62, 0x9C8E4E), .desert: (0xE8CF8E, 0xDFC383, 0xCDAE6C),
    ]
    private static let shallow: UInt32 = 0x6A9CC2, mid: UInt32 = 0x3F6E9C, foam: UInt32 = 0xE6F0F4

    private func waterColor(_ x: Int, _ y: Int) -> UInt32 {
        guard x >= 0, y >= 0, x < side, y < side else { return Self.deepWater }
        let d = distance[y * side + x]
        return d <= 1 ? Self.shallow : d == 2 ? Pix.mix(Self.shallow, Self.mid, 0.6) : d < 6 ? Self.mid : Self.deepWater
    }

    /// Плавный шум травы: пятна, а не шахматка клеток.
    private func fineNoise(_ wx: Double, _ wy: Double) -> Double {
        let fx = (wx + 0.5) * 3 / 5, fy = (wy + 0.5) * 3 / 5
        let i = Int(fx.rounded(.down)), j = Int(fy.rounded(.down))
        var tx = fx - Double(i), ty = fy - Double(j)
        tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty)
        let a = Pix.hash(i, j, 71) * (1 - tx) + Pix.hash(i + 1, j, 71) * tx
        let b = Pix.hash(i, j + 1, 71) * (1 - tx) + Pix.hash(i + 1, j + 1, 71) * tx
        return a * (1 - ty) + b * ty
    }

    private func groundColor(_ x: Int, _ y: Int, wx: Double, wy: Double, sx: Int, sy: Int) -> UInt32 {
        let zone = island.zone(at: TilePoint(x, y))
        let palette = Self.palettes[zone]!
        let v = fineNoise(wx, wy)
        var c = v + (Pix.hash(sx, sy, 11) - 0.5) * 0.12 > 0.62 ? Pix.shade(palette.g0, 1.04) : (v > 0.42 ? palette.g0 : palette.g1)
        if zone == .tundra, (sx / 3 + sy) % 7 == 0, Pix.hash(sx / 6, sy / 3, 13) < 0.5 { c = 0xCFD8DF }
        if Pix.hash(sx, sy, 5) < 0.08 { c = palette.detail }
        return c
    }

    private func drawTile(_ canvas: inout RGBACanvas, x: Int, y: Int, cx: Int, cy: Int) {
        let tw = ExploreRenderer.tileW, th = ExploreRenderer.tileH
        let me = kind(x, y)
        let zone = island.zone(at: TilePoint(x, y))
        let elevation = me == .mountain ? island.height(at: TilePoint(x, y)) : 0
        let desert = zone == .desert
        let rock: UInt32 = desert ? 0xC9A57A : 0x9A9284
        let snowy = elevation >= ExploreRules.snowLineHeight
        // Склоны гор.
        if elevation > 0 {
            let sideL: UInt32 = desert ? 0xA8865E : 0x7A7368, sideR: UInt32 = desert ? 0x8E6E4C : 0x625C53
            for dx in (-tw / 2)..<(tw / 2) {
                // Нижняя кромка ромба клетки в этом столбце — та же, что у заливки ромба ниже.
                var bottom = 0
                for py in 0..<th {
                    let half = py < th / 2 ? (py + 1) * 2 : (th - py) * 2
                    if dx >= -half && dx < half { bottom = py }
                }
                let base = cy - th / 2 + bottom
                for dy in 0...elevation {
                    canvas.set(cx + dx, base - dy, Pix.shade(dx < 0 ? sideL : sideR, 0.92 + 0.08 * Pix.hash(cx + dx, dy, 3)))
                }
            }
        }
        let road = island.road(at: TilePoint(x, y))
        let isPlaza = plaza.contains(y * side + x)
        for py in 0..<th {
            let half = py < th / 2 ? (py + 1) * 2 : (th - py) * 2
            for dx in -half..<half {
                let sx = cx + dx, sy = cy - th / 2 + py - elevation
                let ddx = Double(dx) + 0.5, ddy = Double(py) - Double(th) / 2 + 0.5
                let fx = (ddx / Double(tw / 2) + ddy / Double(th / 2)) / 2
                let fy = (ddy / Double(th / 2) - ddx / Double(tw / 2)) / 2
                let h = Pix.hash(sx, sy, 11)
                var c: UInt32
                switch me {
                case .water:
                    c = waterColor(x, y)
                    if Pix.hash(sx, sy, 6) < 0.025 { c = Pix.mix(c, 0xFFFFFF, 0.35) }
                case .sand:
                    c = Pix.hash(sx, sy, 7) < 0.06 ? Pix.shade(0xE3CF9A, 0.92) : 0xE3CF9A
                case .mountain:
                    c = snowy ? (fy > 0.1 && Pix.hash(sx, sy, 8) < 0.5 ? 0xD5DCE2 : 0xF2F4F6) : (Pix.hash(sx, sy, 14) < 0.12 ? Pix.shade(rock, 0.88) : rock)
                    if snowy && desert { c = 0xB88E62 }
                case .ground:
                    c = groundColor(x, y, wx: Double(x) + fx, wy: Double(y) + fy, sx: sx, sy: sy)
                }
                // Автотайлинг: у края с соседом другого типа (или другой зоны) — дизеринг в цвет соседа, пена у берега.
                if me != .mountain {
                    for (nx, ny, dist) in [(x - 1, y, fx + 0.5), (x + 1, y, 0.5 - fx), (x, y - 1, fy + 0.5), (x, y + 1, 0.5 - fy)] where dist < 0.32 {
                        let other = kind(nx, ny)
                        let t = (0.32 - dist) / 0.32
                        if me == .water {
                            guard other != .water else { continue }
                            c = dist < 0.09 && h < 0.8 ? Pix.mix(c, Self.foam, 0.75) : Pix.mix(c, Self.shallow, t * 0.8)
                        } else if other == .water {
                            if dist < 0.08 { c = Pix.mix(c, 0xEFE2BC, 0.6) }
                        } else if other == .mountain {
                            continue
                        } else if other != me || (me == .ground && island.zone(at: TilePoint(nx, ny)) != zone) {
                            if h < t * 0.55 {
                                c = other == .sand ? 0xE3CF9A : groundColor(nx, ny, wx: Double(x) + fx, wy: Double(y) + fy, sx: sx, sy: sy)
                            }
                        }
                    }
                }
                if isPlaza {
                    c = Pix.hash(sx, sy, 21) < 0.8 ? 0xB9AE9A : 0x8E8574
                    if (sx + 2 * sy) % 8 == 0 { c = 0xA79C87 }
                } else if let road, me != .water {
                    let rx = Double(dx) / Double(tw / 2), ry = (Double(py) - Double(th) / 2) / Double(th / 2)
                    if abs(rx) + abs(ry) < 0.82 {
                        let hr = Pix.hash(sx, sy, 21)
                        switch road.wear {
                        case .paved:
                            c = hr < 0.82 ? 0xB9AE9A : 0x8E8574
                            if (sx + sy) % 4 == 0 && hr < 0.5 { c = 0xA79C87 }
                        case .dirt: c = hr < 0.9 ? 0xA88A5E : 0x8E7450
                        case .overgrown: if hr < 0.5 { c = 0xA88A5E }
                        case .faint: if hr < 0.18 { c = 0xA88A5E }
                        }
                    }
                }
                canvas.set(sx, sy, c)
            }
        }
    }
}
