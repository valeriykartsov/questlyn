import Foundation
import Domain

/// Сборка героя из деталей (10.1): зоны спрайта 32×56 берутся из разных образов, каждая — в цветах своего образа.
/// Голова (причёска) — строки 0–23, головной убор — поверх строк 0–14, верх — 24–40 по центру (столбцы 10–21),
/// «в руке» — бока строк 24–51, низ — 41–51 по центру, обувь — 52–55. Латная юбка шире центра и перекрывает бока.
enum HeroComposer {
    static let size = (width: 32, height: 56)

    /// Цвета пикселей; nil — прозрачно.
    static func colors(_ appearance: HeroAppearance, accent: UInt32) -> [[UInt32?]] {
        let parts = appearance.resolvedParts
        let tint = appearance.accent ?? accent
        func palette(_ outfit: HeroAppearance.Outfit) -> [Character: UInt32] {
            var look = appearance
            look.outfit = outfit
            return HeroPalette.colors(for: look, accent: tint)
        }
        let palettes = Dictionary(uniqueKeysWithValues: HeroAppearance.Outfit.allCases.map { ($0, palette($0)) })
        let rows = Dictionary(uniqueKeysWithValues: HeroAppearance.Outfit.allCases.map { ($0, $0.spriteRows.map(Array.init)) })
        let hairless: Set<Character> = ["H", "h", "S", "s", "E", "."]
        var result = Array(repeating: [UInt32?](repeating: nil, count: size.width), count: size.height)
        for y in 0..<size.height {
            for x in 0..<size.width {
                let core = x >= 10 && x <= 21
                var source: HeroAppearance.Outfit
                var char: Character
                // С оружием (17.11.2026) руки опущены, как у «Ассасина» (до кистей), ниже — без предмета.
                let sides: HeroAppearance.Outfit = parts.weapon == nil ? parts.item : (y <= 37 ? .assassin : .coder)
                if y <= 23 { source = parts.hair }
                else if y <= 40 { source = core ? parts.top : sides }
                else if y <= 51 {
                    if case let .outfit(bottom) = parts.bottom { source = core ? bottom : sides }
                    else { source = sides }
                } else { source = parts.shoes }
                char = rows[source]![y][x]
                if let hat = parts.hat, y <= 14 {
                    let over = rows[hat]![y][x]
                    if !hairless.contains(over) { char = over; source = hat }
                }
                // Латная юбка: свои строки 41–51 поверх центра и боков.
                if parts.bottom == .plateSkirt, y >= 41, y <= 51 {
                    let skirt = Array(plateSkirt[y - 41])[x]
                    if skirt != "." { char = skirt; source = .warrior }
                    else if core { char = "." }
                }
                result[y][x] = char == "." ? nil : palettes[source]?[char]
            }
        }
        return result
    }

    /// Оружие поверх тела и позади него, с пальцами поверх рукояти (хват). Координаты — в рисунке 32×56, могут выходить за него.
    static func weaponLayers(_ appearance: HeroAppearance, accent: UInt32) -> (behind: [WeaponArt.Pixel], front: [WeaponArt.Pixel]) {
        guard let weapon = appearance.resolvedParts.weapon else { return ([], []) }
        let layers = WeaponArt.layers(weapon)
        let behind = layers.behind
        var front = layers.front
        // Пальцы — кожа рук «Ассасина» в рядах 35–38 — поверх рукояти.
        var look = appearance
        look.outfit = .assassin
        let palette = HeroPalette.colors(for: look, accent: appearance.accent ?? accent)
        let arms = HeroAppearance.Outfit.assassin.spriteRows.map(Array.init)
        for y in 35...38 { for x in Array(5...10) + Array(21...26) where arms[y][x] == "S" || arms[y][x] == "s" {
            if let color = palette[arms[y][x]] { front.append(WeaponArt.Pixel(x: x, y: y, color: color)) }
        } }
        return (behind, front)
    }

    /// Половинный масштаб (16×28) — для карт.
    static func half(_ appearance: HeroAppearance, accent: UInt32) -> [[UInt32?]] {
        let full = colors(appearance, accent: accent)
        return stride(from: 0, to: full.count, by: 2).map { y in stride(from: 0, to: full[y].count, by: 2).map { full[y][$0] } }
    }

    /// Латная юбка (12.11.2026): широкие пластины до колен, ниже — поножи. Цвета — как у доспеха воина.
    static let plateSkirt: [String] = [
        ".........KMMMMMMMMMMMMK.........",
        "........KMWMMKMMMMKMMWMK........",
        "........KMMMMKMMMMKMMMMK........",
        ".......KMmMMMKmMMmKMMMmMK.......",
        ".......KMmmMMKmmMmKMMmmMK.......",
        "......KmmmmmmKmmmmKmmmmmmK......",
        "......KKKKKKKKKKKKKKKKKKKK......",
        "..........KMmK....KmMK..........",
        "..........KMmK....KmMK..........",
        "..........KWMK....KMWK..........",
        "..........KmmK....KmmK..........",
    ]
}
