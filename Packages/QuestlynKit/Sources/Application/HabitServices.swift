import Foundation
import Domain

private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

/// Черновик Daily / Weekly из форм DailyNew и WeeklyNew.
public struct HabitDraft: Sendable, Equatable {
    public var kind: HabitKind
    public var title: String
    public var details: String
    public var skillId: UUID?
    public var weekdays: Set<Weekday>
    public var targetPerWeek: Int
    public var time: LocalTime?

    public init(kind: HabitKind, title: String = "", details: String = "", skillId: UUID? = nil,
                weekdays: Set<Weekday> = Weekday.everyDay, targetPerWeek: Int = 3, time: LocalTime? = nil) {
        self.kind = kind
        self.title = title
        self.details = details
        self.skillId = skillId
        self.weekdays = weekdays
        self.targetPerWeek = targetPerWeek
        self.time = time
    }
}

/// Создание и изменение привычек (BACKLOG 2.4, 2.5).
public struct HabitService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    @discardableResult
    public func create(_ draft: HabitDraft, now: Date, timeZone: TimeZone) async throws -> HabitDefinition {
        try await validate(draft)
        let habit = HabitDefinition(
            kind: draft.kind, title: trimmed(draft.title), details: nonEmpty(draft.details), skillId: draft.skillId,
            weekdays: draft.kind == .daily ? draft.weekdays : Weekday.everyDay,
            targetPerWeek: draft.kind == .weekly ? draft.targetPerWeek : 1, time: draft.time,
            timezoneId: timeZone.identifier, startDate: LocalDate(now, timeZone: timeZone), createdAt: now
        )
        try await store.save(habit)
        return habit
    }

    /// Изменение не трогает дату начала и уже посчитанные недели DIS.
    @discardableResult
    public func update(habitId: UUID, with draft: HabitDraft) async throws -> HabitDefinition {
        guard var habit = try await store.habit(id: habitId) else { throw QuestlynError.habitNotFound }
        var draft = draft
        draft.kind = habit.kind
        try await validate(draft)
        habit.title = trimmed(draft.title)
        habit.details = nonEmpty(draft.details)
        habit.skillId = draft.skillId
        if habit.kind == .daily { habit.weekdays = draft.weekdays } else { habit.targetPerWeek = draft.targetPerWeek }
        habit.time = draft.time
        try await store.save(habit)
        return habit
    }

    /// Удаление (4): привычка уходит из списков, с текущей недели не входит в DIS; отметки и начисления остаются в Летописи.
    public func archive(habitId: UUID, now: Date, timeZone: TimeZone) async throws {
        guard var habit = try await store.habit(id: habitId) else { throw QuestlynError.habitNotFound }
        habit.isActive = false
        habit.archivedOn = LocalDate(now, timeZone: timeZone)
        try await store.save(habit)
    }

    private func validate(_ draft: HabitDraft) async throws {
        guard !trimmed(draft.title).isEmpty else { throw QuestlynError.emptyName }
        if draft.kind == .daily, draft.weekdays.isEmpty { throw QuestlynError.noWeekdays }
        if draft.kind == .weekly, !(1...14).contains(draft.targetPerWeek) { throw QuestlynError.invalidTarget }
        if let skillId = draft.skillId, try await !store.skills().contains(where: { $0.id == skillId }) {
            throw QuestlynError.skillNotFound
        }
    }

    private func nonEmpty(_ text: String) -> String? {
        let value = trimmed(text)
        return value.isEmpty ? nil : value
    }
}

/// Отметка и отмена привычки (BACKLOG 2.4, 2.5).
public struct HabitMarkService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    @discardableResult
    public func mark(habitId: UUID, on date: LocalDate, now: Date, timeZone: TimeZone) async throws -> [ProgressGrant] {
        guard let habit = try await store.habit(id: habitId) else { throw QuestlynError.habitNotFound }
        let today = LocalDate(now, timeZone: timeZone)
        guard HabitMarkingRules.canMark(date, today: today, kind: habit.kind), date >= habit.startDate else { throw QuestlynError.cannotMarkDate }
        if habit.kind == .daily {
            guard habit.isScheduled(on: date) else { throw QuestlynError.notScheduled }
            guard try await store.occurrences(from: date, through: date).allSatisfy({ $0.habitId != habitId }) else {
                throw QuestlynError.alreadyMarked
            }
        }
        guard let hero = try await store.currentHero() else { throw QuestlynError.heroNotFound }
        let professions = try await store.professions(heroId: hero.id)
        let skill = try await store.skills().first { $0.id == habit.skillId && habit.skillId != nil }
        let profession = professions.first { $0.id == skill?.professionId }
        let snapshot = profession.map { ClassRules.snapshot(skillProfession: $0, activeProfessions: professions) } ?? .empty

        let occurrence = HabitOccurrence(habitId: habitId, localDate: date, completedAt: now,
                                         timezoneId: timeZone.identifier, classSnapshot: snapshot)
        let grants = GrantCalculator.habitOccurrenceGrants(occurrenceId: occurrence.id, skill: skill,
                                                           skillProfessionTitle: profession?.title, snapshot: snapshot,
                                                           createdAt: now, effectiveDate: date)
        try await store.record(occurrence, grants: grants)
        try await DisciplineService(store: store).settle(now: now, timeZone: timeZone)
        return grants
    }

    /// Снять конкретную отметку недельного квеста за любой день текущей недели (8.5). XP за неё отменяется.
    public func unmarkWeekly(occurrenceId: UUID, now: Date, timeZone: TimeZone) async throws {
        let today = LocalDate(now, timeZone: timeZone)
        guard let occurrence = try await store.allOccurrences().first(where: { $0.id == occurrenceId && $0.isActive }),
              let habit = try await store.habit(id: occurrence.habitId) else { throw QuestlynError.notCompleted }
        guard habit.kind == .weekly, HabitMarkingRules.canUnmarkWeekly(occurrence.localDate, today: today) else {
            throw QuestlynError.cannotMarkDate
        }
        try await store.undoOccurrence(id: occurrence.id, at: now)
        try await DisciplineService(store: store).settle(now: now, timeZone: timeZone)
    }

    /// Снять последнюю отметку за день.
    public func unmark(habitId: UUID, on date: LocalDate, now: Date, timeZone: TimeZone) async throws {
        let today = LocalDate(now, timeZone: timeZone)
        guard HabitMarkingRules.canMark(date, today: today) else { throw QuestlynError.cannotMarkDate }
        guard let occurrence = try await store.occurrences(from: date, through: date).last(where: { $0.habitId == habitId }) else {
            throw QuestlynError.notCompleted
        }
        try await store.undoOccurrence(id: occurrence.id, at: now)
        try await DisciplineService(store: store).settle(now: now, timeZone: timeZone)
    }
}

/// Недельный пересчёт DIS по понедельникам (BACKLOG 2.6, 07 раздел 5).
public struct DisciplineService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    /// Считает закрытые недели, за которые ещё нет начисления, и пересчитывает последнюю закрытую неделю
    /// (её можно изменить отметкой за вчера в понедельник). Более ранние недели не меняются.
    public func settle(now: Date, timeZone: TimeZone) async throws {
        guard let hero = try await store.currentHero() else { return }
        let today = LocalDate(now, timeZone: timeZone)
        let lastClosed = today.weekStart.adding(days: -7)
        let first = DisciplineCalculator.firstCountedWeek(heroCreatedOn: LocalDate(hero.createdAt, timeZone: timeZone))
        guard first <= lastClosed else { return }

        let habits = try await store.habits()
        let occurrences = try await store.occurrences(from: first, through: lastClosed.adding(days: 6))
        let existing = Dictionary(try await store.disciplineGrants().map { ($0.sourceId, $0) }, uniquingKeysWith: { a, _ in a })

        var running = CentiXP.zero
        var week = first
        while week <= lastClosed {
            let sourceId = DisciplineCalculator.sourceId(weekStart: week)
            if let stored = existing[sourceId], week != lastClosed {
                running += stored.amount
            } else {
                let input = Self.input(week: week, habits: habits, occurrences: occurrences)
                let result = DisciplineCalculator.evaluate(input)
                let amount = DisciplineCalculator.grantAmount(delta: result.delta, currentDIS: running)
                if existing[sourceId]?.amount != amount || existing[sourceId] == nil {
                    let grant = ProgressGrant(
                        sourceType: .weeklyDiscipline, sourceId: sourceId, ruleVersion: .current,
                        target: .attribute(.discipline), amount: amount,
                        reason: Self.reason(week: week, result: result), createdAt: now,
                        effectiveDate: week.adding(days: 7)
                    )
                    try await store.replaceDisciplineGrant(sourceId: sourceId, with: grant)
                }
                running += amount
            }
            week = week.adding(days: 7)
        }
    }

    public static func input(week: LocalDate, habits: [HabitDefinition], occurrences: [HabitOccurrence]) -> DisciplineCalculator.WeekInput {
        let days = week.weekDays.map { day -> (done: Int, scheduled: Int) in
            let scheduled = habits.filter { $0.isScheduled(on: day) }
            let ids = Set(scheduled.map(\.id))
            let done = Set(occurrences.filter { $0.localDate == day && ids.contains($0.habitId) }.map(\.habitId)).count
            return (done, scheduled.count)
        }
        let weekEnd = week.adding(days: 6)
        let weekly = habits.filter { $0.countsForWeek(starting: week) }.map { habit -> (done: Int, target: Int) in
            let done = occurrences.filter { $0.habitId == habit.id && $0.localDate >= week && $0.localDate <= weekEnd }.count
            return (done, habit.targetPerWeek)
        }
        return .init(days: days, weekly: weekly)
    }

    static func reason(week: LocalDate, result: DisciplineCalculator.WeekResult) -> String {
        let percent = Int(result.percent.rounded())
        let v = String(format: "%.2f", result.v).replacingOccurrences(of: ".", with: ",")
        return "Неделя с \(week): выполнено \(percent)% · v \(v)"
    }
}

/// Статус привычки на сегодня и текущую неделю — для «Сегодня», журнала и карточек.
public struct HabitStatus: Sendable, Equatable, Identifiable {
    public var habit: HabitDefinition
    public var skill: Skill?
    /// Отметки по датам: текущая неделя и вчера (в понедельник вчера — прошлая неделя).
    public var weekMarks: [LocalDate: Int]
    public var today: LocalDate
    public var id: UUID { habit.id }

    public var isScheduledToday: Bool { habit.kind == .weekly || habit.isScheduled(on: today) }
    public var doneToday: Bool { (weekMarks[today] ?? 0) > 0 }
    public var weekDone: Int { weekMarks.filter { $0.key >= today.weekStart }.values.reduce(0, +) }
    public func marks(on date: LocalDate) -> Int { weekMarks[date] ?? 0 }
    /// Для daily — запланировано на неделе; для weekly — цель.
    public var weekPlanned: Int {
        habit.kind == .weekly ? habit.targetPerWeek : today.weekDays.filter { habit.isScheduled(on: $0) }.count
    }
}

/// Сводка Epic: шаги и прогресс «N из M».
public struct EpicStatus: Sendable, Equatable, Identifiable {
    public var epic: EpicQuest
    public var steps: [TodayItem]
    public var id: UUID { epic.id }
    public var doneCount: Int { steps.filter(\.isCompleted).count }
    public var canComplete: Bool { !epic.isCompleted && !steps.isEmpty && doneCount == steps.count }
    public var nextStep: TodayItem? { steps.first { !$0.isCompleted } }
}

struct HabitStatusBuilder {
    let store: any QuestlynStore

    func statuses(today: LocalDate, skills: [Skill]) async throws -> [HabitStatus] {
        let week = today.weekStart
        let occurrences = try await store.occurrences(from: min(week, today.adding(days: -1)), through: week.adding(days: 6))
        return try await store.habits().filter(\.isActive).map { habit in
            var marks: [LocalDate: Int] = [:]
            for occurrence in occurrences where occurrence.habitId == habit.id {
                marks[occurrence.localDate, default: 0] += 1
            }
            return HabitStatus(habit: habit, skill: skills.first { $0.id == habit.skillId }, weekMarks: marks, today: today)
        }
        // По времени, без времени — внизу (8C.5); внутри — по созданию.
        .sorted { lhs, rhs in
            (lhs.habit.time == nil ? 1 : 0, lhs.habit.time?.description ?? "", lhs.habit.createdAt)
                < (rhs.habit.time == nil ? 1 : 0, rhs.habit.time?.description ?? "", rhs.habit.createdAt)
        }
    }
}

/// Сброс: начать путь с нуля после тестирования MVP (02, 10.11.2026). Необратимо.
public struct ResetService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    /// Слово, которое пользователь вводит для подтверждения.
    public static let confirmationWord = "СБРОС"

    public func resetEverything(confirmation: String) async throws {
        guard confirmation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == Self.confirmationWord else {
            throw QuestlynError.resetNotConfirmed
        }
        try await store.eraseAll()
    }
}

/// Epic: создание, шаги, завершение вручную (BACKLOG 2.3, 02).
public struct EpicService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    @discardableResult
    public func create(title: String, details: String, deadline: LocalDate?, steps: [QuestDraft], professionId: UUID? = nil,
                       now: Date, timeZone: TimeZone) async throws -> EpicQuest {
        let name = trimmed(title)
        guard !name.isEmpty else { throw QuestlynError.emptyName }
        let text = trimmed(details)
        let epic = EpicQuest(title: name, details: text.isEmpty ? nil : text, deadline: deadline, createdAt: now, professionId: professionId)
        let quests = try steps.filter { !trimmed($0.title).isEmpty }.enumerated().map { index, draft in
            // Порядок шагов сохраняется через время создания.
            try QuestService.makeQuest(draft, now: now.addingTimeInterval(Double(index) / 1000), timeZone: timeZone, epicId: epic.id)
        }
        try await store.createEpic(epic, steps: quests)
        return epic
    }

    /// Завершение — веха без XP. Только когда все шаги выполнены.
    public func complete(epicId: UUID, now: Date) async throws {
        guard var epic = try await store.epic(id: epicId) else { throw QuestlynError.epicNotFound }
        let steps = try await store.allQuests().filter { $0.epicId == epicId }
        let completions = try await store.activeCompletions(questIds: steps.map(\.id))
        guard !steps.isEmpty, steps.allSatisfy({ completions[$0.id] != nil }) else { throw QuestlynError.epicHasOpenSteps }
        epic.completedAt = now
        try await store.save(epic)
    }

    public func reopen(epicId: UUID) async throws {
        guard var epic = try await store.epic(id: epicId) else { throw QuestlynError.epicNotFound }
        epic.completedAt = nil
        try await store.save(epic)
    }

    /// Шаг в редактировании Epic: существующий (с id) или новый.
    public struct StepEdit: Sendable, Equatable {
        public var id: UUID?
        public var draft: QuestDraft
        public init(id: UUID? = nil, draft: QuestDraft) {
            self.id = id
            self.draft = draft
        }
    }

    /// Изменение Epic (3): название, описание, срок и шаги. Убранные шаги удаляются пометкой, их начисления остаются.
    public func update(epicId: UUID, title: String, details: String, deadline: LocalDate?, steps: [StepEdit],
                       professionId: UUID? = nil, now: Date, timeZone: TimeZone) async throws {
        guard var epic = try await store.epic(id: epicId) else { throw QuestlynError.epicNotFound }
        let name = trimmed(title)
        guard !name.isEmpty else { throw QuestlynError.emptyName }
        let kept = steps.filter { !trimmed($0.draft.title).isEmpty }
        guard !kept.isEmpty else { throw QuestlynError.epicNeedsStep }
        epic.title = name
        let text = trimmed(details)
        epic.details = text.isEmpty ? nil : text
        epic.deadline = deadline
        epic.professionId = professionId
        let existing = try await store.allQuests().filter { $0.epicId == epicId }
        let quests = QuestService(store: store)
        for (index, step) in kept.enumerated() {
            if let id = step.id, existing.contains(where: { $0.id == id }) {
                _ = try await quests.update(questId: id, with: step.draft)
            } else {
                // Новые шаги — в конец порядка.
                try await store.save(try QuestService.makeQuest(step.draft, now: now.addingTimeInterval(Double(index) / 1000),
                                                                timeZone: timeZone, epicId: epicId))
            }
        }
        let keptIds = Set(kept.compactMap(\.id))
        for var removed in existing where !keptIds.contains(removed.id) {
            removed.deletedAt = now
            try await store.save(removed)
        }
        try await store.save(epic)
    }

    /// Удаление Epic вместе с шагами (3). Выполненные шаги остаются в Летописи, прогресс не отнимается.
    public func delete(epicId: UUID, now: Date) async throws {
        guard var epic = try await store.epic(id: epicId) else { throw QuestlynError.epicNotFound }
        for var step in try await store.allQuests().filter({ $0.epicId == epicId }) {
            step.deletedAt = now
            try await store.save(step)
        }
        epic.deletedAt = now
        try await store.save(epic)
    }
}
