import Foundation
import Domain

enum Format {
    private static let ru = Locale(identifier: "ru_RU")

    /// XP с запятой и без лишних нулей: 5, 3,75, 5,63.
    static func xp(_ value: CentiXP) -> String {
        value.xp.formatted(.number.precision(.fractionLength(0...2)).locale(ru))
    }

    static func signedXP(_ value: CentiXP) -> String {
        (value.value >= 0 ? "+" : "−") + xp(CentiXP(abs(value.value)))
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(ru))
    }

    /// «Вторник, 10 ноября».
    static func longDay(_ date: Date) -> String {
        let text = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(ru))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// «Чт, 12 ноя».
    static func shortDay(_ date: LocalDate) -> String {
        guard let value = date.date else { return date.description }
        return value.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(ru))
    }

    /// «Сегодня, 18:00», «Вчера», «Чт, 12 ноя · без времени».
    static func when(_ quest: Quest, today: LocalDate?) -> String {
        guard let due = quest.dueDate else { return "Без даты" }
        var day: String
        if due == today { day = "Сегодня" }
        else if let today, due == today.adding(days: -1) { day = "Вчера" }
        else if let today, due == today.adding(days: 1) { day = "Завтра" }
        else { day = shortDay(due) }
        if let time = quest.dueTime { day += ", \(time)" }
        return day
    }

    /// «9–15 ноября».
    static func week(_ start: LocalDate) -> String {
        let end = start.adding(days: 6)
        guard let endDate = end.date else { return start.description }
        let month = endDate.formatted(.dateTime.day().month(.wide).locale(ru))
        return "\(start.day)–\(month)"
    }

    static func weekdays(_ days: Set<Weekday>) -> String {
        if days == Weekday.everyDay { return "Каждый день" }
        if days == Weekday.workdays { return "Будни" }
        return days.sorted().map(\.shortTitle).joined(separator: ", ")
    }

    static func times(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        let word = (mod10 >= 2 && mod10 <= 4 && !(12...14).contains(mod100)) ? "раза" : "раз"
        return "\(n) \(word)"
    }

    static func priority(_ priority: QuestPriority) -> String {
        switch priority {
        case .low: "Низкий"
        case .medium: "Средний"
        case .high: "Высокий"
        }
    }

    static func multiplier(_ priority: QuestPriority) -> String {
        switch priority {
        case .low: "×0,5"
        case .medium: "×1"
        case .high: "×1,5"
        }
    }
}

extension LocalDate {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// Полдень этой даты в текущем часовом поясе — для форматирования и DatePicker.
    var date: Date? {
        LocalDate.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

}
