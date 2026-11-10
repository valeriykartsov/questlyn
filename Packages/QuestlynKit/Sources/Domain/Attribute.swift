/// Атрибуты героя (02, «Итоговый набор атрибутов»). DEX исключён 10.11.2026.
public enum Attribute: String, CaseIterable, Codable, Sendable {
    case strength = "STR"
    case endurance = "END"
    case intelligence = "INT"
    case mentality = "MNT"
    case charisma = "CHR"
    case focus = "FOC"
    case discipline = "DIS"

    /// Аббревиатура для интерфейса и хранения.
    public var code: String { rawValue }

    /// Название в интерфейсе (макеты онбординга, 02: MNT — «Ментальность»).
    public var title: String {
        switch self {
        case .strength: "Сила"
        case .endurance: "Выносливость"
        case .intelligence: "Интеллект"
        case .mentality: "Ментальность"
        case .charisma: "Харизма"
        case .focus: "Фокус"
        case .discipline: "Дисциплина"
        }
    }

    /// FOC и DIS не выбираются в профессии (02).
    public var isSelectableForProfession: Bool {
        switch self {
        case .focus, .discipline: false
        default: true
        }
    }

    public static var professionSelectable: [Attribute] {
        allCases.filter(\.isSelectableForProfession)
    }
}
