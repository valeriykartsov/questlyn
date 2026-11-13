import Foundation

// Уведомления (этап 12D, 13.11.2026): что и когда напомнить. Чистая функция — расписание пересчитывается после
// каждого обновления данных, поэтому «если ещё не отмечено» проверяется на сегодня, а на будущие дни ставится заранее.

public struct NotificationSettings: Codable, Equatable, Sendable {
    public var quests = false
    /// За сколько минут до начала квеста: 0, 5, 15, 30.
    public var questLeadMinutes = 15
    /// Ежедневные квесты — в своё время, указанное в привычке.
    public var habitsOwnTime = false
    /// Общее напоминание о неотмеченных ежедневных.
    public var habitsReminder = false
    public var habitsReminderTime = LocalTime(hour: 20, minute: 0)!
    /// Внести сон — через 30 минут после подъёма, если ночи нет.
    public var sleep = false
    /// «Итог дня» вечером, если его ещё нет.
    public var mood = false
    public var moodTime = LocalTime(hour: 21, minute: 0)!

    public static let questLeadOptions = [0, 5, 15, 30]
    public static let sleepDelayMinutes = 30

    public init() {}

    public var isAnyOn: Bool { quests || habitsOwnTime || habitsReminder || sleep || mood }
}

public struct PlannedNotification: Hashable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var fireDate: Date

    public init(id: String, title: String, body: String, fireDate: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.fireDate = fireDate
    }
}

public enum NotificationPlanner {
    /// Сколько дней вперёд ставить и предел iOS на ожидающие уведомления (64, с запасом).
    public static let horizonDays = 7
    public static let limit = 60

    public struct QuestInput: Sendable {
        public var id: UUID
        public var title: String
        public var date: LocalDate
        public var time: LocalTime
        public var isDone: Bool
        public init(id: UUID, title: String, date: LocalDate, time: LocalTime, isDone: Bool) {
            self.id = id; self.title = title; self.date = date; self.time = time; self.isDone = isDone
        }
    }

    public struct HabitInput: Sendable {
        public var habit: HabitDefinition
        public var doneToday: Bool
        public init(habit: HabitDefinition, doneToday: Bool) { self.habit = habit; self.doneToday = doneToday }
    }

    public static func plan(settings: NotificationSettings, now: Date, timeZone: TimeZone, quests: [QuestInput], habits: [HabitInput],
                            wakeTime: LocalTime, sleepEnteredToday: Bool, daySummaryToday: Bool) -> [PlannedNotification] {
        let today = LocalDate(now, timeZone: timeZone)
        let days = (0..<horizonDays).map { today.adding(days: $0) }
        func at(_ day: LocalDate, _ time: LocalTime) -> Date { VitalsCalculator.date(day, time, timeZone: timeZone) }
        var result: [PlannedNotification] = []

        if settings.quests {
            for quest in quests where !quest.isDone {
                let start = at(quest.date, quest.time)
                let fire = start - Double(settings.questLeadMinutes) * 60
                guard fire > now, quest.date <= days[days.count - 1] else { continue }
                let body = settings.questLeadMinutes == 0 ? "Начало сейчас, \(quest.time)" : "Через \(settings.questLeadMinutes) мин, в \(quest.time)"
                result.append(.init(id: "quest-\(quest.id)", title: quest.title, body: body, fireDate: fire))
            }
        }
        let daily = habits.filter { $0.habit.kind == .daily && $0.habit.isActive }
        for day in days {
            let scheduled = daily.filter { $0.habit.isScheduled(on: day) && !(day == today && $0.doneToday) }
            if settings.habitsOwnTime {
                for item in scheduled {
                    guard let time = item.habit.time else { continue }
                    let fire = at(day, time)
                    guard fire > now else { continue }
                    result.append(.init(id: "habit-\(item.habit.id)-\(day)", title: item.habit.title, body: "Ежедневный квест · \(time)", fireDate: fire))
                }
            }
            if settings.habitsReminder, !scheduled.isEmpty {
                let fire = at(day, settings.habitsReminderTime)
                if fire > now {
                    let names = scheduled.prefix(3).map(\.habit.title).joined(separator: ", ") + (scheduled.count > 3 ? " и ещё \(scheduled.count - 3)" : "")
                    result.append(.init(id: "habits-\(day)", title: "Ежедневные ещё не отмечены", body: names, fireDate: fire))
                }
            }
            if settings.sleep, !(day == today && sleepEnteredToday) {
                let fire = at(day, wakeTime) + Double(NotificationSettings.sleepDelayMinutes) * 60
                if fire > now { result.append(.init(id: "sleep-\(day)", title: "Как спали?", body: "Внесите сон — он восстанавливает HP и MP.", fireDate: fire)) }
            }
            if settings.mood, !(day == today && daySummaryToday) {
                let fire = at(day, settings.moodTime)
                if fire > now { result.append(.init(id: "mood-\(day)", title: "Как прошёл день?", body: "Отметьте итог дня — он попадёт в «Дневник».", fireDate: fire)) }
            }
        }
        return Array(result.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }
}
