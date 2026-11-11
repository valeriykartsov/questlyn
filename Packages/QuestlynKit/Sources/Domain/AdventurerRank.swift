/// Adventurer Rank (07, раздел 8). Названия — Подтверждено 10.11.2026.
public struct AdventurerRank: Hashable, Sendable {
    /// Номер ранга 1…10.
    public let number: Int
    public let letter: String
    public let title: String

    public static let all: [AdventurerRank] = [
        .init(number: 1, letter: "G", title: "Новобранец"),
        .init(number: 2, letter: "F", title: "Странник"),
        .init(number: 3, letter: "E", title: "Следопыт"),
        .init(number: 4, letter: "D", title: "Искатель"),
        .init(number: 5, letter: "C", title: "Первопроходец"),
        .init(number: 6, letter: "B", title: "Ветеран"),
        .init(number: 7, letter: "A", title: "Хранитель"),
        .init(number: 8, letter: "S", title: "Магистр"),
        .init(number: 9, letter: "SS", title: "Герой"),
        .init(number: 10, letter: "SSS", title: "Легенда"),
    ]

    /// Порог очков T(r) = 2,5·r² + 7,5·r. Всегда целое: r² + 3r чётно.
    public var threshold: Int { AdventurerRank.threshold(number) }

    public static func threshold(_ r: Int) -> Int { (5 * r * r + 15 * r) / 2 }

    /// «Ранг D · Искатель».
    public var displayName: String { "Ранг \(letter) · \(title)" }

    /// Меньше 10 очков — ранга нет (02, 07; 10.11.2026).
    public static let unrankedTitle = "Без ранга"

    public static func displayName(for rank: AdventurerRank?) -> String {
        rank?.displayName ?? unrankedTitle
    }
}

/// Расчёт ранга по уровням атрибутов и составу класса.
public enum RankCalculator {
    /// Очки ранга в половинах: S = Σ вес × уровень; вес 1,0 (класс, FOC, DIS) или 0,5 (вне класса).
    public static func pointsInHalves(levels: [Attribute: Int], classAttributes: Set<Attribute>) -> Int {
        Attribute.allCases.reduce(0) { sum, attribute in
            let level = levels[attribute] ?? 0
            let weightInHalves = (attribute == .focus || attribute == .discipline || classAttributes.contains(attribute)) ? 2 : 1
            return sum + weightInHalves * level
        }
    }

    /// Очки ранга S как число — для отображения.
    public static func points(levels: [Attribute: Int], classAttributes: Set<Attribute>) -> Double {
        Double(pointsInHalves(levels: levels, classAttributes: classAttributes)) / 2
    }

    /// Достигнутый ранг или `nil`, если очков меньше порога G (10).
    /// Для рангов 6+ каждый атрибут профессий класса должен быть не ниже уровня 2·r.
    public static func rank(levels: [Attribute: Int], classAttributes: Set<Attribute>) -> AdventurerRank? {
        let points = pointsInHalves(levels: levels, classAttributes: classAttributes)
        return AdventurerRank.all.last { rank in
            guard points >= rank.threshold * 2 else { return false }
            guard rank.number >= 6 else { return true }
            return classAttributes.allSatisfy { (levels[$0] ?? 0) >= 2 * rank.number }
        }
    }
}

/// Ступень ауры героя по текущему рангу (02, 11.11.2026): G — без ауры; F–E, D–C, B–A, S–SS, SSS — ступени 1–5.
/// При спаде ранга ступень опускается или пропадает.
public enum AuraTier {
    public static func of(_ rank: AdventurerRank?) -> Int {
        guard let rank else { return 0 }
        switch rank.number {
        case ...1: return 0
        case 2...3: return 1
        case 4...5: return 2
        case 6...7: return 3
        case 8...9: return 4
        default: return 5
        }
    }
}
