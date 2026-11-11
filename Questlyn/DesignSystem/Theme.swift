import SwiftUI
import UIKit
import CoreText

/// Дизайн-токены Questlyn: светлая тема — «Полевой журнал», тёмная — «Ночная экспедиция» (05, Design/README.md, макеты 6.1–6.2).
/// Каждый цвет — пара «светлый / тёмный»; выбор темы — в настройках (7.3).
enum QColor {
    /// Бумага — фон экрана. Ночью — «ночь».
    static let paper = Color(light: 0xF5F0E6, dark: 0x0F1424)
    /// Лист — карточки. Ночью — «сумерки».
    static let sheet = Color(light: 0xFFFCF6, dark: 0x182036)
    /// Чернила — основной текст. Ночью — «звезда».
    static let ink = Color(light: 0x1F2A44, dark: 0xE8ECF7)
    /// Вторичный текст.
    static let inkSecondary = Color(light: 0x4A5368, dark: 0xAEB8D2)
    /// Граница карточек.
    static let line = Color(light: 0xE3D9C6, dark: 0x27314F)
    /// Граница кнопок и полей.
    static let lineStrong = Color(light: 0xC9BCA2, dark: 0x3A4566)
    /// Подсказка в пустом поле ввода: заметно светлее текста, но читается на фоне.
    static let placeholder = Color(light: 0x7A8091, dark: 0x8A94B8)
    /// Подложка полос прогресса.
    static let track = Color(light: 0xE9E1D0, dark: 0x27314F)
    /// Янтарь — акцент. Ночью — «костёр».
    static let amber = Color(light: 0xB8651B, dark: 0xF2B35B)
    /// Ссылки и нажатый акцент.
    static let amberDeep = Color(light: 0x9A5214, dark: 0xF7C97F)
    /// Лес — успех, DIS. Ночью — «сияние».
    static let forest = Color(light: 0x2F6B4F, dark: 0x4FD1C5)
    static let hp = Color(light: 0xA8432F, dark: 0xFF9A8A)
    static let mp = Color(light: 0x3E6FA3, dark: 0x8FB8F2)
    static let debuffINT = Color(light: 0x6B4FA3, dark: 0xB9A2F2)
    /// Тёплая плашка (подсказки, деревня, награда) и её текст.
    static let warmFill = Color(light: 0xF1E3D3, dark: 0x3A2E26)
    static let warmInk = Color(light: 0x5C3410, dark: 0xF7C97F)
    /// Холодная плашка (атрибуты, квест на карте).
    static let coolFill = Color(light: 0xE6E8EE, dark: 0x27314F)
    /// Пунктир «вне карты», неактивные точки недели.
    static let dash = Color(light: 0xB8A98A, dark: 0x4A5578)
    static let muted = Color(light: 0xD9CDB6, dark: 0x3A4566)
    /// «Сцена» героя: фон и земля.
    static let stage = Color(light: 0xE7DCC4, dark: 0x1E2742)
    static let stageGround = Color(light: 0xB9AA86, dark: 0x2E3A5C)
    static let stageEdge = Color(light: 0x8E7F5C, dark: 0x45507A)
}

/// Выбор темы (02: системная / светлая / тёмная).
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Как в системе"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
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
    /// Размеры масштабируются по Dynamic Type (7.5), но не больше чем в 1,6 раза — иначе ломаются карточки и сетки.
    static let maxScale: CGFloat = 1.6

    static func scaled(_ size: CGFloat, style: UIFont.TextStyle) -> CGFloat {
        min(UIFontMetrics(forTextStyle: style).scaledValue(for: size), size * maxScale)
    }

    static func title(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        let size = scaled(size, style: .title2)
        guard let font = literata(size: size, weight: weight) else {
            return .system(size: size, weight: weight, design: .serif)
        }
        return Font(font)
    }

    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size, style: .body), weight: weight)
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
    /// Цвет, который сам меняется вместе с темой.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: themedUIColor(light: light, dark: dark))
    }

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

/// Цвет темы для UIKit. Функция и замыкание — вне главного актора: iOS вызывает провайдер цвета
/// из потока отрисовки, и привязка к главному потоку роняла приложение (11.11.2026, EXC_BREAKPOINT в dispatch_assert_queue).
nonisolated func themedUIColor(light: UInt32, dark: UInt32) -> UIColor {
    UIColor { @Sendable traits in
        let hex = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                       blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
