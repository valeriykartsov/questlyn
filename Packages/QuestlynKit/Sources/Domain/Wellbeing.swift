import Foundation

// Настроение, погода, вредные привычки и похмелье (02 «Wellbeing», «Карта дня»; 08, разделы 2.1–2.2).
// Настроение не отнимает прогресс: оно задаёт только погоду и флажок на карте.

public enum Mood: String, CaseIterable, Codable, Sendable {
    case good, neutral, bad

    public var title: String {
        switch self {
        case .good: "Хорошее"
        case .neutral: "Ровное"
        case .bad: "Плохое"
        }
    }

    /// Шкала Apple Health State of Mind (−1…+1).
    public var valence: Double {
        switch self {
        case .good: 0.6
        case .neutral: 0
        case .bad: -0.6
        }
    }
}

/// Отметка настроения — факт.
public struct MoodEntry: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var mood: Mood
    public var note: String?
    /// «Итог дня»: не больше одного в день, новый заменяет прежний.
    public var isDaySummary: Bool
    public var at: Date
    public var localDate: LocalDate
    public var timezoneId: String
    public var deletedAt: Date?

    public init(id: UUID = UUID(), mood: Mood, note: String? = nil, isDaySummary: Bool = false, at: Date, localDate: LocalDate,
                timezoneId: String, deletedAt: Date? = nil) {
        self.id = id
        self.mood = mood
        self.note = note
        self.isDaySummary = isDaySummary
        self.at = at
        self.localDate = localDate
        self.timezoneId = timezoneId
        self.deletedAt = deletedAt
    }
}

public enum Weather: String, Codable, Sendable {
    case clear, cloudy, rain, snow

    public var title: String {
        switch self {
        case .clear: "Ясно"
        case .cloudy: "Облачно"
        case .rain: "Дождь"
        case .snow: "Снег"
        }
    }

    /// Хорошее → ясно, ровное → облачно, плохое → дождь (зимой — снег). Без отметок — ясно.
    public static func from(_ mood: Mood?, on date: LocalDate) -> Weather {
        switch mood {
        case .good, nil: .clear
        case .neutral: .cloudy
        case .bad: [12, 1, 2].contains(date.month) ? .snow : .rain
        }
    }
}

/// Вид отметки блока «Здоровье».
public enum HarmKind: String, CaseIterable, Codable, Sendable {
    case smoking, fastFood, lateCaffeine, custom, alcohol

    /// Урон в процентах MaxHP за одну отметку (08, раздел 2). Своя привычка — по силе, алкоголь — не HP.
    public var damagePercent: Int? {
        switch self {
        case .smoking: 3
        case .fastFood, .lateCaffeine: 5
        case .custom, .alcohol: nil
        }
    }

    public var title: String {
        switch self {
        case .smoking: "Курение"
        case .fastFood: "Фастфуд"
        case .lateCaffeine: "Кофеин после 16:00"
        case .custom: "Своя привычка"
        case .alcohol: "Алкоголь"
        }
    }
}

public enum AlcoholDegree: String, CaseIterable, Codable, Sendable, Comparable {
    case little, lots

    public var title: String { self == .little ? "Немного" : "Много" }
    /// −10% уровня INT (минимум 1) или −25% (минимум 2), округление вниз.
    public func removedLevels(of level: Int) -> Int {
        let removed = self == .little ? max(1, level / 10) : max(2, level / 4)
        return min(removed, level)
    }

    public static func < (lhs: AlcoholDegree, rhs: AlcoholDegree) -> Bool { lhs == .little && rhs == .lots }
}

/// Отметка блока «Здоровье» — факт. Удаление возвращает урон.
public struct HarmEntry: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var kind: HarmKind
    /// Для своей привычки — её id, название и сила на момент отметки.
    public var customHabitId: UUID?
    public var title: String
    public var damagePercent: Int
    public var alcohol: AlcoholDegree?
    public var at: Date
    public var localDate: LocalDate
    public var timezoneId: String
    public var deletedAt: Date?

    public init(id: UUID = UUID(), kind: HarmKind, customHabitId: UUID? = nil, title: String, damagePercent: Int,
                alcohol: AlcoholDegree? = nil, at: Date, localDate: LocalDate, timezoneId: String, deletedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.customHabitId = customHabitId
        self.title = title
        self.damagePercent = damagePercent
        self.alcohol = alcohol
        self.at = at
        self.localDate = localDate
        self.timezoneId = timezoneId
        self.deletedAt = deletedAt
    }

    public var isActive: Bool { deletedAt == nil }
}

/// Своя вредная привычка: сила 5 / 10 / 20% HP за отметку.
public struct CustomHarmHabit: Identifiable, Hashable, Codable, Sendable {
    public static let allowedPercents = [5, 10, 20]

    public var id: UUID
    public var title: String
    public var damagePercent: Int
    public var isActive: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, damagePercent: Int, isActive: Bool = true, createdAt: Date) {
        self.id = id
        self.title = title
        self.damagePercent = damagePercent
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

/// Похмелье: дебаф действующего INT на 24 ч (08, 2.1, вариант А).
public struct Hangover: Hashable, Sendable {
    public var degree: AlcoholDegree
    public var startedAt: Date
    public var until: Date

    public static let duration: TimeInterval = 24 * 3600

    /// Повтор за время дебафа не складывается: берётся бо́льшая степень, отсчёт начинается заново.
    public static func timeline(_ entries: [HarmEntry]) -> [Hangover] {
        var result: [Hangover] = []
        for entry in entries.filter({ $0.isActive && $0.kind == .alcohol }).sorted(by: { $0.at < $1.at }) {
            guard let degree = entry.alcohol else { continue }
            if var current = result.last, entry.at < current.until {
                current.degree = max(current.degree, degree)
                current.until = entry.at + duration
                result[result.count - 1] = current
            } else {
                result.append(Hangover(degree: degree, startedAt: entry.at, until: entry.at + duration))
            }
        }
        return result
    }

    public static func active(at date: Date, in timeline: [Hangover]) -> Hangover? {
        timeline.last { $0.startedAt <= date && date < $0.until }
    }

    public func removedLevels(intelligence level: Int) -> Int { degree.removedLevels(of: level) }
}

// MARK: - Полезные действия (08, раздел 2.3)

public enum BenefitKind: String, CaseIterable, Codable, Sendable {
    case water, vegetables, outdoorWalk, stretching, nap, custom

    public var title: String {
        switch self {
        case .water: "Вода 2 л"
        case .vegetables: "Овощи и фрукты"
        case .outdoorWalk: "Прогулка на воздухе"
        case .stretching: "Растяжка"
        case .nap: "Дневной отдых"
        case .custom: "Своё действие"
        }
    }
}

/// Факт: полезное действие. Восстанавливает HP; удаление — пометкой.
public struct BenefitEntry: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var kind: BenefitKind
    public var title: String
    public var at: Date
    public var localDate: LocalDate
    public var timezoneId: String
    public var deletedAt: Date?

    public init(id: UUID = UUID(), kind: BenefitKind, title: String, at: Date, localDate: LocalDate, timezoneId: String, deletedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.at = at
        self.localDate = localDate
        self.timezoneId = timezoneId
        self.deletedAt = deletedAt
    }

    public var isActive: Bool { deletedAt == nil }
}

public enum BenefitRules {
    /// +3% MaxHP за отметку, не больше +10% MaxHP за день (08, раздел 2.3).
    public static let healShare = 0.03
    public static let dailyCapShare = 0.10
}
