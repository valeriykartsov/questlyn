import SwiftUI
import Domain
import Application

/// Пиксельный герой (холст 8.5–8.6): образ, волосы и кожа игрока, цвет акцента — по основной профессии.
struct HeroSprite: View {
    let appearance: HeroAppearance
    var accent: UInt32 = HeroAccent.fallback
    /// Точек на пиксель спрайта. Целые значения дают чёткие края.
    var scale: CGFloat = 2

    static let size = (width: 32, height: 56)

    var body: some View {
        let runs = HeroSprite.runs(appearance: appearance, accent: accent)
        Canvas { context, _ in
            for run in runs {
                let rect = CGRect(x: CGFloat(run.x) * scale, y: CGFloat(run.y) * scale,
                                  width: CGFloat(run.length) * scale, height: scale)
                context.fill(Path(rect.insetBy(dx: 0, dy: -0.25)), with: .color(Color(hex: run.color)))
            }
        }
        .frame(width: CGFloat(Self.size.width) * scale, height: CGFloat(Self.size.height) * scale)
        .accessibilityElement()
        .accessibilityLabel("Герой: \(appearance.outfit.title)")
    }

    private struct Run { let x: Int; let y: Int; let length: Int; let color: UInt32 }

    /// Соседние пиксели одного цвета склеиваются в полосы — меньше фигур и нет швов.
    private static func runs(appearance: HeroAppearance, accent: UInt32) -> [Run] {
        let palette = HeroPalette.colors(for: appearance, accent: accent)
        var result: [Run] = []
        for (y, row) in appearance.outfit.spriteRows.enumerated() {
            var current: (x: Int, color: UInt32)?
            var x = 0
            for character in row {
                let color = palette[character]
                if let open = current, open.color != color {
                    result.append(Run(x: open.x, y: y, length: x - open.x, color: open.color))
                    current = nil
                }
                if current == nil, let color { current = (x, color) }
                x += 1
            }
            if let open = current { result.append(Run(x: open.x, y: y, length: x - open.x, color: open.color)) }
        }
        return result
    }
}

/// Цвета ролей спрайта — как в макете 8.6.
enum HeroPalette {
    static func colors(for appearance: HeroAppearance, accent: UInt32) -> [Character: UInt32] {
        let hair = appearance.hair.hex, skin = appearance.skin.hex
        var p: [Character: UInt32] = [
            "K": 0x2A2320, "H": hair, "h": shade(hair, 0.76), "S": skin, "s": shade(skin, 0.86), "E": 0x1F2A44,
            "C": accent, "Y": shade(accent, 1.3), "D": shade(accent, 0.75), "T": 0xD8C7A0, "t": 0xB9A57E,
            "B": 0x6B4A2E, "b": 0xC9772A, "P": 0x3E4A63, "p": 0x2F3A50, "F": 0x5A3E2B, "G": 0xD9A441,
            "W": 0xF4EFE4, "M": 0xA9B1BC, "m": 0x7C8592, "Q": 0x9FE3F0, "g": 0x6B5A4A, "q": 0x3FA7C4,
            "w": 0x8A5A34, "V": 0x8A5A3A, "v": 0x6E4529, "L": 0xE8E0CC, "R": 0xB5473A, "Z": 0xD9772B,
            "X": 0xECE6DA, "J": 0x4C6A8C, "j": 0x3B5573, "z": 0xE8EEF2, "N": 0x2B2B35,
            "O": accent, "o": shade(accent, 0.75),
        ]
        switch appearance.outfit {
        case .archer: p["P"] = 0x5B5240; p["p"] = 0x47402F
        case .assassin: p["O"] = 0x3A3A46; p["o"] = 0x2C2C36; p["P"] = 0x33333F; p["p"] = 0x26262F; p["F"] = 0x24242C
        case .coder: p["L"] = 0xA8B0BA; p["l"] = 0x8A929C
        case .mage, .warrior, .baller: break
        }
        return p
    }

    static func shade(_ hex: UInt32, _ factor: Double) -> UInt32 {
        [16, 8, 0].reduce(UInt32(0)) { result, shift in
            let channel = Double((hex >> UInt32(shift)) & 0xFF) * factor
            return result | (UInt32(min(255, max(0, channel.rounded()))) << UInt32(shift))
        }
    }
}

/// Цвет акцента одежды по основной профессии (Рабочая гипотеза, 02). Палитра — макет 8.6.
enum HeroAccent {
    static let fallback: UInt32 = 0x2F6B4F
    static let custom: UInt32 = 0x8E8576

    static func hex(catalogItemId: String?) -> UInt32 {
        switch catalogItemId {
        case "software-engineer": 0x2F6B4F
        case "athlete": 0xB8651B
        case "project-manager": 0x3E5C8A
        case "basketball-player": 0x2E7D7A
        case "prompt-engineer": 0x4B3F72
        default: custom
        }
    }
}

extension HeroAppearance.Hair {
    var hex: UInt32 {
        switch self {
        case .dark: 0x3B2A20
        case .red: 0xC46A3A
        case .blond: 0xE0C27A
        case .black: 0x1F1A16
        }
    }
}

extension HeroAppearance.Skin {
    var hex: UInt32 {
        switch self {
        case .light: 0xF2D0B0
        case .medium: 0xE8B892
        case .tan: 0xC98E68
        case .deep: 0x8C5A3C
        }
    }
}

/// Герой на «земле» — плитка из макетов онбординга и «Героя».
struct HeroStage: View {
    let appearance: HeroAppearance
    var accent: UInt32 = HeroAccent.fallback
    var scale: CGFloat = 2
    var height: CGFloat = 140

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: 0xE7DCC4)
            Rectangle().fill(Color(hex: 0xB9AA86)).frame(height: 22)
                .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0x8E7F5C)).frame(height: 4) }
            HeroSprite(appearance: appearance, accent: accent, scale: scale)
                .padding(.bottom, 12)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.card))
    }
}

/// Выбор образа: сетка 3×2 (макет 8.7).
struct OutfitPicker: View {
    @Binding var appearance: HeroAppearance
    var accent: UInt32 = HeroAccent.fallback

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: QSpacing.m), count: 3), spacing: QSpacing.m) {
            ForEach(HeroAppearance.Outfit.allCases, id: \.self) { outfit in
                let selected = appearance.outfit == outfit
                Button { appearance.outfit = outfit } label: {
                    VStack(spacing: QSpacing.s) {
                        HeroSprite(appearance: appearance(wearing: outfit), accent: accent, scale: 2)
                        Text(outfit.title).font(QFont.text(13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, QSpacing.m).padding(.bottom, QSpacing.s)
                    .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.card))
                    .overlay(RoundedRectangle(cornerRadius: QRadius.card)
                        .strokeBorder(selected ? QColor.ink : QColor.line, lineWidth: selected ? 2 : 1))
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(QColor.sheet)
                                .frame(width: 20, height: 20).background(QColor.ink, in: Circle())
                                .padding(QSpacing.s)
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(QColor.ink)
                .accessibilityLabel(outfit.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func appearance(wearing outfit: HeroAppearance.Outfit) -> HeroAppearance {
        var look = appearance
        look.outfit = outfit
        return look
    }
}

/// Ряд образцов цвета волос или кожи (макет OnbHero).
struct SwatchRow<Option: AppearanceSwatch>: View {
    let title: String
    let options: [Option]
    let selected: Option
    let pick: (Option) -> Void

    var body: some View {
        HStack(spacing: QSpacing.l) {
            Text(title).font(QFont.text(14)).foregroundStyle(QColor.inkSecondary).frame(width: 70, alignment: .leading)
            ForEach(options, id: \.self) { option in
                Button { pick(option) } label: {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(option.color)
                        .frame(width: 40, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(option == selected ? QColor.ink : QColor.lineStrong,
                                                                                  lineWidth: option == selected ? 3 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(option == selected ? .isSelected : [])
            }
        }
    }
}

/// Смена внешности из настроек: образ, волосы, кожа. Прогресс не меняется.
struct AppearanceEditorView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var appearance: HeroAppearance
    @State private var isSaving = false

    init(model: AppModel) {
        self.model = model
        _appearance = State(initialValue: model.hero?.appearance ?? .default)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.screen) {
                HeroStage(appearance: appearance, accent: model.heroAccent, scale: 3, height: 200)
                VStack(alignment: .leading, spacing: QSpacing.l) {
                    SwatchRow(title: "Волосы", options: HeroAppearance.Hair.allCases, selected: appearance.hair) { appearance.hair = $0 }
                    SwatchRow(title: "Кожа", options: HeroAppearance.Skin.allCases, selected: appearance.skin) { appearance.skin = $0 }
                }
                VStack(alignment: .leading, spacing: QSpacing.s) {
                    CapsHeader(title: "Образ героя")
                    OutfitPicker(appearance: $appearance, accent: model.heroAccent)
                }
                Text("Цвет одежды — по основной профессии. Внешность не влияет на атрибуты и прогресс.")
                    .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
            }
            .padding(QSpacing.screen)
        }
        .paperScreen()
        .navigationTitle("Внешность")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    isSaving = true
                    Task {
                        if await model.updateAppearance(appearance) { dismiss() }
                        isSaving = false
                    }
                }
                .disabled(isSaving || appearance == model.hero?.appearance)
            }
        }
    }
}
