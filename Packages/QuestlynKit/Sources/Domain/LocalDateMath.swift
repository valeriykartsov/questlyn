import Foundation

/// Арифметика локальных дат без часовых поясов: считаем в UTC от полудня.
extension LocalDate {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private var utcNoon: Date {
        LocalDate.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(LocalDate.utc.date(byAdding: .day, value: days, to: utcNoon)!, timeZone: LocalDate.utc.timeZone)
    }

    /// День недели: понедельник — первый (07: неделя с понедельника).
    public var weekday: Weekday {
        let gregorian = LocalDate.utc.component(.weekday, from: utcNoon) // 1 = вс
        return Weekday(rawValue: (gregorian + 5) % 7 + 1)!
    }

    /// Понедельник недели этой даты.
    public var weekStart: LocalDate { adding(days: -(weekday.rawValue - 1)) }

    /// 7 дней недели, начиная с понедельника.
    public var weekDays: [LocalDate] { (0..<7).map { weekStart.adding(days: $0) } }

    public func days(until other: LocalDate) -> Int {
        LocalDate.utc.dateComponents([.day], from: utcNoon, to: other.utcNoon).day!
    }
}

/// День недели, 1 — понедельник … 7 — воскресенье.
public enum Weekday: Int, CaseIterable, Codable, Sendable, Comparable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    public var shortTitle: String {
        ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"][rawValue - 1]
    }

    public static let workdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    public static let everyDay = Set(Weekday.allCases)
}
