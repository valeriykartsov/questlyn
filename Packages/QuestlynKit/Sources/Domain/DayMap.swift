import Foundation

// Карта дня (02 «Карта дня», холст 8.8 и 8.9): только визуализация, наград за события нет.

/// Событие календаря для карты — не хранится, приходит из EventKit.
public struct MapEvent: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var attendees: Int

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, attendees: Int) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.attendees = attendees
    }
}

/// Квест с датой этого дня: с точным временем — маркер на дороге, без времени — в списке под картой.
public struct MapQuest: Hashable, Sendable {
    public var title: String
    public var start: Date?
    public var isDone: Bool

    public init(title: String, start: Date?, isDone: Bool) {
        self.title = title
        self.start = start
        self.isDone = isDone
    }
}

public enum Season: String, Sendable {
    case winter, spring, summer, autumn

    /// Декабрь–февраль — зима, март–май — весна, июнь–август — лето, сентябрь–ноябрь — осень.
    public static func of(_ date: LocalDate) -> Season {
        switch date.month {
        case 12, 1, 2: .winter
        case 3...5: .spring
        case 6...8: .summer
        default: .autumn
        }
    }

    public var title: String {
        switch self {
        case .winter: "Зима"
        case .spring: "Весна"
        case .summer: "Лето"
        case .autumn: "Осень"
        }
    }
}

/// Освещение по времени суток (холст 8.8): утро до 10:00, день до 17:00, вечер до 22:00, ночь до 06:00.
public enum DayLight: String, Sendable {
    case night, morning, day, evening

    public static func at(hour: Double) -> DayLight {
        switch hour {
        case ..<6: .night
        case ..<10: .morning
        case ..<17: .day
        case ..<22: .evening
        default: .night
        }
    }
}

/// Поселение: одно событие ≤ 30 мин — деревня; длиннее или несколько пересекающихся — город.
public struct Settlement: Hashable, Sendable {
    public enum Kind: String, Sendable { case village, city }

    public var startHour: Double
    public var endHour: Double
    public var titles: [String]
    public var kind: Kind
    /// Плотность — сколько событий пересеклось.
    public var density: Int
    public var attendees: Int
}

public struct DayMap: Hashable, Sendable {
    public struct Marker: Hashable, Sendable {
        public var hour: Double
        public var title: String
        public var isDone: Bool
    }

    public struct MoodFlag: Hashable, Sendable {
        public var hour: Double
        public var mood: Mood
    }

    public var date: LocalDate
    public var settlements: [Settlement]
    public var questMarkers: [Marker]
    public var moodFlags: [MoodFlag]
    /// Весь день, многодневные события и квесты без времени — только списком.
    public var offMap: [String]
    public var weather: Weather
    public var season: Season
    /// Герой — только в сегодняшнем дне.
    public var heroHour: Double?

    public var light: DayLight { heroHour.map(DayLight.at(hour:)) ?? .day }
}

public enum DayMapBuilder {
    public static let villageMaxMinutes = 30.0

    public static func build(date: LocalDate, events: [MapEvent], quests: [MapQuest], moods: [MoodEntry],
                             now: Date?, timeZone: TimeZone) -> DayMap {
        let dayStart = VitalsCalculator.date(date, LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
        let dayEnd = VitalsCalculator.date(date.adding(days: 1), LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
        func hour(_ moment: Date) -> Double { min(24, max(0, moment.timeIntervalSince(dayStart) / 3600)) }

        var offMap: [String] = []
        var timed: [MapEvent] = []
        for event in events where event.end > dayStart && event.start < dayEnd {
            // Весь день и события, которые накрывают сутки целиком, — вне карты.
            if event.isAllDay || (event.start <= dayStart && event.end >= dayEnd) {
                offMap.append(event.isAllDay ? "Весь день: \(event.title)" : "Несколько дней: \(event.title)")
            } else {
                timed.append(event)
            }
        }
        timed.sort { ($0.start, $0.end) < ($1.start, $1.end) }

        // Пересекающиеся события — одно поселение (плотность растёт только от пересечений).
        var settlements: [Settlement] = []
        var clusterEnd: Date?
        var cluster: [MapEvent] = []
        func flush() {
            guard let first = cluster.first, let end = clusterEnd else { return }
            let minutes = end.timeIntervalSince(first.start) / 60
            let kind: Settlement.Kind = cluster.count == 1 && minutes <= villageMaxMinutes ? .village : .city
            settlements.append(Settlement(startHour: hour(first.start), endHour: hour(end), titles: cluster.map(\.title), kind: kind,
                                          density: cluster.count, attendees: cluster.reduce(0) { $0 + $1.attendees }))
            cluster = []
        }
        for event in timed {
            if let end = clusterEnd, event.start < end {
                cluster.append(event)
                clusterEnd = max(end, event.end)
            } else {
                flush()
                cluster = [event]
                clusterEnd = event.end
            }
        }
        flush()

        var markers: [DayMap.Marker] = []
        for quest in quests {
            if let start = quest.start, start >= dayStart, start < dayEnd {
                markers.append(.init(hour: hour(start), title: quest.title, isDone: quest.isDone))
            } else if quest.start == nil {
                offMap.append("Квест: \(quest.title)")
            }
        }
        let dayMoods = moods.filter { $0.deletedAt == nil && $0.localDate == date }.sorted { $0.at < $1.at }
        let heroHour = now.flatMap { LocalDate($0, timeZone: timeZone) == date ? hour($0) : nil }
        return DayMap(date: date, settlements: settlements, questMarkers: markers.sorted { $0.hour < $1.hour },
                      moodFlags: dayMoods.map { .init(hour: hour($0.at), mood: $0.mood) }, offMap: offMap,
                      weather: Weather.from(dayMoods.last?.mood, on: date), season: Season.of(date), heroHour: heroHour)
    }
}

// MARK: - Неделя на карте (02 от 11.11.2026)

/// Привал — сон на дороге: интервал и длительность. Ночь без данных — окно сна с пометкой.
public struct SleepCamp: Hashable, Sendable {
    public var wakeDate: LocalDate
    public var start: Date
    public var end: Date
    public var minutes: Int
    /// nil — данных о сне нет, привал стоит в окне сна.
    public var source: SleepSource?

    public init(wakeDate: LocalDate, start: Date, end: Date, minutes: Int, source: SleepSource?) {
        self.wakeDate = wakeDate
        self.start = start
        self.end = end
        self.minutes = minutes
        self.source = source
    }
}

public enum SleepCampBuilder {
    /// Привалы из ночей проекции HP и MP. Ручной ввод знает только длительность — он заканчивается в конце окна сна.
    public static func camps(from log: [VitalsLogEntry], window: SleepWindow, timeZone: TimeZone) -> [SleepCamp] {
        log.compactMap { entry -> SleepCamp? in
            guard case let .night(night) = entry.kind else { return nil }
            let windowEnd = VitalsCalculator.date(night.wakeDate, window.end, timeZone: timeZone)
            if let session = night.session {
                if let start = session.startedAt, let end = session.endedAt {
                    return SleepCamp(wakeDate: night.wakeDate, start: start, end: end, minutes: session.durationMinutes, source: session.source)
                }
                return SleepCamp(wakeDate: night.wakeDate, start: windowEnd - Double(session.durationMinutes) * 60, end: windowEnd,
                                 minutes: session.durationMinutes, source: session.source)
            }
            let startDay = window.start > window.end ? night.wakeDate.adding(days: -1) : night.wakeDate
            let start = VitalsCalculator.date(startDay, window.start, timeZone: timeZone)
            return SleepCamp(wakeDate: night.wakeDate, start: start, end: windowEnd,
                             minutes: Int((windowEnd.timeIntervalSince(start) / 60).rounded()), source: nil)
        }
    }
}

/// Неделя на карте: семь дней с понедельника и привалы сна.
public struct WeekMap: Hashable, Sendable {
    public var start: LocalDate
    public var days: [DayMap]
    public var camps: [SleepCamp]
    /// Час недели героя (0…168), если «сейчас» внутри недели.
    public var heroHour: Double?

    public static let hours = 168.0

    public init(start: LocalDate, days: [DayMap], camps: [SleepCamp], heroHour: Double?) {
        self.start = start
        self.days = days
        self.camps = camps
        self.heroHour = heroHour
    }

    /// Час недели для момента (может выйти за 0…168).
    public static func hour(of moment: Date, weekStart: LocalDate, timeZone: TimeZone) -> Double {
        moment.timeIntervalSince(VitalsCalculator.date(weekStart, LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)) / 3600
    }

    public static func build(weekStart: LocalDate, days: [DayMap], camps: [SleepCamp], now: Date, timeZone: TimeZone) -> WeekMap {
        let end = weekStart.adding(days: 7)
        let inWeek = camps.filter { $0.end > VitalsCalculator.date(weekStart, LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
            && $0.start < VitalsCalculator.date(end, LocalTime(hour: 0, minute: 0)!, timeZone: timeZone) }
        let now = hour(of: now, weekStart: weekStart, timeZone: timeZone)
        return WeekMap(start: weekStart, days: days, camps: inWeek, heroHour: (0..<hours).contains(now) ? now : nil)
    }
}
