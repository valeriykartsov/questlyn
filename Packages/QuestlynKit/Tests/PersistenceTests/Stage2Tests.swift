import Foundation
import Testing
import GRDB
import Domain
import Application
@testable import Persistence

/// Этап 2: привычки, DIS, Epic, изменение квеста, миграция v1 → v2.
struct Stage2Tests {
    let store: GRDBStore
    let utc = TimeZone(identifier: "UTC")!

    init() throws { store = GRDBStore(try AppDatabase.inMemory()) }

    func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text + "T12:00:00Z")! }
    func day(_ text: String) -> LocalDate { LocalDate(string: text)! }

    /// Герой «Инженер-программист» + «Атлет», навык «ОФП» у Атлета.
    func setUp(createdAt: String) async throws -> Skill {
        try await OnboardingService(store: store).start(heroName: "Арин", catalogItemIds: ["software-engineer", "athlete"], classTitle: "К", now: at(createdAt))
        let hero = try #require(try await store.currentHero())
        let athlete = try await store.professions(heroId: hero.id)[1]
        return try await SkillService(store: store).create(title: "ОФП", professionId: athlete.id, now: at(createdAt))
    }

    @Test func dailyMarkUnmarkAndRules() async throws {
        let skill = try await setUp(createdAt: "2026-11-10")
        let habit = try await HabitService(store: store).create(
            HabitDraft(kind: .daily, title: "Зарядка", skillId: skill.id, weekdays: Weekday.workdays), now: at("2026-11-10"), timeZone: utc
        )
        let marks = HabitMarkService(store: store)
        let now = at("2026-11-11")
        let grants = try await marks.mark(habitId: habit.id, on: day("2026-11-11"), now: now, timeZone: utc)
        #expect(grants.map(\.amount.value) == [500, 250, 150, 125])
        await #expect(throws: QuestlynError.alreadyMarked) {
            try await marks.mark(habitId: habit.id, on: day("2026-11-11"), now: now, timeZone: utc)
        }
        // Вчера — можно, позавчера — нет (и это день до создания).
        try await marks.mark(habitId: habit.id, on: day("2026-11-10"), now: now, timeZone: utc)
        await #expect(throws: QuestlynError.cannotMarkDate) {
            try await marks.mark(habitId: habit.id, on: day("2026-11-09"), now: now, timeZone: utc)
        }
        // Суббота не запланирована.
        await #expect(throws: QuestlynError.notScheduled) {
            try await marks.mark(habitId: habit.id, on: day("2026-11-14"), now: at("2026-11-14"), timeZone: utc)
        }
        try await marks.unmark(habitId: habit.id, on: day("2026-11-11"), now: now, timeZone: utc)
        #expect(try await store.allGrants().filter { $0.sourceType == .habitOccurrence }.count == 4)
        #expect(try await store.allGrants().filter { $0.sourceType == .habitOccurrence }.allSatisfy { $0.effectiveDate == day("2026-11-10") })
    }

    @Test func weeklyAllowsSeveralMarksAndCountsInStatus() async throws {
        _ = try await setUp(createdAt: "2026-11-10")
        let habit = try await HabitService(store: store).create(HabitDraft(kind: .weekly, title: "Бег", targetPerWeek: 3), now: at("2026-11-10"), timeZone: utc)
        let marks = HabitMarkService(store: store)
        for _ in 0..<4 { try await marks.mark(habitId: habit.id, on: day("2026-11-11"), now: at("2026-11-11"), timeZone: utc) }
        let overview = try await TodayService(store: store).overview(now: at("2026-11-11"), timeZone: utc)
        let status = try #require(overview.habits.first)
        #expect(status.weekDone == 4 && status.weekPlanned == 3)
        // Без навыка начислений нет.
        #expect(try await earned(store).isEmpty)
    }

    /// Пишем историю отметок напрямую: через сервис можно отмечать только сегодня и вчера.
    func markHistory(_ habit: HabitDefinition, _ days: [String]) async throws {
        for d in days {
            try await store.record(HabitOccurrence(habitId: habit.id, localDate: day(d), completedAt: at(d), timezoneId: "UTC", classSnapshot: .empty), grants: [])
        }
    }

    @Test func disciplineSettlesWeeksSkipsCreationWeekAndClampsAtZero() async throws {
        _ = try await setUp(createdAt: "2026-11-04") // среда: неделя 2–8 ноября не считается
        let habit = try await HabitService(store: store).create(HabitDraft(kind: .daily, title: "Чтение"), now: at("2026-11-04"), timeZone: utc)
        try await markHistory(habit, ["2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15"])
        let service = DisciplineService(store: store)

        try await service.settle(now: at("2026-11-17"), timeZone: utc)
        var dis = try await store.disciplineGrants()
        // Неделя 9–15: 100%, запланировано 7 → v = 1,0 → +30.
        #expect(dis.map(\.amount.value) == [3000])

        // Две пустые недели: −30, затем 0 (DIS не ниже 0).
        try await service.settle(now: at("2026-12-01"), timeZone: utc)
        dis = try await store.disciplineGrants()
        #expect(dis.map(\.amount.value).sorted() == [-3000, 0, 3000])
        let progress = HeroProgress(grants: try await store.allGrants(), classAttributes: [])
        #expect(progress.xp(.discipline) == .zero)

        // Повторный пересчёт ничего не дублирует.
        try await service.settle(now: at("2026-12-01"), timeZone: utc)
        #expect(try await store.disciplineGrants().count == 3)
    }

    @Test func mondayMarkForSundayRecalculatesLastWeek() async throws {
        _ = try await setUp(createdAt: "2026-11-02") // понедельник — неделя считается
        let habit = try await HabitService(store: store).create(HabitDraft(kind: .daily, title: "Чтение"), now: at("2026-11-02"), timeZone: utc)
        try await markHistory(habit, ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07"])
        let monday = at("2026-11-09")
        try await DisciplineService(store: store).settle(now: monday, timeZone: utc)
        let before = try #require(try await store.disciplineGrants().first)
        // 6 из 7 дней: p = 85,71…, v = 1 → +21,43.
        #expect(before.amount == CentiXP(2143))

        try await HabitMarkService(store: store).mark(habitId: habit.id, on: day("2026-11-08"), now: monday, timeZone: utc)
        let after = try await store.disciplineGrants()
        #expect(after.count == 1 && after[0].amount == CentiXP(3000))
    }

    @Test func epicCompletesManuallyWhenAllStepsDone() async throws {
        _ = try await setUp(createdAt: "2026-11-10")
        let now = at("2026-11-10")
        let epic = try await EpicService(store: store).create(
            title: "Полумарафон", details: "", deadline: day("2027-04-25"),
            steps: [QuestDraft(title: "Купить кроссовки"), QuestDraft(title: "План тренировок"), QuestDraft(title: " ")],
            now: now, timeZone: utc
        )
        var overview = try await TodayService(store: store).overview(now: now, timeZone: utc)
        let status = try #require(overview.epics.first)
        #expect(status.steps.map(\.quest.title) == ["Купить кроссовки", "План тренировок"])
        await #expect(throws: QuestlynError.epicHasOpenSteps) { try await EpicService(store: store).complete(epicId: epic.id, now: now) }

        for step in status.steps { _ = try await CompletionService(store: store).complete(questId: step.quest.id, now: now, timeZone: utc) }
        overview = try await TodayService(store: store).overview(now: now, timeZone: utc)
        #expect(overview.epics.first?.canComplete == true)
        try await EpicService(store: store).complete(epicId: epic.id, now: now)
        #expect(try await store.epic(id: epic.id)?.isCompleted == true)
        // Шаги дали только FOC, сам Epic — ничего.
        #expect(HeroProgress(grants: try await earned(store), classAttributes: []).xp(.focus) == .xp(10))
    }

    @Test func completedQuestKeepsPriorityAndSkill() async throws {
        _ = try await setUp(createdAt: "2026-11-10")
        let now = at("2026-11-10")
        let quests = QuestService(store: store)
        let quest = try await quests.create(QuestDraft(title: "Отчёт", dueDate: day("2026-11-10")), now: now, timeZone: utc)
        // Перенос невыполненного.
        var draft = QuestDraft(title: "Отчёт v2", priority: .high, dueDate: day("2026-11-12"))
        let moved = try await quests.update(questId: quest.id, with: draft)
        #expect(moved.dueDate == day("2026-11-12") && moved.priority == .high && moved.createdAt == quest.createdAt)

        _ = try await CompletionService(store: store).complete(questId: quest.id, now: now, timeZone: utc)
        draft.title = "Отчёт v3"
        _ = try await quests.update(questId: quest.id, with: draft)
        draft.priority = .low
        await #expect(throws: QuestlynError.lockedWhileCompleted) { try await quests.update(questId: quest.id, with: draft) }
    }
}

/// Данные этапа 1 переживают миграцию v2.
struct MigrationUpgradeTests {
    @Test func v3BackfillsGrantDates() throws {
        let queue = try DatabaseQueue()
        try Migrations.migrator.migrate(queue, upTo: Migrations.habitsAndEpics)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO hero (id, name, classTitle, createdAt) VALUES ('h', 'Г', 'К', '2026-11-01 10:00:00.000')")
            try db.execute(sql: "INSERT INTO quest (id, title, timezoneId, createdAt) VALUES ('q', 'К', 'UTC', '2026-11-01')")
            try db.execute(sql: "INSERT INTO questCompletion (id, questId, completedAt, localDate, timezoneId, classSnapshot) VALUES ('c', 'q', '2026-11-03 23:30:00.000', '2026-11-04', 'Europe/Moscow', '{}')")
            try db.execute(sql: """
                INSERT INTO progressGrant (id, sourceType, sourceId, ruleVersion, targetKind, attribute, targetKey, amountCenti, reason, createdAt) VALUES
                ('g1', 'questCompletion', 'c', '1.1', 'attribute', 'FOC', 'attribute:FOC', 500, '', '2026-11-03 23:30:00.000'),
                ('g2', 'weeklyDiscipline', 'd15c0000-0000-4000-8000-000020261102', '1.1', 'attribute', 'DIS', 'attribute:DIS', 3000, '', '2026-11-09 08:00:00.000')
                """)
        }
        try Migrations.migrator.migrate(queue)
        let dates = try queue.read { db in try Row.fetchAll(db, sql: "SELECT id, localDate FROM progressGrant ORDER BY id") }
        #expect(dates.map { $0["localDate"] as String? } == ["2026-11-04", "2026-11-09"])
        let hero = try queue.read { db in try Row.fetchOne(db, sql: "SELECT hair, skin FROM hero") }
        #expect(hero?["hair"] == "dark" && hero?["skin"] == "medium")
    }

    @Test func v5GivesExistingHeroDefaultOutfit() throws {
        let queue = try DatabaseQueue()
        try Migrations.migrator.migrate(queue, upTo: Migrations.activities)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO hero (id, name, classTitle, hair, skin, createdAt) VALUES ('h', 'Г', 'К', 'red', 'tan', '2026-11-01 10:00:00.000')")
        }
        try Migrations.migrator.migrate(queue)
        let row = try queue.read { db in try Row.fetchOne(db, sql: "SELECT hair, skin, outfit FROM hero") }
        #expect(row?["outfit"] == "coder" && row?["hair"] == "red" && row?["skin"] == "tan")
    }

    @Test func v1DataSurvivesV2() throws {
        let queue = try DatabaseQueue()
        try Migrations.migrator.migrate(queue, upTo: Migrations.initial)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO quest (id, title, timezoneId, createdAt) VALUES ('q', 'Старый квест', 'UTC', '2026-11-10')")
        }
        try Migrations.migrator.migrate(queue)
        let row = try queue.read { db in try Row.fetchOne(db, sql: "SELECT title, epicId FROM quest") }
        #expect(row?["title"] == "Старый квест")
        #expect((row?["epicId"] as String?) == nil)
    }
}
