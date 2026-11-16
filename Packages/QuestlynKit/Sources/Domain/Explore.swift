import Foundation

// «Побродить» (этап 8B): мини-игра на острове из событий за прошлые даты. Песочница — ничего не сохраняет.
// Все числа — в `ExploreRules` (Product/09_EXPLORE_RULES.md, Рабочая гипотеза).

// MARK: - Случайность по зерну

/// Детерминированный генератор: тот же диапазон и зерно — тот же остров и те же броски.
public struct ExploreRandom: Sendable {
    private var state: UInt64
    public init(_ seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    public mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
    /// 0..<1.
    public mutating func unit() -> Double { Double(next() % 1_000_000) / 1_000_000 }
    public mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(max(bound, 1))) }
    /// Разброс ±share вокруг 1.
    public mutating func spread(_ share: Double) -> Double { 1 + (unit() * 2 - 1) * share }
}

// MARK: - Правила (09)

public enum ExploreRules {
    public static let maxDays = 92
    public static let maxSkills = 3

    // Остров (09, раздел 1–2).
    public static func islandSize(days: Int) -> IslandSize {
        switch days {
        case ...14: .small
        case 15...42: .medium
        default: .large
        }
    }
    public static let citySafeRadius = 3
    public static let cityMinDistance = 8
    public static let villageMinDistance = 3
    public static let npcMinDistanceFromStart = 6
    public static let chestCap = 30
    /// Архипелаг (12B, 12.11.2026): вода между островами и по краю мира, клеток.
    public static let islandGap = 8
    public static let worldMargin = 3
    /// Сесть на корабль — в этом радиусе от него, клеток.
    public static let boardRadius = 2.0
    /// Гавань: NPC не живут ближе к кораблю (бродят ±5 клеток, погоня — до 3,5).
    public static let harbourRadius = 9.0
    /// Корабль быстрее шага вдвое; плавание не тратит HP и MP.
    public static let sailSpeedFactor = 2.0

    // Этап 14 (16.11.2026, 09 раздел 1.2, Рабочая гипотеза).
    public static let bottleCap = 8
    public static let pickupRadius = 1.5
    public static let towerCap = 2
    public static let towerMinDistanceFromStart = 10.0
    public static func guardianHP(steps: Int) -> Double { 40 + 15 * Double(steps) }
    public static let guardianDamageShare = 0.12
    public static let lighthouseStreak = 7
    public static let lighthouseVisionBonus = 3.0
    public static let lighthouseSeconds: TimeInterval = 60
    public static let potionShare = 0.30
    public static let torchVision = 15.0
    public static let torchSeconds: TimeInterval = 30
    public static let compassSeconds: TimeInterval = 20
    public static let bagCap = 6
    public static let taskRewardShare = 0.25
    public static let taskChests = 2
    /// Удар спутника в начале встречи — по его типу.
    public static func companionStrike(_ tier: NPCTier) -> Double { 4 + 4 * Double(tier.rawValue) }
    /// Сутки на карте — 12 минут; ночь 21–6, обзор ×0,7.
    public static let daySeconds: TimeInterval = 12 * 60
    public static let nightVisionFactor = 0.7
    public static func isNight(hour: Double) -> Bool { hour >= 21 || hour < 6 }

    // Этап 15C (17.11.2026, 09 раздел 1.5, Рабочая гипотеза).
    public static let treasureFragments = 3
    public static let treasureItems = 2
    public static let treasureRestoreShare = 0.5
    public static let caveSide = 24
    public static let caveMinSpan = 15.0
    public static let caveVision = 3.0
    public static let caveTorchVision = 9.0
    public static let caveChests = 2
    public static let lookoutRadius = 30.0

    // Этапы 15B и 15G (17.11.2026, 09 раздел 1.4, Рабочая гипотеза).
    /// Финальная Чёрная башня: HP 150 + 2 × дни диапазона, урон 15% макс. HP.
    public static func finalTowerHP(days: Int) -> Double { 150 + 2 * Double(days) }
    public static let finalTowerDamageShare = 0.15
    /// Болото: пятен на остров не больше, радиус пятна; −1% HP в секунду, шаг ×0,6.
    public static let swampCap = 8
    public static let swampRadius = 3.0
    public static let swampHPPerSecond = 0.01
    public static let swampSpeedFactor = 0.6
    /// Сектора навыков: три навыка с наибольшим ростом за месяц.
    public static let sectorSkills = 3
    /// Монумент полезного: полная сила баффа — с 10 отметок вида за месяц.
    public static let buffFullMarks = 10.0

    // Этап 15A (16.11.2026, 09 раздел 1.3, Рабочая гипотеза).
    /// Горы — не ближе 4 клеток к морю, там, где шум высоты выше порога.
    public static let mountainCoastDistance = 4
    public static let mountainThreshold = 0.70
    /// Высота гор в пикселях изометрии: ступени по 2 px, вершины от 14 px — под снегом.
    public static let mountainMaxHeight = 24
    public static let snowLineHeight = 14

    // Герой (09, раздел 4).
    public static func walkSpeed(endurance: Int) -> Double { min(4.5, 3 + 0.1 * Double(endurance)) }
    public static func strike(strength: Int) -> Double { 8 + 2 * Double(strength) }
    public static func vision(intelligence: Int) -> Double { min(12, 5 + 0.5 * Double(intelligence)) }
    public static let hitSpread = 0.2
    public static func escapeChance(mentality: Int, tier: NPCTier) -> Double {
        min(0.9, max(0.2, 0.5 + 0.04 * Double(mentality) - escapePenaltyPerTier * Double(tier.rawValue - 1)))
    }
    public static let escapePenaltyPerTier = 0.08
    public static func cooldown(focus: Int, discipline: Int) -> Int {
        let sum = focus + discipline
        return 3 - (sum >= 20 ? 2 : sum >= 10 ? 1 : 0)
    }

    // Восстановление (09, раздел 5).
    public static let cityRestorePerSecond = 0.10
    public static let campfireShare = 0.40
    public static let defeatHPShare = 0.5

    /// Множитель силы способности по XP навыка (09, раздел 6).
    public static func power(skillXP: Double) -> Double {
        switch skillXP {
        case ..<50: 1.0
        case ..<200: 1.25
        case ..<500: 1.5
        default: 2.0
        }
    }
}

public enum IslandSize: String, Sendable, CaseIterable {
    case small, medium, large

    /// Сторона острова: с 15A площадь ×3 при прежнем числе объектов (было 48 / 72 / 96).
    public var tiles: Int { switch self { case .small: 83; case .medium: 125; case .large: 166 } }
    public var npcCap: Int { switch self { case .small: 15; case .medium: 25; case .large: 40 } }
    public var cityCap: Int { switch self { case .small: 6; case .medium: 10; case .large: 14 } }
    public var villageCap: Int { switch self { case .small: 10; case .medium: 20; case .large: 30 } }
    public var title: String { switch self { case .small: "Малый остров"; case .medium: "Средний остров"; case .large: "Большой остров" } }
}

/// Тип NPC по числу событий с этим человеком (09, раздел 3).
public enum NPCTier: Int, Sendable, CaseIterable, Comparable {
    case acquaintance = 1, colleague, regular

    public static func of(meetings: Int) -> NPCTier { meetings >= 5 ? .regular : meetings >= 2 ? .colleague : .acquaintance }
    public static func < (lhs: NPCTier, rhs: NPCTier) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String { switch self { case .acquaintance: "Знакомый"; case .colleague: "Коллега"; case .regular: "Постоянный" } }
    public var hp: Double { switch self { case .acquaintance: 20; case .colleague: 40; case .regular: 70 } }
    /// Урон за ход — доля HPmax героя.
    public var damageShare: Double { switch self { case .acquaintance: 0.06; case .colleague: 0.09; case .regular: 0.13 } }
    public var chaseRadius: Double { Double(rawValue) + 1.5 }
    public static let wanderSpeed = 1.5
    public static let chaseSpeed = 2.5
    /// После встречи NPC не преследует, секунд.
    public static let calmAfterEncounter = 10.0
}

// MARK: - Способности навыков (09, раздел 6)

public enum ExploreAbility: String, Sendable, CaseIterable {
    case powerStrike, dash, teamMove, scout, focus, persuade, distract

    public var title: String {
        switch self {
        case .powerStrike: "Мощный удар"
        case .dash: "Рывок"
        case .teamMove: "Командный приём"
        case .scout: "Разведка"
        case .focus: "Концентрация"
        case .persuade: "Уговорить"
        case .distract: "Отвлечь"
        }
    }

    public var summary: String {
        switch self {
        case .powerStrike: "сильный удар"
        case .dash: "побег без броска, на карте — ускорение"
        case .teamMove: "удар и NPC пропускает ход"
        case .scout: "следующий удар сильнее, на карте — обзор"
        case .focus: "урон по герою вдвое меньше"
        case .persuade: "NPC станет мирным"
        case .distract: "NPC пропускает ходы"
        }
    }

    /// Стоимость — доля MPmax.
    public var mpShare: Double {
        switch self {
        case .dash, .scout: 0.08
        case .teamMove: 0.12
        case .powerStrike, .focus, .persuade, .distract: 0.10
        }
    }

    /// По привязанному виду активности (8.6), иначе — по основному атрибуту профессии навыка.
    public static func of(activityTemplateId: String?, professionMain: Attribute?) -> ExploreAbility? {
        switch activityTemplateId {
        case "strength": return .powerStrike
        case "cardio", "walk": return .dash
        case "team-sport": return .teamMove
        case "study": return .scout
        case "deep-work", "meditation": return .focus
        case "social": return .persuade
        case "creative": return .distract
        default: break
        }
        switch professionMain {
        case .strength: return .powerStrike
        case .endurance: return .dash
        case .intelligence: return .scout
        case .mentality: return .focus
        case .charisma: return .persuade
        default: return nil
        }
    }
}

/// Навык, взятый в дорогу.
public struct ExploreSkill: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var ability: ExploreAbility
    /// Множитель силы по XP навыка.
    public var power: Double

    public init(id: UUID, title: String, ability: ExploreAbility, skillXP: Double) {
        self.id = id
        self.title = title
        self.ability = ability
        self.power = ExploreRules.power(skillXP: skillXP)
    }
}

/// Герой на старте прогулки: текущие уровни, HP и MP (песочница — настоящие не меняются).
public struct ExploreHero: Hashable, Sendable {
    public var levels: [Attribute: Int]
    public var hp: Double
    public var maxHP: Double
    public var mp: Double
    public var maxMP: Double
    public var rankLetter: String
    public var skills: [ExploreSkill]

    public init(levels: [Attribute: Int], hp: Double, maxHP: Double, mp: Double, maxMP: Double, rankLetter: String, skills: [ExploreSkill]) {
        self.levels = levels
        self.hp = hp
        self.maxHP = maxHP
        self.mp = mp
        self.maxMP = maxMP
        self.rankLetter = rankLetter
        self.skills = Array(skills.prefix(ExploreRules.maxSkills))
    }

    public func level(_ attribute: Attribute) -> Int { levels[attribute] ?? 0 }
    public var walkSpeed: Double { ExploreRules.walkSpeed(endurance: level(.endurance)) }
    public var vision: Double { ExploreRules.vision(intelligence: level(.intelligence)) }
    public var cooldown: Int { ExploreRules.cooldown(focus: level(.focus), discipline: level(.discipline)) }
}

// MARK: - Входные данные

public struct ExploreEvent: Hashable, Sendable {
    public var title: String
    public var start: Date
    public var minutes: Int
    /// Хеши адресов участников без самого пользователя (имена не хранятся).
    public var attendeeKeys: [String]

    public init(title: String, start: Date, minutes: Int, attendeeKeys: [String]) {
        self.title = title
        self.start = start
        self.minutes = minutes
        self.attendeeKeys = attendeeKeys
    }
}

/// Заметка «Дневника» — бутылка с письмом (14.5).
public struct ExploreDiaryNote: Hashable, Sendable {
    public var date: LocalDate
    public var mood: Mood
    public var note: String
    public init(date: LocalDate, mood: Mood, note: String) { self.date = date; self.mood = mood; self.note = note }
}

/// Epic: даты его шагов (срок или выполнение) — Чёрная башня в месяце шага (14.5).
public struct ExploreEpic: Hashable, Sendable {
    public var title: String
    public var steps: Int
    public var dates: [LocalDate]
    public init(title: String, steps: Int, dates: [LocalDate]) { self.title = title; self.steps = steps; self.dates = dates }
}

/// Выполненный квест — кандидат в клад (15C.1).
public struct ExploreDoneQuest: Hashable, Sendable {
    public var title: String
    public var priority: QuestPriority
    public var minutes: Int
    public init(title: String, priority: QuestPriority, minutes: Int) { self.title = title; self.priority = priority; self.minutes = minutes }
}

/// Навык и его прирост XP по дням (15B.1): сектора острова.
public struct ExploreSkillGain: Hashable, Sendable {
    public var title: String
    public var gains: [LocalDate: Double]
    public init(title: String, gains: [LocalDate: Double]) { self.title = title; self.gains = gains }
    public func gain(from first: LocalDate, through last: LocalDate) -> Double {
        gains.filter { $0.key >= first && $0.key <= last }.values.reduce(0, +)
    }
}

/// Закрытый Epic (15B.2): памятник на острове месяца закрытия.
public struct ExploreClosedEpic: Hashable, Sendable {
    public var title: String
    public var steps: Int
    public var started: LocalDate
    public var closed: LocalDate
    public init(title: String, steps: Int, started: LocalDate, closed: LocalDate) {
        self.title = title; self.steps = steps; self.started = started; self.closed = closed
    }
}

/// Вид «Полезного» из «Как вы?» для монументов (15G.4).
public enum ExploreBuff: String, Sendable, CaseIterable, Hashable {
    case water, walk, stretch, vegetables, nap, custom

    public init(_ kind: BenefitKind) {
        switch kind {
        case .water: self = .water
        case .outdoorWalk: self = .walk
        case .stretching: self = .stretch
        case .vegetables: self = .vegetables
        case .nap: self = .nap
        case .custom: self = .custom
        }
    }

    public var title: String {
        switch self {
        case .water: "Вода 2 л"
        case .walk: "Прогулка на воздухе"
        case .stretch: "Растяжка"
        case .vegetables: "Овощи и фрукты"
        case .nap: "Дневной отдых"
        case .custom: "Своё действие"
        }
    }

    /// Сила на максимуме: доля в секунду, множитель или клетки.
    public var maximum: Double {
        switch self {
        case .water, .vegetables: 0.005
        case .walk: 0.20
        case .stretch: 0.25
        case .nap: 0.30
        case .custom: 2
        }
    }

    /// «+0,5% HP в секунду» — при силе `strength` (0…1).
    public func effect(_ strength: Double) -> String {
        let value = maximum * strength
        func number(_ x: Double, _ digits: Int = 1) -> String {
            x.formatted(.number.precision(.fractionLength(0...digits)).locale(Locale(identifier: "ru_RU")))
        }
        switch self {
        case .water: return "+\(number(value * 100))% HP в секунду"
        case .vegetables: return "+\(number(value * 100))% MP в секунду"
        case .walk: return "скорость +\(number(value * 100, 0))%"
        case .stretch: return "урон по герою −\(number(value * 100, 0))%"
        case .nap: return "перезарядка −\(number(value * 100, 0))%"
        case .custom: return "обзор +\(number(value))"
        }
    }

    public static func strength(marks: Int) -> Double { min(1, Double(marks) / ExploreRules.buffFullMarks) }
}

/// Отметка настроения (15A): погода прогулки — случайная отметка месяца.
public struct ExploreMood: Hashable, Sendable {
    public var date: LocalDate
    public var mood: Mood
    public init(date: LocalDate, mood: Mood) { self.date = date; self.mood = mood }
}

/// Ежедневная привычка и дни её отметок — маяк при серии (14.5).
public struct ExploreHabitDays: Hashable, Sendable {
    public var title: String
    public var days: Set<LocalDate>
    /// Запланированные дни (15A, износ дорог); nil — каждый день.
    public var planned: Set<LocalDate>?
    public init(title: String, days: Set<LocalDate>, planned: Set<LocalDate>? = nil) {
        self.title = title; self.days = days; self.planned = planned
    }

    /// Выполнение за отрезок, % (15A): отмеченные запланированные дни / запланированные. nil — дней не было.
    public func percent(from first: LocalDate, through last: LocalDate) -> Int? {
        var planned = 0, done = 0, day = first
        while day <= last {
            if self.planned?.contains(day) ?? true {
                planned += 1
                if days.contains(day) { done += 1 }
            }
            day = day.adding(days: 1)
        }
        return planned == 0 ? nil : Int((Double(done) / Double(planned) * 100).rounded())
    }

    /// Самая длинная серия подряд внутри диапазона.
    public func longestStreak(from first: LocalDate, through last: LocalDate) -> Int {
        var best = 0, current = 0, day = first
        while day <= last {
            if days.contains(day) { current += 1; best = max(best, current) } else { current = 0 }
            day = day.adding(days: 1)
        }
        return best
    }
}

public struct ExploreInput: Sendable {
    public var first: LocalDate
    public var last: LocalDate
    public var events: [ExploreEvent]
    /// Квесты диапазона: название, приоритет и дата (по ней — остров месяца; без даты — последний месяц).
    public var quests: [(title: String, priority: QuestPriority, date: LocalDate?)]
    /// Качество ночей диапазона (Q из 08), по дню пробуждения.
    public var nights: [LocalDate: Double]
    /// Последняя отметка настроения недели — по понедельнику недели.
    public var weekMoods: [LocalDate: Mood]
    public var hasCalendar: Bool
    /// Пояс для дат событий: по нему событие попадает на остров своего месяца.
    public var timeZone: TimeZone
    public var diary: [ExploreDiaryNote] = []
    public var epics: [ExploreEpic] = []
    public var habits: [ExploreHabitDays] = []
    public var moods: [ExploreMood] = []
    // 15B, 15G.
    public var skillGains: [ExploreSkillGain] = []
    public var closedEpics: [ExploreClosedEpic] = []
    /// Отметки вредного — по одной дате на отметку.
    public var harmDays: [LocalDate] = []
    /// Отметки полезного: дата и вид.
    public var benefits: [(date: LocalDate, buff: ExploreBuff)] = []
    /// Выполненные квесты диапазона (15C.1).
    public var doneQuests: [ExploreDoneQuest] = []

    public init(first: LocalDate, last: LocalDate, events: [ExploreEvent], quests: [(title: String, priority: QuestPriority, date: LocalDate?)],
                nights: [LocalDate: Double], weekMoods: [LocalDate: Mood], hasCalendar: Bool, timeZone: TimeZone = .current) {
        self.timeZone = timeZone
        self.first = first
        self.last = last
        self.events = events
        self.quests = quests
        self.nights = nights
        self.weekMoods = weekMoods
        self.hasCalendar = hasCalendar
    }

    public var days: Int { first.days(until: last) + 1 }

    /// Только прошлые даты, не больше 92 дней (02, 11.11.2026).
    public static func isValidRange(first: LocalDate, last: LocalDate, today: LocalDate) -> Bool {
        first <= last && last < today && first.days(until: last) + 1 <= ExploreRules.maxDays
    }

    /// Месяцы диапазона (12B): каждый — отдельный остров, края обрезаны диапазоном.
    public var months: [(first: LocalDate, last: LocalDate)] {
        var result: [(first: LocalDate, last: LocalDate)] = []
        var day = first
        while day <= last {
            let nextMonth = day.month == 12 ? LocalDate(year: day.year + 1, month: 1, day: 1) : LocalDate(year: day.year, month: day.month + 1, day: 1)
            let end = min(last, nextMonth.adding(days: -1))
            result.append((day, end))
            day = end.adding(days: 1)
        }
        return result
    }

    /// Часть диапазона — данные одного месяца.
    func slice(first: LocalDate, last: LocalDate, isLastMonth: Bool) -> ExploreInput {
        ExploreInput(first: first, last: last,
                     events: events.filter { let day = LocalDate($0.start, timeZone: timeZone); return day >= first && day <= last },
                     quests: quests.filter { quest in quest.date.map { $0 >= first && $0 <= last } ?? isLastMonth },
                     nights: nights.filter { $0.key >= first && $0.key <= last },
                     weekMoods: weekMoods, hasCalendar: hasCalendar, timeZone: timeZone)
            .with(diary: diary.filter { $0.date >= first && $0.date <= last },
                  epics: epics.filter { epic in epic.dates.contains { $0 >= first && $0 <= last } },
                  habits: habits)
            .with(moods: moods.filter { $0.date >= first && $0.date <= last })
            .with(skillGains: skillGains, closedEpics: closedEpics.filter { $0.closed >= first && $0.closed <= last },
                  harmDays: harmDays.filter { $0 >= first && $0 <= last },
                  benefits: benefits.filter { $0.date >= first && $0.date <= last })
    }

    public func with(doneQuests: [ExploreDoneQuest]) -> ExploreInput {
        var copy = self
        copy.doneQuests = doneQuests
        return copy
    }

    /// Клад — главный выполненный квест: высокий приоритет, при равенстве — самый длинный.
    public var treasureQuest: ExploreDoneQuest? {
        let rank: [QuestPriority: Int] = [.high: 3, .medium: 2, .low: 1]
        return doneQuests.max { (rank[$0.priority] ?? 0, $0.minutes, $1.title) < (rank[$1.priority] ?? 0, $1.minutes, $0.title) }
    }

    public func with(skillGains: [ExploreSkillGain], closedEpics: [ExploreClosedEpic], harmDays: [LocalDate],
                     benefits: [(date: LocalDate, buff: ExploreBuff)]) -> ExploreInput {
        var copy = self
        copy.skillGains = skillGains
        copy.closedEpics = closedEpics
        copy.harmDays = harmDays
        copy.benefits = benefits
        return copy
    }

    public func with(moods: [ExploreMood]) -> ExploreInput {
        var copy = self
        copy.moods = moods
        return copy
    }

    public func with(diary: [ExploreDiaryNote], epics: [ExploreEpic], habits: [ExploreHabitDays]) -> ExploreInput {
        var copy = self
        copy.diary = diary
        copy.epics = epics
        copy.habits = habits
        return copy
    }

    /// Зерно из диапазона; «Другой остров» прибавляет номер попытки.
    public func seed(attempt: Int) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in "\(first)|\(last)|\(attempt)".utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return hash
    }
}

// MARK: - Остров

public struct TilePoint: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    public func distance(to other: TilePoint) -> Double { hypot(Double(x - other.x), Double(y - other.y)) }
}

public enum Terrain: UInt8, Sendable { case water, sand, grass, forest, mountain }

/// Климатическая зона (15A): с севера (верх экрана) на юг.
public enum ClimateZone: Int, Sendable, CaseIterable {
    case tundra, taiga, temperate, steppe, desert

    public var title: String {
        switch self {
        case .tundra: "Тундра"
        case .taiga: "Тайга"
        case .temperate: "Умеренная"
        case .steppe: "Степь"
        case .desert: "Пустыня"
        }
    }
    /// Осадки здесь — снег.
    public var isCold: Bool { self == .tundra || self == .taiga }
}

/// Износ дороги (15A) — по выполнению привязанной привычки за месяц.
public enum RoadWear: Int, Sendable, CaseIterable {
    case paved, dirt, overgrown, faint

    public static func of(percent: Int) -> RoadWear {
        switch percent {
        case 80...: .paved
        case 50..<80: .dirt
        case 20..<50: .overgrown
        default: .faint
        }
    }
    public var title: String {
        switch self {
        case .paved: "мощёная"
        case .dirt: "грунтовая"
        case .overgrown: "зарастает"
        case .faint: "едва видна"
        }
    }
    /// Скорость шага по дороге.
    public var speedFactor: Double {
        switch self {
        case .paved: 1.3
        case .dirt: 1.15
        case .overgrown, .faint: 1
        }
    }
}

/// Дорога между соседними городами острова (15A).
public struct IslandRoad: Hashable, Sendable, Identifiable {
    public var id: Int
    public var from: Int
    public var to: Int
    /// Привычка месяца и её выполнение; nil — привычек не было, дорога грунтовая.
    public var habit: String?
    public var percent: Int?
    public var wear: RoadWear
    public var tiles: [TilePoint]

    public var caption: String {
        guard let habit, let percent else { return "Дорога · \(wear.title)" }
        return "Дорога «\(habit)» · \(percent)% · \(wear.title)"
    }
}

public struct IslandCity: Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var center: TilePoint
    public var events: Int
    /// 3, 6 или 10 домов; у деревни — 1.
    public var houses: Int
    public var isCity: Bool
}

public struct IslandNPC: Hashable, Sendable, Identifiable {
    public var id: Int
    public var tier: NPCTier
    public var home: TilePoint
    public var meetings: Int
}

public struct IslandChest: Hashable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var position: TilePoint
    /// Предмет внутри (14.5): каждый сундук даёт один.
    public var item: ExploreItem = .potionHP
    /// Обрывок карты сокровищ (15C.1): номер 0…2 или nil.
    public var fragment: Int?
}

/// Клад (15C.1): место — на острове последнего найденного обрывка.
public struct IslandTreasure: Hashable, Sendable {
    public var title: String
    /// Место клада на каждом острове-месяце (по номеру региона).
    public var spots: [Int: TilePoint]
}

/// Пещера (15C.2): вход и выход на острове, внутри — тёмная подкарта.
public struct IslandCave: Hashable, Sendable, Identifiable {
    public var id: Int
    public var region: Int
    public var entrance: TilePoint
    public var exit: TilePoint
    /// Подкарта side×side: true — стена.
    public var walls: [Bool]
    public var side: Int
    public var start: TilePoint
    public var inner: TilePoint
    public var chests: [TilePoint]
    public var items: [ExploreItem]

    public func isFloor(_ point: TilePoint) -> Bool {
        point.x >= 0 && point.y >= 0 && point.x < side && point.y < side && !walls[point.y * side + point.x]
    }

    /// Путь внутри пещеры (4 направления, BFS).
    public func path(from: TilePoint, to: TilePoint) -> [TilePoint]? {
        guard isFloor(from), isFloor(to) else { return nil }
        var previous = [Int](repeating: -1, count: side * side)
        let start = from.y * side + from.x, goal = to.y * side + to.x
        previous[start] = start
        var queue = [start], head = 0
        while head < queue.count {
            let current = queue[head]; head += 1
            if current == goal { break }
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let next = TilePoint(current % side + dx, current / side + dy)
                guard isFloor(next), previous[next.y * side + next.x] == -1 else { continue }
                previous[next.y * side + next.x] = current
                queue.append(next.y * side + next.x)
            }
        }
        guard previous[goal] != -1 else { return nil }
        var result: [TilePoint] = [], index = goal
        while index != start { result.append(TilePoint(index % side, index / side)); index = previous[index] }
        return result.reversed()
    }
}

/// Смотровая площадка с подзорной трубой (15C.3).
public struct IslandLookout: Hashable, Sendable, Identifiable {
    public var id: Int
    public var region: Int
    public var position: TilePoint
}

/// Расходники из сундуков (14.5) — только в прогулке.
public enum ExploreItem: String, Sendable, CaseIterable, Hashable {
    case potionHP, potionMP, torch, compass

    public var title: String {
        switch self {
        case .potionHP: "Зелье HP"
        case .potionMP: "Зелье MP"
        case .torch: "Факел"
        case .compass: "Компас"
        }
    }

    public var note: String {
        switch self {
        case .potionHP: "+\(Int(ExploreRules.potionShare * 100))% HP"
        case .potionMP: "+\(Int(ExploreRules.potionShare * 100))% MP"
        case .torch: "обзор \(Int(ExploreRules.torchVision)) клеток, \(Int(ExploreRules.torchSeconds)) с"
        case .compass: "к сундуку, \(Int(ExploreRules.compassSeconds)) с"
        }
    }
}

/// Бутылка с письмом — в воде у берега (14.5).
public struct IslandBottle: Hashable, Sendable, Identifiable {
    public var id: Int
    public var position: TilePoint
    public var note: ExploreDiaryNote
}

/// Чёрная башня Epic со стражем (14.5).
public struct IslandTower: Hashable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var steps: Int
    public var position: TilePoint
    /// Финальная Чёрная башня архипелага (15G.2): своё HP и урон.
    public var isFinal = false
    public var finalHP: Double = 0
    public var guardianHP: Double { isFinal ? finalHP : ExploreRules.guardianHP(steps: steps) }
    public var guardianDamageShare: Double { isFinal ? ExploreRules.finalTowerDamageShare : ExploreRules.guardianDamageShare }
}

/// Сектор навыка на острове месяца (15B.1): рост — богаче, без роста — пустошь.
public struct IslandSector: Hashable, Sendable, Identifiable {
    public var id: Int
    public var region: Int
    public var title: String
    public var gain: Double
    public var isWaste: Bool { gain <= 0 }
    /// Табличка у центра сектора.
    public var sign: TilePoint
}

/// Памятник закрытого Epic (15B.2).
public struct IslandMonument: Hashable, Sendable, Identifiable {
    public var id: Int
    public var epic: ExploreClosedEpic
    public var position: TilePoint
}

/// Монумент полезного (15G.4): бафф до конца прогулки.
public struct IslandShrine: Hashable, Sendable, Identifiable {
    public var id: Int
    public var buff: ExploreBuff
    public var marks: Int
    public var position: TilePoint
    public var strength: Double { ExploreBuff.strength(marks: marks) }
}

/// Маяк привычки с серией (14.5) — на берегу.
public struct IslandLighthouse: Hashable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var position: TilePoint
}

/// Задание доски в городе (14.5).
public struct CityTask: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case reachVillage(Int)
        case openChests(Int)
        case lightCampfire
    }
    public var id: Int
    public var cityId: Int
    public var kind: Kind
}

public struct IslandCampfire: Hashable, Sendable, Identifiable {
    public var id: Int
    public var quality: Double
    public var position: TilePoint
}

/// Остров месяца в архипелаге (12B): квадрат `side`×`side` клеток от `origin`.
public struct IslandRegion: Hashable, Sendable, Identifiable {
    public var id: Int
    public var first: LocalDate
    public var last: LocalDate
    public var size: IslandSize
    public var origin: TilePoint
    public var side: Int

    public var days: Int { first.days(until: last) + 1 }
    public var center: TilePoint { TilePoint(origin.x + side / 2, origin.y + side / 2) }
    public func contains(_ point: TilePoint) -> Bool {
        point.x >= origin.x && point.y >= origin.y && point.x < origin.x + side && point.y < origin.y + side
    }
    public var monthTitle: String {
        ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"][first.month - 1]
    }
}

/// Корабль (12B): стоит на воде у берега; одна модель — фрегат.
public struct IslandShip: Hashable, Sendable, Identifiable {
    public var id: Int
    /// Остров, у которого корабль стоял в начале прогулки.
    public var region: Int
    public var position: TilePoint
}

public struct Island: Sendable {
    /// Размер самого большого острова.
    public var size: IslandSize
    /// Сторона мира в клетках: остров или весь архипелаг.
    public var side: Int
    public var terrain: [Terrain]
    public var cities: [IslandCity]
    public var villages: [IslandCity]
    public var npcs: [IslandNPC]
    public var chests: [IslandChest]
    public var campfires: [IslandCampfire]
    public var start: TilePoint
    /// Острова-месяцы (12B); у одного месяца — один остров на весь мир.
    public var regions: [IslandRegion] = []
    /// Корабли — только когда островов больше одного.
    public var ships: [IslandShip] = []
    public var bottles: [IslandBottle] = []
    public var towers: [IslandTower] = []
    public var lighthouses: [IslandLighthouse] = []
    public var tasks: [CityTask] = []
    // Этап 15A.
    /// Высота гор в пикселях изометрии (0 — равнина).
    public var elevation: [UInt8] = []
    /// Климатическая зона клетки (ClimateZone.rawValue).
    public var zones: [UInt8] = []
    public var roads: [IslandRoad] = []
    /// Номер дороги на клетке, −1 — дороги нет.
    public var roadAt: [Int32] = []
    /// Погода острова-месяца — случайная отметка настроения месяца.
    public var regionWeather: [Weather] = []
    // 15B, 15G.
    public var sectors: [IslandSector] = []
    /// Номер сектора клетки, −1 — вне секторов.
    public var sectorAt: [Int8] = []
    public var monuments: [IslandMonument] = []
    public var shrines: [IslandShrine] = []
    /// Болото на клетке.
    public var swamp: [Bool] = []
    // 15C.
    public var treasure: IslandTreasure?
    public var caves: [IslandCave] = []
    public var lookouts: [IslandLookout] = []

    init(size: IslandSize, side: Int? = nil, terrain: [Terrain], cities: [IslandCity], villages: [IslandCity], npcs: [IslandNPC],
         chests: [IslandChest], campfires: [IslandCampfire], start: TilePoint) {
        self.size = size
        self.side = side ?? size.tiles
        self.terrain = terrain
        self.cities = cities
        self.villages = villages
        self.npcs = npcs
        self.chests = chests
        self.campfires = campfires
        self.start = start
    }

    public func zone(at point: TilePoint) -> ClimateZone {
        guard point.x >= 0, point.y >= 0, point.x < side, point.y < side, !zones.isEmpty else { return .temperate }
        return ClimateZone(rawValue: Int(zones[point.y * side + point.x])) ?? .temperate
    }

    public func height(at point: TilePoint) -> Int {
        guard point.x >= 0, point.y >= 0, point.x < side, point.y < side, !elevation.isEmpty else { return 0 }
        return Int(elevation[point.y * side + point.x])
    }

    public func sector(at point: TilePoint) -> IslandSector? {
        guard point.x >= 0, point.y >= 0, point.x < side, point.y < side, !sectorAt.isEmpty else { return nil }
        let index = Int(sectorAt[point.y * side + point.x])
        return index >= 0 ? sectors[index] : nil
    }

    public func isSwamp(_ point: TilePoint) -> Bool {
        guard point.x >= 0, point.y >= 0, point.x < side, point.y < side, !swamp.isEmpty else { return false }
        return swamp[point.y * side + point.x]
    }

    public func road(at point: TilePoint) -> IslandRoad? {
        guard point.x >= 0, point.y >= 0, point.x < side, point.y < side, !roadAt.isEmpty else { return nil }
        let index = Int(roadAt[point.y * side + point.x])
        return index >= 0 ? roads[index] : nil
    }

    /// Погода острова-месяца под клеткой (в том числе над водой у острова).
    public func weather(at point: TilePoint) -> Weather {
        guard let region = regions.min(by: { $0.center.distance(to: point) < $1.center.distance(to: point) }),
              regionWeather.indices.contains(region.id) else { return .clear }
        return regionWeather[region.id]
    }

    /// Можно идти: суша, кроме гор.
    public func isWalkable(_ point: TilePoint) -> Bool {
        let kind = terrain(at: point)
        return kind != .water && kind != .mountain
    }

    /// Остров месяца под клеткой суши.
    public func region(at point: TilePoint) -> IslandRegion? {
        guard isLand(point) else { return nil }
        return regions.first { $0.contains(point) }
    }

    /// Клетка суши рядом с кораблём — куда сойти на берег (сначала по сторонам, потом по диагонали).
    public func landing(near point: TilePoint) -> TilePoint? {
        let around = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
        return around.map { TilePoint(point.x + $0.0, point.y + $0.1) }.first { isWalkable($0) }
    }

    /// Путь корабля по воде (8 направлений, BFS; углы суши не срезает). nil — недостижимо.
    public func seaPath(from: TilePoint, to: TilePoint) -> [TilePoint]? {
        guard !isLand(from), !isLand(to), from.x >= 0, from.y >= 0, to.x >= 0, to.y >= 0,
              from.x < side, from.y < side, to.x < side, to.y < side else { return nil }
        if from == to { return [from] }
        var previous = [Int](repeating: -1, count: side * side)
        let startIndex = from.y * side + from.x, goalIndex = to.y * side + to.x
        previous[startIndex] = startIndex
        var queue = [startIndex], head = 0
        let steps = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
        while head < queue.count {
            let current = queue[head]; head += 1
            if current == goalIndex { break }
            let cx = current % side, cy = current / side
            for (dx, dy) in steps {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, ny >= 0, nx < side, ny < side else { continue }
                if dx != 0, dy != 0, isLand(TilePoint(cx + dx, cy)) || isLand(TilePoint(cx, cy + dy)) { continue }
                let next = ny * side + nx
                guard previous[next] == -1, terrain[next] == .water else { continue }
                previous[next] = current
                queue.append(next)
            }
        }
        guard previous[goalIndex] != -1 else { return nil }
        var result: [TilePoint] = []
        var index = goalIndex
        while index != startIndex { result.append(TilePoint(index % side, index / side)); index = previous[index] }
        result.append(from)
        return result.reversed()
    }

    public func terrain(at point: TilePoint) -> Terrain {
        guard point.x >= 0, point.y >= 0, point.x < side, point.y < side else { return .water }
        return terrain[point.y * side + point.x]
    }
    public func isLand(_ point: TilePoint) -> Bool { terrain(at: point) != .water }

    /// Безопасная зона: в радиусе от центра города (деревни — не безопасны).
    public func safeCity(at point: TilePoint) -> IslandCity? {
        cities.first { $0.center.distance(to: point) <= Double(ExploreRules.citySafeRadius) }
    }

    /// Путь по суше (8 направлений, BFS). nil — недостижимо.
    public func path(from: TilePoint, to: TilePoint) -> [TilePoint]? {
        guard isWalkable(from), isWalkable(to) else { return nil }
        if from == to { return [from] }
        var previous = [Int](repeating: -1, count: side * side)
        let startIndex = from.y * side + from.x, goalIndex = to.y * side + to.x
        previous[startIndex] = startIndex
        var queue = [startIndex], head = 0
        let steps = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
        while head < queue.count {
            let current = queue[head]; head += 1
            if current == goalIndex { break }
            let cx = current % side, cy = current / side
            for (dx, dy) in steps {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, ny >= 0, nx < side, ny < side else { continue }
                // По диагонали — только если обе соседние клетки — суша (не срезаем углы через воду).
                if dx != 0, dy != 0, !(isWalkable(TilePoint(cx + dx, cy)) && isWalkable(TilePoint(cx, cy + dy))) { continue }
                let next = ny * side + nx
                guard previous[next] == -1, terrain[next] != .water, terrain[next] != .mountain else { continue }
                previous[next] = current
                queue.append(next)
            }
        }
        guard previous[goalIndex] != -1 else { return nil }
        var result: [TilePoint] = []
        var index = goalIndex
        while index != startIndex { result.append(TilePoint(index % side, index / side)); index = previous[index] }
        result.append(from)
        return result.reversed()
    }
}

public enum IslandGenerator {
    /// Архипелаг (12B): остров на каждый месяц диапазона, по порядку месяцев сверху вниз со сдвигом; старт — на острове
    /// последнего месяца. Один месяц — один остров, как раньше, без кораблей.
    public static func generate(_ input: ExploreInput, seed: UInt64) -> Island {
        let months = input.months
        let parts = months.enumerated().map { index, month in
            single(input.slice(first: month.first, last: month.last, isLastMonth: index == months.count - 1),
                   seed: index == 0 ? seed : seed &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15)
        }
        guard parts.count > 1 else {
            var island = parts[0]
            island.regions = [IslandRegion(id: 0, first: input.first, last: input.last, size: island.size, origin: TilePoint(0, 0), side: island.side)]
            finish(&island, seed: seed, days: input.days, treasure: input.treasureQuest)
            return island
        }

        // Раскладка: следующий остров — то вправо-вниз (+x), то влево-вниз (+y) на экране изометрии; квадраты не пересекаются.
        let gap = ExploreRules.islandGap, margin = ExploreRules.worldMargin
        var origins = [TilePoint(0, 0)]
        for index in 1..<parts.count {
            let previous = origins[index - 1], before = parts[index - 1].side, shift = (before - parts[index].side) / 2
            origins.append(index % 2 == 1 ? TilePoint(previous.x + before + gap, previous.y + shift)
                                          : TilePoint(previous.x + shift, previous.y + before + gap))
        }
        let minX = origins.map(\.x).min() ?? 0, minY = origins.map(\.y).min() ?? 0
        origins = origins.map { TilePoint($0.x - minX + margin, $0.y - minY + margin) }
        let side = zip(origins, parts).map { max($0.x, $0.y) + $1.side }.max()! + margin

        var terrain = [Terrain](repeating: .water, count: side * side)
        var world = Island(size: parts.map(\.size).max { $0.tiles < $1.tiles } ?? .small, side: side, terrain: [],
                           cities: [], villages: [], npcs: [], chests: [], campfires: [], start: TilePoint(0, 0))
        var elevation = [UInt8](repeating: 0, count: side * side)
        var sectorAt = [Int8](repeating: -1, count: side * side)
        var swamp = [Bool](repeating: false, count: side * side)
        func moved(_ point: TilePoint, _ origin: TilePoint) -> TilePoint { TilePoint(point.x + origin.x, point.y + origin.y) }
        for (index, part) in parts.enumerated() {
            let origin = origins[index]
            for y in 0..<part.side { for x in 0..<part.side {
                terrain[(y + origin.y) * side + x + origin.x] = part.terrain[y * part.side + x]
                elevation[(y + origin.y) * side + x + origin.x] = part.elevation[y * part.side + x]
            } }
            for var city in part.cities {
                city.id = world.cities.count; city.center = moved(city.center, origin); world.cities.append(city)
            }
            for var village in part.villages {
                village.id = 1000 + world.villages.count; village.center = moved(village.center, origin); world.villages.append(village)
            }
            for var npc in part.npcs { npc.id = world.npcs.count; npc.home = moved(npc.home, origin); world.npcs.append(npc) }
            for var chest in part.chests { chest.id = world.chests.count; chest.position = moved(chest.position, origin); world.chests.append(chest) }
            let villageBase = world.villages.count - part.villages.count, cityBase = world.cities.count - part.cities.count
            for var fire in part.campfires { fire.id = world.campfires.count; fire.position = moved(fire.position, origin); world.campfires.append(fire) }
            for var bottle in part.bottles { bottle.id = world.bottles.count; bottle.position = moved(bottle.position, origin); world.bottles.append(bottle) }
            for var tower in part.towers { tower.id = world.towers.count; tower.position = moved(tower.position, origin); world.towers.append(tower) }
            for var light in part.lighthouses { light.id = world.lighthouses.count; light.position = moved(light.position, origin); world.lighthouses.append(light) }
            for var task in part.tasks {
                task.id = world.tasks.count
                task.cityId += cityBase
                if case let .reachVillage(village) = task.kind { task.kind = .reachVillage(1000 + village - 1000 + villageBase) }
                world.tasks.append(task)
            }
            for var road in part.roads {
                road.id = world.roads.count
                road.from += cityBase
                road.to += cityBase
                road.tiles = road.tiles.map { moved($0, origin) }
                world.roads.append(road)
            }
            world.regionWeather.append(part.regionWeather.first ?? .clear)
            let sectorBase = world.sectors.count
            for var sector in part.sectors {
                sector.id = world.sectors.count; sector.region = index; sector.sign = moved(sector.sign, origin); world.sectors.append(sector)
            }
            for var monument in part.monuments { monument.id = world.monuments.count; monument.position = moved(monument.position, origin); world.monuments.append(monument) }
            for var shrine in part.shrines { shrine.id = world.shrines.count; shrine.position = moved(shrine.position, origin); world.shrines.append(shrine) }
            for var cave in part.caves {
                cave.id = world.caves.count; cave.region = index
                cave.entrance = moved(cave.entrance, origin); cave.exit = moved(cave.exit, origin)
                world.caves.append(cave)
            }
            for var lookout in part.lookouts { lookout.id = world.lookouts.count; lookout.region = index; lookout.position = moved(lookout.position, origin); world.lookouts.append(lookout) }
            for y in 0..<part.side { for x in 0..<part.side {
                let source = y * part.side + x, target = (y + origin.y) * side + x + origin.x
                if !part.sectorAt.isEmpty, part.sectorAt[source] >= 0 { sectorAt[target] = Int8(sectorBase + Int(part.sectorAt[source])) }
                if !part.swamp.isEmpty, part.swamp[source] { swamp[target] = true }
            } }
            world.regions.append(IslandRegion(id: index, first: months[index].first, last: months[index].last,
                                              size: part.size, origin: origin, side: part.side))
        }
        world.terrain = terrain
        world.elevation = elevation
        world.sectorAt = sectorAt
        world.swamp = swamp
        // Старт (15G.2) — на северо-западном берегу первого (самого раннего) острова.
        world.start = moved(parts[0].start, origins[0])
        world.ships = ships(in: world)
        // У корабля, как у старта, NPC не стоят — высадка не начинается со встречи.
        world.npcs = world.npcs.filter { npc in
            world.ships.allSatisfy { $0.position.distance(to: npc.home) >= ExploreRules.harbourRadius }
        }
        for index in world.npcs.indices { world.npcs[index].id = index }
        finish(&world, seed: seed, days: input.days, treasure: input.treasureQuest)
        return world
    }

    /// Общее для острова и архипелага (15A): зоны климата по всему миру и клетки дорог.
    static func finish(_ island: inout Island, seed: UInt64, days: Int = 0, treasure: ExploreDoneQuest? = nil) {
        finalTower(&island, days: days)
        if let treasure { hideTreasure(&island, title: treasure.title, seed: seed) }
        island.zones = climate(side: island.side, seed: seed)
        island.roadAt = [Int32](repeating: -1, count: island.side * island.side)
        for road in island.roads {
            for tile in road.tiles where tile.x >= 0 && tile.y >= 0 && tile.x < island.side && tile.y < island.side {
                let index = tile.y * island.side + tile.x
                // На пересечении — лучшая дорога.
                if island.roadAt[index] < 0 || island.roads[Int(island.roadAt[index])].wear.rawValue > road.wear.rawValue {
                    island.roadAt[index] = Int32(road.id)
                }
            }
        }
    }

    /// Клад (15C.1): три обрывка в сундуках разных островов (не у старта), место клада — на каждом острове.
    static func hideTreasure(_ island: inout Island, title: String, seed: UInt64) {
        var random = ExploreRandom(seed ^ 0x7EA5_0000)
        let candidates = island.chests.indices.filter { island.chests[$0].position.distance(to: island.start) > 8 }
        guard !candidates.isEmpty else { return }
        var chosen: [Int] = []
        // Сначала — по одному сундуку с каждого острова, затем любые.
        let byRegion = Dictionary(grouping: candidates) { island.region(at: island.chests[$0].position)?.id ?? 0 }
        for region in byRegion.keys.sorted() where chosen.count < ExploreRules.treasureFragments {
            let pool = byRegion[region]!
            chosen.append(pool[random.int(pool.count)])
        }
        while chosen.count < min(ExploreRules.treasureFragments, candidates.count) {
            let pick = candidates[random.int(candidates.count)]
            if !chosen.contains(pick) { chosen.append(pick) }
        }
        for (k, index) in chosen.enumerated() { island.chests[index].fragment = k }
        var spots: [Int: TilePoint] = [:]
        for region in island.regions {
            var best: TilePoint?
            for _ in 0..<300 {
                let point = TilePoint(region.origin.x + random.int(region.side), region.origin.y + random.int(region.side))
                guard island.isWalkable(point), island.road(at: point) == nil,
                      island.cities.allSatisfy({ $0.center.distance(to: point) >= 10 }) else { continue }
                best = point
                break
            }
            if let best { spots[region.id] = best }
        }
        island.treasure = IslandTreasure(title: title, spots: spots)
    }

    /// Финальная Чёрная башня (15G.2): на острове последнего месяца, в самой дальней от старта точке суши (не у городов).
    static func finalTower(_ island: inout Island, days: Int) {
        guard let region = island.regions.last else { return }
        var best: TilePoint?, bestDistance = -1.0
        for y in region.origin.y..<min(island.side, region.origin.y + region.side) {
            for x in region.origin.x..<min(island.side, region.origin.x + region.side) {
                let point = TilePoint(x, y)
                guard island.isWalkable(point), island.road(at: point) == nil,
                      island.cities.allSatisfy({ $0.center.distance(to: point) > Double(ExploreRules.citySafeRadius + 2) }),
                      island.towers.allSatisfy({ $0.position.distance(to: point) > 3 }) else { continue }
                // Рядом должна быть ещё суша — чтобы к башне можно было подойти.
                guard [(1, 0), (-1, 0), (0, 1), (0, -1)].filter({ island.isWalkable(TilePoint(x + $0.0, y + $0.1)) }).count >= 2 else { continue }
                let distance = point.distance(to: island.start)
                if distance > bestDistance { bestDistance = distance; best = point }
            }
        }
        guard let best else { return }
        var tower = IslandTower(id: island.towers.count, title: "Финальная башня", steps: 0, position: best)
        tower.isFinal = true
        tower.finalHP = ExploreRules.finalTowerHP(days: days)
        island.towers.append(tower)
    }

    /// Климат (15A): зона — по «широте» на экране изометрии (x + y), граница волнистая, у самой границы клетки перемешаны.
    static func climate(side: Int, seed: UInt64) -> [UInt8] {
        var random = ExploreRandom(seed ^ 0xC11A_7E00)
        let noise = valueNoise(side: side, cell: max(8, side / 14), random: &random)
        let span = Double(max(1, 2 * (side - 1)))
        return (0..<(side * side)).map { index in
            let x = index % side, y = index / side
            var hash = UInt64(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263) ^ seed
            hash = (hash ^ (hash >> 13)) &* 1_274_126_177
            let jitter = Double(hash % 1000) / 1000
            let t = Double(x + y) / span + (noise[index] - 0.5) * 0.16 + (jitter - 0.5) * 0.025
            return UInt8(max(0, min(4, Int(t * 5))))
        }
    }

    /// Корабль у каждого острова: вода открытого моря рядом с сушей, ближе всего к соседнему острову.
    static func ships(in island: Island) -> [IslandShip] {
        let side = island.side
        // Открытое море — связная вода от угла мира (озёра внутри островов не годятся).
        var sea = [Bool](repeating: false, count: side * side)
        var stack = [0]
        sea[0] = true
        while let current = stack.popLast() {
            let cx = current % side, cy = current / side
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, ny >= 0, nx < side, ny < side else { continue }
                let next = ny * side + nx
                if !sea[next], island.terrain[next] == .water { sea[next] = true; stack.append(next) }
            }
        }
        return island.regions.map { region in
            let neighbour = island.regions[region.id == island.regions.count - 1 ? region.id - 1 : region.id + 1].center
            var best = region.center, bestDistance = Double.infinity
            for y in max(0, region.origin.y - 2)..<min(side, region.origin.y + region.side + 2) {
                for x in max(0, region.origin.x - 2)..<min(side, region.origin.x + region.side + 2) where sea[y * side + x] {
                    let point = TilePoint(x, y)
                    let touchesLand = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { dx, dy in
                        let near = TilePoint(x + dx, y + dy)
                        return island.isLand(near) && region.contains(near)
                    }
                    guard touchesLand else { continue }
                    let distance = point.distance(to: neighbour)
                    if distance < bestDistance { bestDistance = distance; best = point }
                }
            }
            return IslandShip(id: region.id, region: region.id, position: best)
        }
    }

    /// Погода острова-месяца (15A): случайная отметка настроения месяца; плохо — осадки (в холодных зонах — снег),
    /// нормально — облачно, хорошо и без отметок — ясно.
    static func weather(_ input: ExploreInput, random: inout ExploreRandom) -> Weather {
        var pool = input.moods.map(\.mood)
        if pool.isEmpty {
            pool = input.weekMoods.filter { $0.key >= input.first.weekStart && $0.key <= input.last }.sorted { $0.key < $1.key }.map(\.value)
        }
        guard !pool.isEmpty else { return .clear }
        switch pool[random.int(pool.count)] {
        case .good: return .clear
        case .neutral: return .cloudy
        case .bad: return .rain
        }
    }

    /// Один остров по данным одного месяца (или всего диапазона).
    static func single(_ input: ExploreInput, seed: UInt64) -> Island {
        var random = ExploreRandom(seed)
        let size = ExploreRules.islandSize(days: input.days)
        let side = size.tiles
        var terrain = landMask(side: side, random: &random)
        let elevation = mountains(&terrain, side: side, random: &random)

        // Пляж — суша у воды, лес — пятна шума.
        let forestNoise = valueNoise(side: side, cell: 6, random: &random)
        for y in 0..<side { for x in 0..<side where terrain[y * side + x] != .water && terrain[y * side + x] != .mountain {
            let nearWater = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { dx, dy in
                let nx = x + dx, ny = y + dy
                return nx < 0 || ny < 0 || nx >= side || ny >= side || terrain[ny * side + nx] == .water
            }
            terrain[y * side + x] = nearWater ? .sand : (forestNoise[y * side + x] > 0.62 ? .forest : .grass)
        } }
        var island = Island(size: size, terrain: terrain, cities: [], villages: [], npcs: [], chests: [], campfires: [],
                            start: TilePoint(side / 2, side / 2))
        island.elevation = elevation
        var occupied: [TilePoint] = []

        func freeSpot(minDistance: Double, from others: [TilePoint], avoid: [(TilePoint, Double)] = [], attempts: Int = 400) -> TilePoint? {
            for _ in 0..<attempts {
                let point = TilePoint(random.int(side), random.int(side))
                guard island.terrain(at: point) == .grass || island.terrain(at: point) == .forest else { continue }
                guard others.allSatisfy({ $0.distance(to: point) >= minDistance }),
                      avoid.allSatisfy({ $0.0.distance(to: point) >= $0.1 }) else { continue }
                return point
            }
            return nil
        }

        // Города и деревни: события по названию (02, ответ 9).
        let groups = Dictionary(grouping: input.events) { $0.title.trimmingCharacters(in: .whitespaces).lowercased() }
            .map { (name: $0.value[0].title.trimmingCharacters(in: .whitespaces), count: $0.value.count) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
        var cityCenters: [TilePoint] = []
        for group in groups.filter({ $0.count >= 2 }).prefix(size.cityCap) {
            guard let spot = freeSpot(minDistance: Double(ExploreRules.cityMinDistance), from: cityCenters) else { continue }
            cityCenters.append(spot)
            occupied.append(spot)
            let houses = group.count >= 10 ? 10 : group.count >= 5 ? 6 : 3
            island.cities.append(IslandCity(id: island.cities.count, name: group.name, center: spot, events: group.count, houses: houses, isCity: true))
        }
        for group in groups.filter({ $0.count == 1 }).prefix(size.villageCap) {
            guard let spot = freeSpot(minDistance: Double(ExploreRules.villageMinDistance), from: occupied) else { continue }
            occupied.append(spot)
            island.villages.append(IslandCity(id: 1000 + island.villages.count, name: group.name, center: spot, events: 1, houses: 1, isCity: false))
        }
        // Старт (15G.2) — на берегу в самой северо-западной части острова: на экране изометрии это наименьший x.
        island.start = northWestShore(island) ?? island.cities.first?.center ?? nearestLand(to: TilePoint(side / 2, side / 2), in: island)
        roads(&island, input: input)

        // NPC: уникальные участники, потолок по размеру — самые частые остаются.
        var meetings: [String: Int] = [:]
        for event in input.events { for key in Set(event.attendeeKeys) { meetings[key, default: 0] += 1 } }
        let people = meetings.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(size.npcCap)
        let safe = island.cities.map { ($0.center, Double(ExploreRules.citySafeRadius + 2)) }
        for (index, person) in people.enumerated() {
            guard let spot = freeSpot(minDistance: 2, from: island.npcs.map(\.home),
                                      avoid: safe + [(island.start, Double(ExploreRules.npcMinDistanceFromStart))]) else { continue }
            island.npcs.append(IslandNPC(id: index, tier: NPCTier.of(meetings: person.value), home: spot, meetings: person.value))
        }

        // Сундуки: квесты по приоритету, не больше 30.
        let order: [QuestPriority] = [.high, .medium, .low]
        let quests = input.quests.sorted { (order.firstIndex(of: $0.priority) ?? 1) < (order.firstIndex(of: $1.priority) ?? 1) }
        for quest in quests.prefix(ExploreRules.chestCap) {
            guard let spot = freeSpot(minDistance: 2, from: occupied) else { continue }
            occupied.append(spot)
            island.chests.append(IslandChest(id: island.chests.count, title: quest.title, position: spot))
        }

        // Костры: лучшая ночь каждой недели.
        let byWeek = Dictionary(grouping: input.nights) { $0.key.weekStart }
        for week in byWeek.keys.sorted() {
            guard let best = byWeek[week]?.map(\.value).max(), let spot = freeSpot(minDistance: 3, from: occupied) else { continue }
            occupied.append(spot)
            island.campfires.append(IslandCampfire(id: island.campfires.count, quality: best, position: spot))
        }

        // Предметы в сундуках — по зерну.
        for index in island.chests.indices {
            island.chests[index].item = ExploreItem.allCases[random.int(ExploreItem.allCases.count)]
        }
        // Чёрные башни Epic — вдали от старта (14.5).
        for epic in input.epics.prefix(ExploreRules.towerCap) {
            guard let spot = freeSpot(minDistance: 4, from: occupied, avoid: [(island.start, ExploreRules.towerMinDistanceFromStart)]) else { continue }
            occupied.append(spot)
            island.towers.append(IslandTower(id: island.towers.count, title: epic.title, steps: epic.steps, position: spot))
        }
        // Маяки — на песке у воды, для привычек с серией от 7 дней в этом месяце.
        let sands = (0..<(side * side)).compactMap { index -> TilePoint? in
            island.terrain[index] == .sand ? TilePoint(index % side, index / side) : nil
        }
        for habit in input.habits where habit.longestStreak(from: input.first, through: input.last) >= ExploreRules.lighthouseStreak {
            let options = sands.filter { point in island.lighthouses.allSatisfy { $0.position.distance(to: point) >= 10 } }
            guard !options.isEmpty else { break }
            island.lighthouses.append(IslandLighthouse(id: island.lighthouses.count, title: habit.title, position: options[random.int(options.count)]))
        }
        // Бутылки — в воде рядом с берегом: подобрать с берега или с корабля.
        let shoreWater = (0..<(side * side)).compactMap { index -> TilePoint? in
            guard island.terrain[index] == .water else { return nil }
            let point = TilePoint(index % side, index / side)
            return [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { island.terrain(at: TilePoint(point.x + $0.0, point.y + $0.1)) == .sand } ? point : nil
        }
        for note in input.diary.prefix(ExploreRules.bottleCap) where !shoreWater.isEmpty {
            let options = shoreWater.filter { point in island.bottles.allSatisfy { $0.position.distance(to: point) >= 6 } }
            let pool = options.isEmpty ? shoreWater : options
            let spot = pool[random.int(pool.count)]
            island.bottles.append(IslandBottle(id: island.bottles.count, position: spot, note: note))
        }
        // Доска заданий — одно задание в каждом городе.
        for city in island.cities {
            let kind: CityTask.Kind
            switch random.int(3) {
            case 0 where !island.villages.isEmpty:
                let village = island.villages.min { $0.center.distance(to: city.center) < $1.center.distance(to: city.center) }!
                kind = .reachVillage(village.id)
            case 2 where !island.campfires.isEmpty: kind = .lightCampfire
            default: kind = island.chests.count >= ExploreRules.taskChests ? .openChests(ExploreRules.taskChests) : .lightCampfire
            }
            island.tasks.append(CityTask(id: island.tasks.count, cityId: city.id, kind: kind))
        }
        island.regionWeather = [weather(input, random: &random)]
        lifeOnMap(&island, input: input, random: &random)
        exploration(&island, random: &random)
        return island
    }

    /// 15C на острове месяца: пещера (вход и выход у подножия гор) и смотровая площадка.
    static func exploration(_ island: inout Island, random: inout ExploreRandom) {
        let side = island.side
        // Клетки у подножия: можно стоять, рядом гора, не дорога и не город.
        var foot: [TilePoint] = []
        for y in 0..<side { for x in 0..<side {
            let point = TilePoint(x, y)
            guard island.isWalkable(point), island.road(at: point) == nil, island.safeCity(at: point) == nil,
                  [(1, 0), (-1, 0), (0, 1), (0, -1)].contains(where: { island.terrain(at: TilePoint(x + $0.0, y + $0.1)) == .mountain }) else { continue }
            foot.append(point)
        } }
        if foot.count >= 2 {
            let entrance = foot[random.int(foot.count)]
            let far = foot.filter { $0.distance(to: entrance) >= ExploreRules.caveMinSpan }
            if let exit = far.isEmpty ? nil : far[random.int(far.count)] {
                var cave = caveInterior(random: &random)
                cave.entrance = entrance
                cave.exit = exit
                island.caves.append(cave)
            }
        }
        // Площадка: у самой высокой горы; без гор — самый дальний от центра берег.
        if let best = foot.max(by: { a, b in
            func height(_ p: TilePoint) -> Int { [(1, 0), (-1, 0), (0, 1), (0, -1)].map { island.height(at: TilePoint(p.x + $0.0, p.y + $0.1)) }.max() ?? 0 }
            return (height(a), b.x + b.y) < (height(b), a.x + a.y)
        }) {
            island.lookouts.append(IslandLookout(id: 0, region: 0, position: best))
        } else {
            let center = TilePoint(side / 2, side / 2)
            let shore = (0..<(side * side)).map { TilePoint($0 % side, $0 / side) }.filter { island.terrain(at: $0) == .sand && island.isWalkable($0) }
            if let cape = shore.max(by: { $0.distance(to: center) < $1.distance(to: center) }) {
                island.lookouts.append(IslandLookout(id: 0, region: 0, position: cape))
            }
        }
    }

    /// Подкарта пещеры: клеточный автомат, самая большая связная часть; старт и выход — в дальних концах, тайники — вдали от старта.
    static func caveInterior(random: inout ExploreRandom) -> IslandCave {
        let n = ExploreRules.caveSide
        var walls = (0..<(n * n)).map { i in i % n == 0 || i / n == 0 || i % n == n - 1 || i / n == n - 1 || random.unit() < 0.45 }
        for _ in 0..<4 {
            walls = (0..<(n * n)).map { i in
                let x = i % n, y = i / n
                var count = 0
                for dy in -1...1 { for dx in -1...1 {
                    let nx = x + dx, ny = y + dy
                    count += (nx < 0 || ny < 0 || nx >= n || ny >= n || walls[ny * n + nx]) ? 1 : 0
                } }
                return count >= 5 || x == 0 || y == 0 || x == n - 1 || y == n - 1
            }
        }
        // Самая большая связная часть пола.
        var component = [Int](repeating: -1, count: n * n), best = (id: -1, count: 0), id = 0
        for start in 0..<(n * n) where !walls[start] && component[start] == -1 {
            var stack = [start], count = 0
            component[start] = id
            while let current = stack.popLast() {
                count += 1
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = current % n + dx, ny = current / n + dy
                    guard nx >= 0, ny >= 0, nx < n, ny < n else { continue }
                    let next = ny * n + nx
                    if !walls[next], component[next] == -1 { component[next] = id; stack.append(next) }
                }
            }
            if count > best.count { best = (id, count) }
            id += 1
        }
        walls = walls.indices.map { walls[$0] || component[$0] != best.id }
        let floor = walls.indices.filter { !walls[$0] }.map { TilePoint($0 % n, $0 / n) }
        let start = floor.min { $0.x + $0.y < $1.x + $1.y } ?? TilePoint(1, 1)
        var cave = IslandCave(id: 0, region: 0, entrance: start, exit: start, walls: walls, side: n, start: start, inner: start, chests: [], items: [])
        let distance = floor.map { (point: $0, steps: cave.path(from: start, to: $0)?.count ?? 0) }
        cave.inner = distance.max { $0.steps < $1.steps }?.point ?? start
        let candidates = distance.filter { $0.steps >= 8 && $0.point != cave.inner }.map(\.point)
        for _ in 0..<ExploreRules.caveChests where !candidates.isEmpty {
            let options = candidates.filter { point in cave.chests.allSatisfy { $0.distance(to: point) >= 5 } }
            let pool = options.isEmpty ? candidates : options
            cave.chests.append(pool[random.int(pool.count)])
            cave.items.append(ExploreItem.allCases[random.int(ExploreItem.allCases.count)])
        }
        return cave
    }

    /// Самая северо-западная клетка берега: суша, где можно стоять, рядом с водой.
    static func northWestShore(_ island: Island) -> TilePoint? {
        var best: TilePoint?
        for y in 0..<island.side { for x in 0..<island.side {
            let point = TilePoint(x, y)
            guard island.isWalkable(point),
                  [(1, 0), (-1, 0), (0, 1), (0, -1)].contains(where: { island.terrain(at: TilePoint(x + $0.0, y + $0.1)) == .water }) else { continue }
            if let current = best, (current.x, current.x + current.y) <= (x, x + y) { continue }
            best = point
        } }
        return best
    }

    /// 15B и 15G.4 на острове месяца: сектора навыков, памятники Epic, монументы полезного, болото.
    static func lifeOnMap(_ island: inout Island, input: ExploreInput, random: inout ExploreRandom) {
        let side = island.side
        let walkable = (0..<(side * side)).filter { island.isWalkable(TilePoint($0 % side, $0 / side)) }
        guard !walkable.isEmpty else { return }
        // Сектора: три навыка с наибольшим ростом за месяц, по углу от центра суши.
        let skills = input.skillGains.map { ($0.title, $0.gain(from: input.first, through: input.last)) }
            .sorted { ($0.1, $1.0) > ($1.1, $0.0) }.prefix(ExploreRules.sectorSkills)
        island.sectorAt = [Int8](repeating: -1, count: side * side)
        if !skills.isEmpty {
            let cx = Double(walkable.map { $0 % side }.reduce(0, +)) / Double(walkable.count)
            let cy = Double(walkable.map { $0 / side }.reduce(0, +)) / Double(walkable.count)
            var members = [[Int]](repeating: [], count: skills.count)
            for index in walkable {
                let angle = atan2(Double(index / side) - cy, Double(index % side) - cx) + .pi
                let part = min(2, Int(angle / (2 * .pi) * 3))
                guard part < skills.count else { continue }
                island.sectorAt[index] = Int8(part)
                members[part].append(index)
            }
            for (k, skill) in skills.enumerated() where !members[k].isEmpty {
                let mx = Double(members[k].map { $0 % side }.reduce(0, +)) / Double(members[k].count)
                let my = Double(members[k].map { $0 / side }.reduce(0, +)) / Double(members[k].count)
                let sign = members[k].min { hypot(Double($0 % side) - mx, Double($0 / side) - my) < hypot(Double($1 % side) - mx, Double($1 / side) - my) }!
                island.sectors.append(IslandSector(id: k, region: 0, title: skill.0, gain: skill.1, sign: TilePoint(sign % side, sign / side)))
            }
        }
        // Свободная клетка у города (или где угодно): не дорога, не занята.
        var taken = Set((island.cities + island.villages).map(\.center) + island.chests.map(\.position) + island.campfires.map(\.position)
                        + island.towers.map(\.position) + island.lighthouses.map(\.position))
        func spot(near center: TilePoint?) -> TilePoint? {
            if let center {
                for radius in 4...7 { for _ in 0..<12 {
                    let angle = random.unit() * 2 * .pi
                    let point = TilePoint(center.x + Int((cos(angle) * Double(radius)).rounded()), center.y + Int((sin(angle) * Double(radius)).rounded()))
                    if island.isWalkable(point), island.road(at: point) == nil, !taken.contains(point) { taken.insert(point); return point }
                } }
            }
            for _ in 0..<200 {
                let index = walkable[random.int(walkable.count)]
                let point = TilePoint(index % side, index / side)
                if island.road(at: point) == nil, !taken.contains(point) { taken.insert(point); return point }
            }
            return nil
        }
        func city() -> TilePoint? { island.cities.isEmpty ? nil : island.cities[random.int(island.cities.count)].center }
        for epic in input.closedEpics {
            guard let position = spot(near: city()) else { continue }
            island.monuments.append(IslandMonument(id: island.monuments.count, epic: epic, position: position))
        }
        let counts = Dictionary(grouping: input.benefits, by: \.buff).mapValues(\.count)
        for buff in ExploreBuff.allCases {
            guard let marks = counts[buff], marks > 0, let position = spot(near: city()) else { continue }
            island.shrines.append(IslandShrine(id: island.shrines.count, buff: buff, marks: marks, position: position))
        }
        // Болото: пятен = вредное − полезное, не больше 8; не у городов и не на дорогах.
        island.swamp = [Bool](repeating: false, count: side * side)
        let patches = min(ExploreRules.swampCap, max(0, input.harmDays.count - input.benefits.count))
        let noise = valueNoise(side: side, cell: 3, random: &random)
        var placed = 0, attempts = 0
        while placed < patches && attempts < 400 {
            attempts += 1
            let index = walkable[random.int(walkable.count)]
            let center = TilePoint(index % side, index / side)
            guard island.cities.allSatisfy({ $0.center.distance(to: center) > Double(ExploreRules.citySafeRadius + 3) }),
                  center.distance(to: island.start) > 6 else { continue }
            let r = Int(ExploreRules.swampRadius.rounded(.up)) + 1
            for dy in -r...r { for dx in -r...r {
                let point = TilePoint(center.x + dx, center.y + dy)
                guard point.x >= 0, point.y >= 0, point.x < side, point.y < side else { continue }
                let i = point.y * side + point.x
                let distance = hypot(Double(dx), Double(dy)) + (noise[i] - 0.5) * 2
                guard distance <= ExploreRules.swampRadius, island.isWalkable(point), island.road(at: point) == nil, !taken.contains(point) else { continue }
                island.swamp[i] = true
            } }
            placed += 1
        }
    }

    /// Горы (15A): массивы там, где шум высоты выше порога, не ближе 4 клеток к морю; высота растёт к центру массива.
    /// К суше, отрезанной горами, прорубается перевал — все объекты достижимы пешком.
    static func mountains(_ terrain: inout [Terrain], side: Int, random: inout ExploreRandom) -> [UInt8] {
        let coast = distance(side: side) { terrain[$0] == .water }
        let height = valueNoise(side: side, cell: max(8, side / 10), random: &random)
        let detail = valueNoise(side: side, cell: 4, random: &random)
        var value = [Double](repeating: 0, count: side * side)
        for index in terrain.indices where terrain[index] != .water && coast[index] >= ExploreRules.mountainCoastDistance {
            let h = height[index] + (detail[index] - 0.5) * 0.12
            if h > ExploreRules.mountainThreshold { terrain[index] = .mountain; value[index] = h }
        }
        // Карманы суши за горами: к каждому прорубается перевал — кратчайший путь сквозь горы к главной части.
        func components() -> (ids: [Int], main: Int) {
            var component = [Int](repeating: -1, count: side * side)
            var best = (id: -1, count: 0), id = 0
            for start in terrain.indices where terrain[start] != .water && terrain[start] != .mountain && component[start] == -1 {
                var stack = [start], count = 0
                component[start] = id
                while let current = stack.popLast() {
                    count += 1
                    let cx = current % side, cy = current / side
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = cx + dx, ny = cy + dy
                        guard nx >= 0, ny >= 0, nx < side, ny < side else { continue }
                        let next = ny * side + nx
                        if terrain[next] != .water, terrain[next] != .mountain, component[next] == -1 { component[next] = id; stack.append(next) }
                    }
                }
                if count > best.count { best = (id, count) }
                id += 1
            }
            return (component, best.id)
        }
        for _ in 0..<32 {
            let (component, main) = components()
            guard let pocket = terrain.indices.first(where: { component[$0] >= 0 && component[$0] != main }) else { break }
            let pocketId = component[pocket]
            var previous = [Int](repeating: -2, count: side * side)
            var queue = terrain.indices.filter { component[$0] == pocketId }, head = 0
            for index in queue { previous[index] = -1 }
            var reached: Int?
            search: while head < queue.count {
                let current = queue[head]; head += 1
                let cx = current % side, cy = current / side
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = cx + dx, ny = cy + dy
                    guard nx >= 0, ny >= 0, nx < side, ny < side else { continue }
                    let next = ny * side + nx
                    guard previous[next] == -2, terrain[next] != .water else { continue }
                    previous[next] = current
                    if component[next] == main { reached = next; break search }
                    if terrain[next] == .mountain { queue.append(next) }
                }
            }
            guard var index = reached else {
                for i in terrain.indices where component[i] == pocketId { terrain[i] = .mountain }
                continue
            }
            while index >= 0 { if terrain[index] == .mountain { terrain[index] = .grass; value[index] = 0 }; index = previous[index] }
        }
        let inner = distance(side: side) { terrain[$0] != .mountain }
        return terrain.indices.map { index in
            guard terrain[index] == .mountain else { return 0 }
            let raw = max(0, value[index] - ExploreRules.mountainThreshold) / 0.12 * Double(ExploreRules.mountainMaxHeight) * min(1, Double(inner[index]) / 3)
            return UInt8(max(2, min(ExploreRules.mountainMaxHeight, Int(raw / 2) * 2 + 2)))
        }
    }

    /// Расстояние (шагами по сторонам) до ближайшей клетки, где `isSource`.
    static func distance(side: Int, isSource: (Int) -> Bool) -> [Int] {
        var result = [Int](repeating: Int.max, count: side * side)
        var queue: [Int] = [], head = 0
        for index in 0..<(side * side) where isSource(index) { result[index] = 0; queue.append(index) }
        while head < queue.count {
            let current = queue[head]; head += 1
            let cx = current % side, cy = current / side
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, ny >= 0, nx < side, ny < side else { continue }
                let next = ny * side + nx
                if result[next] > result[current] + 1 { result[next] = result[current] + 1; queue.append(next) }
            }
        }
        return result.map { $0 == Int.max ? side : $0 }
    }

    /// Дороги (15A): сеть кратчайших связей всех городов острова плюс одна петля; путь — по суше, через горы — перевалом.
    /// Каждой дороге — ежедневная привычка месяца по кругу; износ — по её выполнению.
    static func roads(_ island: inout Island, input: ExploreInput) {
        let cities = island.cities
        guard cities.count >= 2 else { return }
        var edges: [(Int, Int)] = []
        var inTree: Set<Int> = [0]
        while inTree.count < cities.count {
            var best: (Int, Int, Double)?
            for a in inTree { for b in cities.indices where !inTree.contains(b) {
                let d = cities[a].center.distance(to: cities[b].center)
                if best == nil || d < best!.2 { best = (a, b, d) }
            } }
            guard let edge = best else { break }
            edges.append((edge.0, edge.1))
            inTree.insert(edge.1)
        }
        if cities.count >= 3 {
            let extra = cities.indices.flatMap { a in cities.indices.filter { $0 > a }.map { (a, $0) } }
                .filter { pair in !edges.contains { ($0.0 == pair.0 && $0.1 == pair.1) || ($0.0 == pair.1 && $0.1 == pair.0) } }
                .min { cities[$0.0].center.distance(to: cities[$0.1].center) < cities[$1.0].center.distance(to: cities[$1.1].center) }
            if let extra { edges.append(extra) }
        }
        let habits = input.habits.compactMap { habit -> (String, Int)? in
            habit.percent(from: input.first, through: input.last).map { (habit.title, $0) }
        }
        var onRoad = Set<Int>()
        for (k, edge) in edges.enumerated() {
            guard let tiles = roadPath(island, from: cities[edge.0].center, to: cities[edge.1].center, roads: onRoad) else { continue }
            for tile in tiles {
                let index = tile.y * island.side + tile.x
                onRoad.insert(index)
                // Перевал: дорога прорубает гору.
                if island.terrain[index] == .mountain { island.terrain[index] = .grass; island.elevation[index] = 0 }
            }
            let habit = habits.isEmpty ? nil : habits[k % habits.count]
            island.roads.append(IslandRoad(id: island.roads.count, from: cities[edge.0].id, to: cities[edge.1].id, habit: habit?.0,
                                           percent: habit?.1, wear: habit.map { RoadWear.of(percent: $0.1) } ?? .dirt, tiles: tiles))
        }
    }

    /// Путь дороги: Дейкстра по суше; горы дороги, готовая дорога дешевле.
    static func roadPath(_ island: Island, from: TilePoint, to: TilePoint, roads: Set<Int>) -> [TilePoint]? {
        let side = island.side
        var cost = [Int](repeating: Int.max, count: side * side)
        var previous = [Int](repeating: -1, count: side * side)
        let start = from.y * side + from.x, goal = to.y * side + to.x
        cost[start] = 0
        var heap = MinHeap()
        heap.push(0, start)
        while let (current, value) = heap.pop() {
            if current == goal { break }
            guard value == cost[current] else { continue }
            let cx = current % side, cy = current / side
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, ny >= 0, nx < side, ny < side else { continue }
                let next = ny * side + nx
                let step: Int
                if roads.contains(next) { step = 6 } else {
                    switch island.terrain[next] {
                    case .water: continue
                    case .grass: step = 10
                    case .forest: step = 14
                    case .sand: step = 18
                    case .mountain: step = 80
                    }
                }
                if cost[current] + step < cost[next] {
                    cost[next] = cost[current] + step
                    previous[next] = current
                    heap.push(cost[next], next)
                }
            }
        }
        guard previous[goal] != -1 || goal == start else { return nil }
        var result: [TilePoint] = []
        var index = goal
        while index != start { result.append(TilePoint(index % side, index / side)); index = previous[index] }
        result.append(from)
        return result.reversed()
    }

    /// Суша — «капля»: расстояние до центра плюс шум; остаётся самая большая связная часть.
    static func landMask(side: Int, random: inout ExploreRandom) -> [Terrain] {
        let noise = valueNoise(side: side, cell: max(6, side / 6), random: &random)
        var land = [Terrain](repeating: .water, count: side * side)
        let center = Double(side - 1) / 2
        for y in 0..<side { for x in 0..<side {
            let dx = (Double(x) - center) / center, dy = (Double(y) - center) / center
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance + (noise[y * side + x] - 0.5) * 0.45 < 0.78 { land[y * side + x] = .grass }
        } }
        // Самая большая связная суша.
        var component = [Int](repeating: -1, count: side * side)
        var best = (id: -1, count: 0), id = 0
        for start in 0..<(side * side) where land[start] != .water && component[start] == -1 {
            var stack = [start], count = 0
            component[start] = id
            while let current = stack.popLast() {
                count += 1
                let cx = current % side, cy = current / side
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = cx + dx, ny = cy + dy
                    guard nx >= 0, ny >= 0, nx < side, ny < side else { continue }
                    let next = ny * side + nx
                    if land[next] != .water, component[next] == -1 { component[next] = id; stack.append(next) }
                }
            }
            if count > best.count { best = (id, count) }
            id += 1
        }
        return land.indices.map { component[$0] == best.id ? land[$0] : .water }
    }

    /// Шум значений: случайная решётка с шагом `cell`, билинейная интерполяция.
    static func valueNoise(side: Int, cell: Int, random: inout ExploreRandom) -> [Double] {
        let grid = side / cell + 2
        let lattice = (0..<(grid * grid)).map { _ in random.unit() }
        return (0..<(side * side)).map { index in
            let x = Double(index % side) / Double(cell), y = Double(index / side) / Double(cell)
            let x0 = Int(x), y0 = Int(y), fx = x - Double(x0), fy = y - Double(y0)
            func at(_ i: Int, _ j: Int) -> Double { lattice[min(j, grid - 1) * grid + min(i, grid - 1)] }
            let top = at(x0, y0) * (1 - fx) + at(x0 + 1, y0) * fx
            let bottom = at(x0, y0 + 1) * (1 - fx) + at(x0 + 1, y0 + 1) * fx
            return top * (1 - fy) + bottom * fy
        }
    }

    static func nearestLand(to point: TilePoint, in island: Island) -> TilePoint {
        var best = point, bestDistance = Double.infinity
        for y in 0..<island.side { for x in 0..<island.side where island.isWalkable(TilePoint(x, y)) {
            let distance = TilePoint(x, y).distance(to: point)
            if distance < bestDistance { bestDistance = distance; best = TilePoint(x, y) }
        } }
        return best
    }
}

/// Двоичная куча по стоимости (для путей дорог).
struct MinHeap {
    private var items: [(Int, Int)] = []
    mutating func push(_ cost: Int, _ value: Int) {
        items.append((cost, value))
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard items[child].0 < items[parent].0 else { break }
            items.swapAt(child, parent)
            child = parent
        }
    }
    mutating func pop() -> (Int, Int)? {
        guard let first = items.first else { return nil }
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var parent = 0
            while true {
                let left = parent * 2 + 1, right = left + 1
                var smallest = parent
                if left < items.count, items[left].0 < items[smallest].0 { smallest = left }
                if right < items.count, items[right].0 < items[smallest].0 { smallest = right }
                if smallest == parent { break }
                items.swapAt(parent, smallest)
                parent = smallest
            }
        }
        return (first.1, first.0)
    }
}

// MARK: - Встреча (09, раздел 4)

public enum EncounterAction: Hashable, Sendable {
    case fight
    case ability(ExploreSkill)
    case flee
}

public enum EncounterOutcome: Hashable, Sendable { case won, persuaded, fled, lost }

/// Пошаговая встреча: ход героя, затем ход NPC.
public struct Encounter: Sendable {
    public let tier: NPCTier
    public let hero: ExploreHero
    public private(set) var heroHP: Double
    public private(set) var heroMP: Double
    public private(set) var npcHP: Double
    public private(set) var turn = 1
    public private(set) var outcome: EncounterOutcome?
    public private(set) var log: [String] = []
    /// Ходы до готовности способности.
    public private(set) var cooldowns: [ExploreAbility: Int] = [:]
    private var npcSkips = 0
    private var guardTurns = 0
    private var nextHitBonus = 1.0
    private var companionHit = false
    private var random: ExploreRandom
    /// Баффы монументов (15G.4): урон по герою и перезарядка — множители.
    public var damageTakenFactor = 1.0
    public var cooldownFactor = 1.0
    /// Страж Чёрной башни (14.5): своё HP и урон, вместо типа NPC.
    public let guardian: Guardian?

    public struct Guardian: Hashable, Sendable {
        public var title: String
        public var hp: Double
        public var damageShare: Double
        public init(title: String, hp: Double, damageShare: Double = ExploreRules.guardianDamageShare) {
            self.title = title; self.hp = hp; self.damageShare = damageShare
        }
    }

    public init(tier: NPCTier, hero: ExploreHero, heroHP: Double, heroMP: Double, seed: UInt64, guardian: Guardian? = nil) {
        self.tier = tier
        self.hero = hero
        self.heroHP = heroHP
        self.heroMP = heroMP
        self.guardian = guardian
        self.npcHP = guardian?.hp ?? tier.hp
        self.random = ExploreRandom(seed)
    }

    public var npcMaxHP: Double { guardian?.hp ?? tier.hp }
    /// Кто противник: «Страж башни» или тип NPC.
    public var opponentTitle: String { guardian == nil ? tier.title : "Страж башни" }

    /// Спутник бьёт один раз в начале встречи (14.5).
    public mutating func companionAssist(tier companion: NPCTier) {
        guard outcome == nil, turn == 1, !companionHit else { return }
        companionHit = true
        let damage = ExploreRules.companionStrike(companion).rounded()
        npcHP = max(0, npcHP - damage)
        log.append("Спутник ударил: −\(Int(damage))")
        if npcHP <= 0 { outcome = .won; log.append("\(opponentTitle) повержен") }
    }
    public var strikeRange: ClosedRange<Int> {
        let base = ExploreRules.strike(strength: hero.level(.strength))
        return Int((base * (1 - ExploreRules.hitSpread)).rounded())...Int((base * (1 + ExploreRules.hitSpread)).rounded())
    }
    public var escapeChance: Double { ExploreRules.escapeChance(mentality: hero.level(.mentality), tier: tier) }

    public func persuadeChance(power: Double) -> Double {
        let base = (0.30 + 0.05 * Double(hero.level(.charisma))) * power
        return min(0.85, max(0, base - 0.15 * Double(tier.rawValue - 1)))
    }

    public func cost(_ ability: ExploreAbility) -> Double { (ability.mpShare * hero.maxMP).rounded() }

    public func isReady(_ skill: ExploreSkill) -> Bool {
        (cooldowns[skill.ability] ?? 0) == 0 && heroMP >= cost(skill.ability) && outcome == nil
    }

    public mutating func perform(_ action: EncounterAction) {
        guard outcome == nil else { return }
        for key in cooldowns.keys { cooldowns[key] = max(0, (cooldowns[key] ?? 0) - 1) }
        switch action {
        case .fight:
            hit(factor: 1, label: "Вы ударили")
        case .flee:
            if random.unit() < escapeChance {
                outcome = .fled
                log.append("Вы убежали")
                return
            }
            log.append("Убежать не вышло")
        case .ability(let skill):
            guard isReady(skill) else { return }
            heroMP -= cost(skill.ability)
            cooldowns[skill.ability] = max(1, Int((Double(hero.cooldown) * cooldownFactor).rounded()))
            use(skill)
        }
        if npcHP <= 0 { outcome = .won; log.append("\(opponentTitle) повержен"); return }
        guard outcome == nil else { return }
        npcTurn()
        turn += 1
    }

    private mutating func hit(factor: Double, label: String) {
        let damage = (ExploreRules.strike(strength: hero.level(.strength)) * factor * nextHitBonus * random.spread(ExploreRules.hitSpread)).rounded()
        nextHitBonus = 1
        npcHP = max(0, npcHP - damage)
        log.append("\(label): −\(Int(damage))")
    }

    private mutating func use(_ skill: ExploreSkill) {
        let power = skill.power
        switch skill.ability {
        case .powerStrike: hit(factor: 1 + power, label: skill.ability.title)
        case .teamMove:
            hit(factor: 1 + 0.5 * power, label: skill.ability.title)
            npcSkips = max(npcSkips, 1)
        case .scout:
            nextHitBonus = 1 + 0.5 * power
            log.append("Разведка: следующий удар ×\(String(format: "%.2g", nextHitBonus))")
        case .focus:
            guardTurns = Int((2 * power).rounded(.down))
            log.append("Концентрация: \(guardTurns) хода урон вдвое меньше")
        case .distract:
            npcSkips = max(npcSkips, Int((2 * power).rounded(.down)))
            log.append("Отвлечь: NPC пропустит \(npcSkips) хода")
        case .dash:
            outcome = .fled
            log.append("Рывок — вы оторвались")
        case .persuade:
            if random.unit() < persuadeChance(power: power) {
                outcome = .persuaded
                log.append("\(tier.title) согласился разойтись миром")
            } else {
                log.append("Уговорить не вышло")
            }
        }
    }

    private mutating func npcTurn() {
        if npcSkips > 0 {
            npcSkips -= 1
            log.append("\(tier.title) пропускает ход")
            return
        }
        var damage = (guardian?.damageShare ?? tier.damageShare) * hero.maxHP * random.spread(ExploreRules.hitSpread)
        if guardTurns > 0 { damage *= 0.5; guardTurns -= 1 }
        damage = (damage * damageTakenFactor).rounded()
        heroHP = max(0, heroHP - damage)
        log.append("\(opponentTitle) ударил: −\(Int(damage)) HP")
        if heroHP <= 0 { outcome = .lost; log.append("Вы без сил — очнётесь в городе") }
    }
}
