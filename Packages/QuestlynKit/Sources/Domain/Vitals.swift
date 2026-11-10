import Foundation

// HP и MP — состояние героя, а не прогресс (08). Это проекция из фактов: сон, шаги, выполненные квесты.
// Уточнения расчёта — 08, раздел 3.1.

/// Окно сна из «Здоровья героя». По умолчанию 23:00–07:00.
public struct SleepWindow: Hashable, Codable, Sendable {
    public var start: LocalTime
    public var end: LocalTime

    public init(start: LocalTime, end: LocalTime) {
        self.start = start
        self.end = end
    }

    public static let `default` = SleepWindow(start: LocalTime(hour: 23, minute: 0)!, end: LocalTime(hour: 7, minute: 0)!)
}

/// Настройки «Здоровья героя» (4.6).
public struct VitalSettings: Hashable, Codable, Sendable {
    public var sleepWindow: SleepWindow
    public var stepGoal: Int

    public init(sleepWindow: SleepWindow = .default, stepGoal: Int = VitalSettings.defaultStepGoal) {
        self.sleepWindow = sleepWindow
        self.stepGoal = stepGoal
    }

    public static let defaultStepGoal = 6000
    public static let stepGoalStep = 500
    public static let stepGoalRange = 500...30000
    public static let `default` = VitalSettings()
}

public enum SleepSource: String, Codable, Sendable { case manual, health }

/// Факт сна. Ночь относится к дню пробуждения.
public struct SleepSession: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var wakeDate: LocalDate
    public var durationMinutes: Int
    /// Отклонение отбоя от начала окна сна, минуты. Для ручного ввода — по выбранной кнопке.
    public var bedtimeDeviationMinutes: Int?
    public var startedAt: Date?
    public var endedAt: Date?
    public var source: SleepSource
    public var timezoneId: String
    public var createdAt: Date

    public init(id: UUID = UUID(), wakeDate: LocalDate, durationMinutes: Int, bedtimeDeviationMinutes: Int?,
                startedAt: Date? = nil, endedAt: Date? = nil, source: SleepSource, timezoneId: String, createdAt: Date) {
        self.id = id
        self.wakeDate = wakeDate
        self.durationMinutes = durationMinutes
        self.bedtimeDeviationMinutes = bedtimeDeviationMinutes
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.source = source
        self.timezoneId = timezoneId
        self.createdAt = createdAt
    }
}

/// Шаги за день (из HealthKit). Нет записи — нет данных, урона нет.
public struct StepDay: Hashable, Codable, Sendable {
    public var date: LocalDate
    public var steps: Int
    public var updatedAt: Date

    public init(date: LocalDate, steps: Int, updatedAt: Date) {
        self.date = date
        self.steps = steps
        self.updatedAt = updatedAt
    }
}

/// Кнопки длительности на экране «Как спали?» (макет 3.3, 02 от 11.11.2026).
public enum ManualSleepDuration: String, CaseIterable, Codable, Sendable {
    case under5, h5to6, h6to7, h7to8, h8to9, over9

    public var title: String {
        switch self {
        case .under5: "< 5 ч"
        case .h5to6: "5–6 ч"
        case .h6to7: "6–7 ч"
        case .h7to8: "7–8 ч"
        case .h8to9: "8–9 ч"
        case .over9: "> 9 ч"
        }
    }

    /// Представитель интервала: даёт по таблице D ровно согласованный коэффициент.
    public var minutes: Int {
        switch self {
        case .under5: 270
        case .h5to6: 330
        case .h6to7: 390
        case .h7to8: 450
        case .h8to9: 510
        case .over9: 570
        }
    }
}

/// Кнопки «Когда легли».
public enum ManualBedtime: String, CaseIterable, Codable, Sendable {
    case onTime, hourLate, muchLater

    public var title: String {
        switch self {
        case .onTime: "по режиму"
        case .hourLate: "на час позже"
        case .muchLater: "сильно позже"
        }
    }

    public var deviationMinutes: Int {
        switch self {
        case .onTime: 0
        case .hourLate: 60
        case .muchLater: 180
        }
    }
}

/// Качество ночи Q = D · R (08, раздел 2).
public enum SleepRules {
    public static let neutralQuality = 0.5
    public static let hpRestoreShare = 0.6

    /// D по длительности; на границе — лучший интервал.
    public static func durationFactor(minutes: Int) -> Double {
        switch minutes {
        case ..<240: 0.2
        case 240..<300: 0.4
        case 300..<360: 0.6
        case 360..<420: 0.8
        case 420...540: 1.0
        case 541...600: 0.9
        default: 0.8
        }
    }

    /// R по отклонению отбоя; нет данных об отбое — 1,0.
    public static func regimeFactor(deviationMinutes: Int?) -> Double {
        guard let deviation = deviationMinutes.map(abs) else { return 1.0 }
        switch deviation {
        case ...30: return 1.0
        case ...60: return 0.85
        case ...120: return 0.7
        default: return 0.5
        }
    }

    public static func quality(_ session: SleepSession) -> (d: Double, r: Double, q: Double) {
        let d = durationFactor(minutes: session.durationMinutes)
        let r = regimeFactor(deviationMinutes: session.bedtimeDeviationMinutes)
        return (d, r, d * r)
    }

    /// Отклонение начала сна от начала окна той же ночи, минуты (по модулю).
    public static func bedtimeDeviation(startedAt: Date, wakeDate: LocalDate, window: SleepWindow, timeZone: TimeZone) -> Int {
        // Окно через полночь (23:00–07:00) начинается накануне дня пробуждения.
        let startDay = window.start > window.end ? wakeDate.adding(days: -1) : wakeDate
        let windowStart = VitalsCalculator.date(startDay, window.start, timeZone: timeZone)
        return Int((abs(startedAt.timeIntervalSince(windowStart)) / 60).rounded())
    }
}

/// Стоимость квеста в MP (08, раздел 3): (4 + 2 · [навык]) · k, k = 0,5 / 1 / 1,5.
public enum ManaRules {
    public static func cost(priority: QuestPriority, hasSkill: Bool) -> Double {
        Double((4 + (hasSkill ? 2 : 0)) * priority.multiplierInHalves) / 2
    }
}

/// Потраченная мана: выполненный обычный квест (Daily и Weekly — отдельные сущности и MP не тратят).
public struct ManaSpend: Hashable, Sendable {
    public var at: Date
    public var cost: Double

    public init(at: Date, cost: Double) {
        self.at = at
        self.cost = cost
    }
}

/// Итог ночи для экрана «Утро».
public struct NightSummary: Hashable, Sendable {
    public var wakeDate: LocalDate
    public var session: SleepSession?
    public var durationFactor: Double?
    public var regimeFactor: Double?
    public var quality: Double
    public var hpBefore: Double
    public var hpAfter: Double
    public var mpBefore: Double
    public var mpAfter: Double
    public var maxHP: Double
    public var maxMP: Double

    /// Данных о сне нет — ночь нейтральная (Q = 0,5).
    public var isAssumed: Bool { session == nil }
}

/// Запись о здоровье для Летописи: ночь или сидячий день.
public struct VitalsLogEntry: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case night(NightSummary)
        case sedentary(date: LocalDate, steps: Int, goal: Int, damage: Double)
    }

    public var at: Date
    public var kind: Kind
}

public struct VitalsState: Hashable, Sendable {
    public var hp: Double
    public var maxHP: Double
    public var mp: Double
    public var maxMP: Double
    /// Последняя посчитанная ночь (сегодняшнее пробуждение), если она уже наступила.
    public var lastNight: NightSummary?
    /// Ночи и сидячие дни по порядку — для Летописи.
    public var log: [VitalsLogEntry] = []

    public init(hp: Double, maxHP: Double, mp: Double, maxMP: Double, lastNight: NightSummary? = nil, log: [VitalsLogEntry] = []) {
        self.hp = hp
        self.maxHP = maxHP
        self.mp = mp
        self.maxMP = maxMP
        self.lastNight = lastNight
        self.log = log
    }

    public static let woundedShare = 0.3

    /// «Ранен» — HP ниже 30% максимума (02, 11.11.2026).
    public var isWounded: Bool { hp < maxHP * Self.woundedShare }
    /// «Истощён» — MP = 0.
    public var isExhausted: Bool { mp <= 0.000_1 }
}

public enum VitalsCalculator {
    public static let baseMax = 100.0
    public static let perLevel = 5.0
    public static let sedentaryDamageShare = 0.05

    public static func maxHP(levels: [Attribute: Int]) -> Double {
        baseMax + perLevel * Double((levels[.strength] ?? 0) + (levels[.endurance] ?? 0))
    }

    public static func maxMP(levels: [Attribute: Int]) -> Double {
        baseMax + perLevel * Double((levels[.intelligence] ?? 0) + (levels[.mentality] ?? 0) + (levels[.charisma] ?? 0))
    }

    private enum Event {
        case night(wakeDate: LocalDate, session: SleepSession?)
        case spend(Double)
        case sedentary(LocalDate)
    }

    /// Проекция HP и MP на момент `now`. Старт — полные HP и MP в момент создания героя.
    public static func state(
        heroCreatedAt: Date, grants: [ProgressGrant], spends: [ManaSpend], sleeps: [SleepSession],
        steps: [StepDay], settings: VitalSettings, now: Date, timeZone: TimeZone
    ) -> VitalsState {
        let firstDay = LocalDate(heroCreatedAt, timeZone: timeZone)
        let today = LocalDate(now, timeZone: timeZone)
        var levelCache: [LocalDate: [Attribute: Int]] = [:]
        func levels(on date: LocalDate) -> [Attribute: Int] {
            if let cached = levelCache[date] { return cached }
            let upToDate = grants.filter { $0.effectiveDate <= date }
            var result: [Attribute: Int] = [:]
            for attribute in [Attribute.strength, .endurance, .intelligence, .mentality, .charisma] {
                let state = ProgressTimeline.attributeState(attribute, grants: upToDate, today: date)
                result[attribute] = LevelCurve.level(for: state.xp)
            }
            levelCache[date] = result
            return result
        }

        // Самая длинная запись сна за ночь.
        var nights: [LocalDate: SleepSession] = [:]
        for session in sleeps where nights[session.wakeDate].map({ session.durationMinutes > $0.durationMinutes }) ?? true {
            nights[session.wakeDate] = session
        }
        let stepsByDay = Dictionary(steps.map { ($0.date, $0.steps) }, uniquingKeysWith: { _, latest in latest })

        var events: [(at: Date, event: Event)] = spends.filter { $0.at >= heroCreatedAt && $0.at <= now }.map { ($0.at, .spend($0.cost)) }
        if firstDay <= today {
            var day = firstDay
            while day <= today {
                let session = nights[day]
                let wake = session?.endedAt ?? date(day, settings.sleepWindow.end, timeZone: timeZone)
                if wake >= heroCreatedAt, wake <= now { events.append((wake, .night(wakeDate: day, session: session))) }
                let dayEnd = date(day, LocalTime(hour: 23, minute: 59)!, timeZone: timeZone)
                if let count = stepsByDay[day], count < settings.stepGoal, dayEnd <= now, dayEnd >= heroCreatedAt {
                    events.append((dayEnd, .sedentary(day)))
                }
                day = day.adding(days: 1)
            }
        }
        events.sort { $0.at < $1.at }

        let startLevels = levels(on: firstDay)
        var hp = maxHP(levels: startLevels), mp = maxMP(levels: startLevels)
        var lastNight: NightSummary?
        var log: [VitalsLogEntry] = []
        for (at, event) in events {
            let current = levels(on: LocalDate(at, timeZone: timeZone))
            let topHP = maxHP(levels: current), topMP = maxMP(levels: current)
            hp = min(hp, topHP)
            mp = min(mp, topMP)
            switch event {
            case let .spend(cost):
                mp = max(0, mp - cost)
            case let .sedentary(day):
                let damage = min(hp, topHP * sedentaryDamageShare)
                hp -= damage
                log.append(VitalsLogEntry(at: at, kind: .sedentary(date: day, steps: stepsByDay[day] ?? 0, goal: settings.stepGoal, damage: damage)))
            case let .night(wakeDate, session):
                let factors = session.map(SleepRules.quality)
                let q = factors?.q ?? SleepRules.neutralQuality
                let summary = NightSummary(
                    wakeDate: wakeDate, session: session, durationFactor: factors?.d, regimeFactor: factors?.r, quality: q,
                    hpBefore: hp, hpAfter: min(topHP, hp + SleepRules.hpRestoreShare * topHP * q),
                    mpBefore: mp, mpAfter: min(topMP, mp + topMP * q), maxHP: topHP, maxMP: topMP
                )
                hp = summary.hpAfter
                mp = summary.mpAfter
                log.append(VitalsLogEntry(at: at, kind: .night(summary)))
                if wakeDate == today { lastNight = summary }
            }
        }
        let todayLevels = levels(on: today)
        let topHP = maxHP(levels: todayLevels), topMP = maxMP(levels: todayLevels)
        return VitalsState(hp: min(hp, topHP), maxHP: topHP, mp: min(mp, topMP), maxMP: topMP, lastNight: lastNight, log: log)
    }

    /// Момент «дата + локальное время» в часовом поясе пользователя.
    public static func date(_ day: LocalDate, _ time: LocalTime, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute))!
    }
}
