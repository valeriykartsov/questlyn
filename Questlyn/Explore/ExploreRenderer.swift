import CoreGraphics
import Foundation
import Domain

/// Рисование острова «Побродить» (8B): изометрия клеток 16×8 в стиле большой карты, спрайты с прозрачностью.
enum ExploreRenderer {
    static let tileW = 16
    static let tileH = 8
    static let padding = 40

    /// Размер картинки острова в пикселях.
    static func imageSize(side: Int) -> (width: Int, height: Int) {
        (side * tileW + padding * 2, side * tileH + padding * 2)
    }

    /// Центр клетки в пикселях картинки (y вниз).
    static func pixel(x: Double, y: Double, side: Int) -> (x: Double, y: Double) {
        let originX = Double(side * tileW / 2 + padding)
        let originY = Double(padding)
        return (originX + (x - y) * Double(tileW / 2), originY + (x + y) * Double(tileH / 2) + Double(tileH / 2))
    }

    /// Обратное преобразование: пиксель картинки → клетка (дробная).
    static func tile(px: Double, py: Double, side: Int) -> (x: Double, y: Double) {
        let originX = Double(side * tileW / 2 + padding)
        let u = (px - originX) / Double(tileW / 2)
        let v = (py - Double(padding) - Double(tileH / 2)) / Double(tileH / 2)
        return ((u + v) / 2, (v - u) / 2)
    }

    // MARK: Остров

    static func islandImage(_ island: Island, seed: UInt64) -> CGImage? {
        let side = island.side
        let size = imageSize(side: side)
        var canvas = RGBACanvas(width: size.width, height: size.height, fill: 0x3F6E9C)
        var random = ExploreRandom(seed ^ 0xA5A5)
        // Вода с рябью.
        for _ in 0..<(size.width * size.height / 60) {
            canvas.set(random.int(size.width), random.int(size.height), random.unit() < 0.5 ? 0x4A7BAA : 0x36628D)
        }
        // Клетки — по глубине.
        for depth in 0..<(side * 2 - 1) {
            for x in 0...depth where x < side {
                let y = depth - x
                guard y < side else { continue }
                let terrain = island.terrain[y * side + x]
                guard terrain != .water else { continue }
                let center = pixel(x: Double(x), y: Double(y), side: side)
                let base: UInt32 = switch terrain {
                case .sand: 0xE3CF9A
                case .forest: 0x7E9656
                default: random.unit() < 0.5 ? 0x9DB06A : 0x93A762
                }
                diamond(&canvas, cx: Int(center.x), cy: Int(center.y), color: base)
                if terrain == .sand, island.terrain(at: TilePoint(x, y + 1)) == .water || island.terrain(at: TilePoint(x + 1, y)) == .water {
                    // Кромка берега.
                    for dx in -3...3 { canvas.set(Int(center.x) + dx, Int(center.y) + 4, 0xC9B27A) }
                }
                if terrain == .grass, random.unit() < 0.15 {
                    canvas.set(Int(center.x) + random.int(6) - 3, Int(center.y) + random.int(3) - 1, 0x6E8A4A)
                }
            }
        }
        // Деревья и дома — по глубине, чтобы ближние перекрывали дальние.
        var items: [(depth: Double, draw: (inout RGBACanvas) -> Void)] = []
        for y in 0..<side { for x in 0..<side where island.terrain[y * side + x] == .forest && random.unit() < 0.55 {
            let c = pixel(x: Double(x), y: Double(y), side: side)
            let shade = random.unit() < 0.5
            items.append((Double(x + y), { tree(&$0, x: Int(c.x), y: Int(c.y), dark: shade) }))
        } }
        let roofs: [UInt32] = [0xB8651B, 0x8A4B3A, 0x3E5C8A, 0x2F6B4F, 0x6B4FA3]
        for (index, place) in (island.cities + island.villages).enumerated() {
            for (k, offset) in houseOffsets.prefix(place.houses).enumerated() {
                let hx = Double(place.center.x + offset.0), hy = Double(place.center.y + offset.1)
                let c = pixel(x: hx, y: hy, side: side)
                let roof = roofs[(index + k) % roofs.count]
                let tall = place.isCity ? 9 + (k % 3) * 2 : 7
                items.append((hx + hy + 0.5, { house(&$0, x: Int(c.x), y: Int(c.y), height: tall, roof: roof) }))
            }
        }
        for item in items.sorted(by: { $0.depth < $1.depth }) { item.draw(&canvas) }
        return canvas.image
    }

    /// Клетки домов вокруг центра города.
    static let houseOffsets: [(Int, Int)] = [(0, 0), (1, -1), (-1, 1), (1, 1), (-1, -1), (2, 0), (0, 2), (-2, 0), (0, -2), (2, 2)]

    static func diamond(_ canvas: inout RGBACanvas, cx: Int, cy: Int, color: UInt32) {
        for dy in 0..<tileH {
            let half = dy < tileH / 2 ? (dy + 1) * 2 : (tileH - dy) * 2
            for dx in -half..<half { canvas.set(cx + dx, cy - tileH / 2 + dy, color) }
        }
    }

    static func tree(_ canvas: inout RGBACanvas, x: Int, y: Int, dark: Bool) {
        for k in 0..<3 { canvas.set(x, y - k, 0x5C3A1E) }
        let leaf: UInt32 = dark ? 0x3F5E31 : 0x4E6E3A
        for dy in 0..<5 {
            let half = dy < 3 ? dy + 1 : 5 - dy
            for dx in -half...half { canvas.set(x + dx, y - 3 - (4 - dy), leaf) }
        }
        canvas.set(x - 1, y - 6, 0x6E8A4A)
    }

    static func house(_ canvas: inout RGBACanvas, x: Int, y: Int, height: Int, roof: UInt32) {
        for dy in 0..<height { for dx in -5...5 {
            canvas.set(x + dx, y - dy, dx < 0 ? 0xE9DCC0 : 0xCDBE9E)
        } }
        canvas.set(x - 2, y, 0x5C3A1E); canvas.set(x - 2, y - 1, 0x5C3A1E); canvas.set(x - 2, y - 2, 0x5C3A1E)
        for dy in 0..<5 {
            let half = 6 - dy
            for dx in -half...half { canvas.set(x + dx, y - height - dy, PixelShade.darken(roof, dx > 0 ? 0.15 : 0)) }
        }
    }

    // MARK: Мини-карта

    /// Вид сверху: клетка — пиксель.
    static func minimap(_ island: Island) -> CGImage? {
        var canvas = RGBACanvas(width: island.side, height: island.side, fill: 0x3F6E9C)
        for (index, terrain) in island.terrain.enumerated() {
            let color: UInt32? = switch terrain {
            case .water: nil
            case .sand: 0xE3CF9A
            case .grass: 0x9DB06A
            case .forest: 0x6E8A4A
            }
            if let color { canvas.set(index % island.side, index / island.side, color) }
        }
        for city in island.cities {
            for dx in -1...1 { for dy in -1...1 { canvas.set(city.center.x + dx, city.center.y + dy, 0x1F2A44) } }
        }
        return canvas.image
    }

    // MARK: Спрайты

    /// Герой или житель в половинном масштабе (16×28), с прозрачным фоном.
    static func person(_ appearance: HeroAppearance, accent: UInt32) -> CGImage? {
        let rows = PixelMapRenderer.heroRows(appearance)
        let palette = HeroPalette.colors(for: appearance, accent: accent)
        let width = rows.map(\.count).max() ?? 16
        var canvas = RGBACanvas(width: width, height: rows.count, fill: nil)
        for (y, row) in rows.enumerated() { for (x, ch) in row.enumerated() { if let color = palette[ch] { canvas.set(x, y, color) } } }
        return canvas.image
    }

    static func chest(opened: Bool) -> CGImage? {
        var canvas = RGBACanvas(width: 10, height: 9, fill: nil)
        for y in 2..<9 { for x in 0..<10 { canvas.set(x, y, y == 2 || y == 8 || x == 0 || x == 9 ? 0x5C3410 : 0xB8651B) } }
        if opened { for x in 1..<9 { canvas.set(x, 3, 0x2B1A0A); canvas.set(x, 4, 0x2B1A0A) } }
        else { for x in 0..<10 { canvas.set(x, 0, 0x5C3410); canvas.set(x, 1, 0x9A5214) } }
        canvas.set(4, 5, 0xF2D27A); canvas.set(5, 5, 0xF2D27A)
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
struct RGBACanvas {
    let width: Int
    let height: Int
    private var bytes: [UInt8]

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
