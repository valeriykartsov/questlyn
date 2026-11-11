import Foundation

// Этап 9: длительность квестов, лагеря монстров, призраки просроченных задач, ритм дня (02, 12.11.2026).

public enum QuestTiming {
    /// Допустимые длительности, минуты (макет 9.1).
    public static let durations = [15, 30, 60, 90, 120, 150, 180]
    /// Квест со временем, но без длительности, считается 30-минутным.
    public static let defaultDuration = 30

    /// Длительность на картах и в «Пути»: только у квеста с датой и временем.
    public static func effectiveDuration(_ quest: Quest) -> Int? {
        guard quest.dueDate != nil, quest.dueTime != nil else { return nil }
        return quest.durationMinutes ?? defaultDuration
    }

    /// Начало квеста — дата и время срока.
    public static func start(_ quest: Quest, timeZone: TimeZone) -> Date? {
        guard let date = quest.dueDate, let time = quest.dueTime else { return nil }
        return VitalsCalculator.date(date, time, timeZone: timeZone)
    }

    /// Момент просрочки: дата и время срока, без времени — конец дня срока.
    public static func dueMoment(_ quest: Quest, timeZone: TimeZone) -> Date? {
        guard let date = quest.dueDate else { return nil }
        if let time = quest.dueTime { return VitalsCalculator.date(date, time, timeZone: timeZone) }
        return VitalsCalculator.date(date.adding(days: 1), LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
    }

    /// Призрак: невыполненный квест, срок которого прошёл. Срок просрочки не важен; один квест — один призрак.
    public static func ghostSince(_ quest: Quest, isCompleted: Bool, now: Date, timeZone: TimeZone) -> Date? {
        guard !isCompleted, quest.deletedAt == nil, let moment = dueMoment(quest, timeZone: timeZone), moment <= now else { return nil }
        return moment
    }

    /// Монстров в лагере: 15–30 мин — 1, 1–1,5 ч — 2, от 2 ч — 3.
    public static func monsters(minutes: Int) -> Int { minutes <= 30 ? 1 : minutes <= 90 ? 2 : 3 }
}

/// Рабочее время — «Фарм» (9.3). Только отображение.
public struct WorkSchedule: Hashable, Codable, Sendable {
    public var isEnabled: Bool
    public var start: LocalTime
    public var end: LocalTime
    public var weekdays: Set<Weekday>

    public init(isEnabled: Bool = false, start: LocalTime = LocalTime(hour: 9, minute: 0)!, end: LocalTime = LocalTime(hour: 18, minute: 0)!,
                weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]) {
        self.isEnabled = isEnabled
        self.start = start
        self.end = end
        self.weekdays = weekdays
    }

    public static let `default` = WorkSchedule()

    /// Интервал «Фарма» в этот день, если он рабочий.
    public func interval(on day: LocalDate, timeZone: TimeZone) -> (start: Date, end: Date)? {
        guard isEnabled, weekdays.contains(day.weekday), start < end else { return nil }
        return (VitalsCalculator.date(day, start, timeZone: timeZone), VitalsCalculator.date(day, end, timeZone: timeZone))
    }
}

/// Вид движения героя: «Фарм» — рабочее время, «Привал» — окно сна, «Приключение» — остальное.
public enum MovementMode: String, Sendable, CaseIterable {
    case farm, rest, adventure

    public var title: String {
        switch self {
        case .farm: "Фарм"
        case .rest: "Привал"
        case .adventure: "Приключение"
        }
    }

    public static func at(_ moment: Date, sleepWindow: SleepWindow, work: WorkSchedule, timeZone: TimeZone) -> MovementMode {
        let day = LocalDate(moment, timeZone: timeZone)
        if let farm = work.interval(on: day, timeZone: timeZone), moment >= farm.start, moment < farm.end { return .farm }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: moment)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let start = sleepWindow.start.hour * 60 + sleepWindow.start.minute
        let end = sleepWindow.end.hour * 60 + sleepWindow.end.minute
        let inSleep = start > end ? (minute >= start || minute < end) : (minute >= start && minute < end)
        return inSleep ? .rest : .adventure
    }
}
