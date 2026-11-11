import Foundation

public enum HabitKind: String, Codable, Sendable, CaseIterable {
    /// Ежедневный квест: по выбранным дням недели.
    case daily
    /// Недельный квест: N раз за неделю, дни любые.
    case weekly
}

/// Daily / Weekly Quest (02). Приоритета нет, награда фиксирована (D1).
public struct HabitDefinition: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var kind: HabitKind
    public var title: String
    public var details: String?
    public var skillId: UUID?
    /// Для daily — дни недели; для weekly не используется.
    public var weekdays: Set<Weekday>
    /// Для weekly — цель «раз в неделю»; для daily не используется.
    public var targetPerWeek: Int
    /// Необязательное время (только для списка).
    public var time: LocalTime?
    public var timezoneId: String
    /// Локальная дата создания: с неё привычка входит в расписание.
    public var startDate: LocalDate
    public var isActive: Bool
    public var createdAt: Date
    /// День удаления: с недели удаления привычка не входит в DIS, прошлые недели не меняются.
    public var archivedOn: LocalDate?

    public init(
        id: UUID = UUID(), kind: HabitKind, title: String, details: String? = nil, skillId: UUID? = nil,
        weekdays: Set<Weekday> = Weekday.everyDay, targetPerWeek: Int = 1, time: LocalTime? = nil,
        timezoneId: String, startDate: LocalDate, isActive: Bool = true, createdAt: Date, archivedOn: LocalDate? = nil
    ) {
        self.archivedOn = archivedOn
        self.id = id
        self.kind = kind
        self.title = title
        self.details = details
        self.skillId = skillId
        self.weekdays = weekdays
        self.targetPerWeek = targetPerWeek
        self.time = time
        self.timezoneId = timezoneId
        self.startDate = startDate
        self.isActive = isActive
        self.createdAt = createdAt
    }

    /// Запланирован ли ежедневный квест на этот день.
    public func isScheduled(on date: LocalDate) -> Bool {
        kind == .daily && counts(inWeekOf: date) && date >= startDate && weekdays.contains(date.weekday)
    }

    /// Входит ли недельный квест в DIS этой недели: с первой полной недели после создания.
    public func countsForWeek(starting weekStart: LocalDate) -> Bool {
        kind == .weekly && counts(inWeekOf: weekStart) && startDate <= weekStart
    }

    /// Активна или удалена позже этой недели.
    private func counts(inWeekOf date: LocalDate) -> Bool {
        guard let archivedOn else { return isActive }
        return date.weekStart < archivedOn.weekStart
    }
}

/// Факт: отметка привычки (Occurrence). `id` — `sourceId` начислений.
public struct HabitOccurrence: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var habitId: UUID
    public var localDate: LocalDate
    public var completedAt: Date
    public var timezoneId: String
    public var undoneAt: Date?
    public var classSnapshot: ClassSnapshot

    public init(id: UUID = UUID(), habitId: UUID, localDate: LocalDate, completedAt: Date,
                timezoneId: String, undoneAt: Date? = nil, classSnapshot: ClassSnapshot) {
        self.id = id
        self.habitId = habitId
        self.localDate = localDate
        self.completedAt = completedAt
        self.timezoneId = timezoneId
        self.undoneAt = undoneAt
        self.classSnapshot = classSnapshot
    }

    public var isActive: Bool { undoneAt == nil }
}

/// Правило отметки задним числом (02): сегодня и вчера.
public enum HabitMarkingRules {
    public static func canMark(_ date: LocalDate, today: LocalDate) -> Bool {
        date == today || date == today.adding(days: -1)
    }

    /// Отметку недельного квеста можно снять за любой день текущей недели (02, 11.11.2026); закрытые недели не меняются.
    public static func canUnmarkWeekly(_ date: LocalDate, today: LocalDate) -> Bool {
        date >= today.weekStart && date <= today
    }
}

/// Epic Quest: большая цель из шагов. XP не даёт, только веха (02, 07).
public struct EpicQuest: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var details: String?
    public var deadline: LocalDate?
    public var completedAt: Date?
    public var createdAt: Date
    /// Удалён пользователем: пропадает из журнала, начисления за выполненные шаги остаются.
    public var deletedAt: Date?
    /// Необязательная профессия: только акцент и порядок в журнале (02, 11.11.2026), на награды не влияет.
    public var professionId: UUID?

    public init(id: UUID = UUID(), title: String, details: String? = nil, deadline: LocalDate? = nil,
                completedAt: Date? = nil, createdAt: Date, deletedAt: Date? = nil, professionId: UUID? = nil) {
        self.professionId = professionId
        self.deletedAt = deletedAt
        self.id = id
        self.title = title
        self.details = details
        self.deadline = deadline
        self.completedAt = completedAt
        self.createdAt = createdAt
    }

    public var isCompleted: Bool { completedAt != nil }
}
