import SwiftUI
import UIKit
import CoreText

/// Дизайн-токены Questlyn: направление A «Полевой журнал», светлая тема (05, Design/README.md).
/// Тёмная тема «Ночная экспедиция» — этап 7.3.
enum QColor {
    /// Бумага — фон экрана.
    static let paper = Color(hex: 0xF5F0E6)
    /// Лист — карточки.
    static let sheet = Color(hex: 0xFFFCF6)
    /// Чернила — основной текст.
    static let ink = Color(hex: 0x1F2A44)
    /// Вторичный текст.
    static let inkSecondary = Color(hex: 0x4A5368)
    /// Граница карточек.
    static let line = Color(hex: 0xE3D9C6)
    /// Граница кнопок и полей.
    static let lineStrong = Color(hex: 0xC9BCA2)
    /// Подложка полос прогресса.
    static let track = Color(hex: 0xE9E1D0)
    /// Янтарь — акцент.
    static let amber = Color(hex: 0xB8651B)
    /// Ссылки и нажатый акцент.
    static let amberDeep = Color(hex: 0x9A5214)
    /// Лес — успех, DIS.
    static let forest = Color(hex: 0x2F6B4F)
    static let hp = Color(hex: 0xA8432F)
    static let mp = Color(hex: 0x3E6FA3)
    static let debuffINT = Color(hex: 0x6B4FA3)
}

/// Отступы — шкала из макетов.
enum QSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    static let m: CGFloat = 8
    static let l: CGFloat = 12
    static let xl: CGFloat = 14
    /// Боковое поле экрана.
    static let screen: CGFloat = 16
}

/// Радиусы скруглений.
enum QRadius {
    static let bar: CGFloat = 3
    static let chip: CGFloat = 6
    static let small: CGFloat = 9
    static let control: CGFloat = 12
    static let card: CGFloat = 14
    static let hero: CGFloat = 18
}

/// Шрифты: Literata — заголовки, SF Pro (системный) — текст и цифры (02, 10.11.2026).
/// Literata — вариативный шрифт (оси wght и opsz) из Google Fonts, лицензия OFL — `Resources/Fonts`.
enum QFont {
    static func title(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        guard let font = literata(size: size, weight: weight) else {
            return .system(size: size, weight: weight, design: .serif)
        }
        return Font(font)
    }

    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Регистрирует шрифты из бандла. Вызывается один раз при запуске.
    static func registerBundledFonts() {
        guard let url = Bundle.main.url(forResource: "Literata", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    private static func literata(size: CGFloat, weight: Font.Weight) -> UIFont? {
        guard UIFont(name: "Literata-Regular", size: size) != nil else { return nil }
        let wghtAxis = 0x7767_6874 // 'wght'
        let opszAxis = 0x6F70_737A // 'opsz', диапазон 7–72 pt
        let variations: [Int: CGFloat] = [
            wghtAxis: cssWeight(weight),
            opszAxis: min(max(size, 7), 72),
        ]
        let descriptor = UIFontDescriptor(name: "Literata-Regular", size: size)
            .addingAttributes([UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variations])
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func cssWeight(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight: 200
        case .thin, .light: 300
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy: 800
        case .black: 900
        default: 400
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Карточка «лист» на «бумаге».
struct SheetCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.card))
            .overlay(RoundedRectangle(cornerRadius: QRadius.card).strokeBorder(QColor.line))
    }
}

extension View {
    func sheetCard() -> some View { modifier(SheetCard()) }
}
