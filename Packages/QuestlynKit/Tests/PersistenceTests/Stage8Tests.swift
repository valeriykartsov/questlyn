import Foundation
import Testing
import GRDB
import Domain
import Application
@testable import Persistence

/// Этап 8: исправление сна, снятие недельных отметок, профессия у Epic, навык ↔ вид активности, миграция v10.
struct Stage8Tests {
    let store: GRDBStore
    let utc = TimeZone(identifier: "UTC")!
    /// Вторник, 10 ноября 2026.
    let now = ISO8601DateFormatter().date(from: "2026-11-10T18:00:00Z")!

    init() throws { store = GRDBStore(try AppDatabase.inMemory()) }

    func onboard(at date: Date) async throws -> [Profession] {
        try await OnboardingService(store: store).start(heroName: "Арин", catalogItemIds: ["software-engineer", "athlete"], classTitle: "К", now: date, timeZone: utc)
        let hero = try #require(try await store.currentHero())
        return try await store.professions(heroId: hero.id)
    }

    // MARK: 8.1 исправление сна

    @Test func correctionWinsOverHealthAndSurvivesSync() async throws {
        _ = try await onboard(at: now)
        let morning = now + 14 * 3600
        let wake = LocalDate(morning, timeZone: utc)
        let health = Stage8Health(nights: [HealthSleepNight(wakeDate: wake, asleepMinutes: 330, startedAt: morning - 7 * 3600, endedAt: morning - 1800)])
        try await HealthSyncService(store: store, source: health).sync(now: morning, timeZone: utc)

        // 23:00–06:30 — 7 ч 30 мин, отбой по режиму.
        let start = ISO8601DateFormatter().date(from: "2026-11-10T23:00:00Z")!
        let end = ISO8601DateFormatter().date(from: "2026-11-11T06:30:00Z")!
        let corrected = try await SleepService(store: store).correct(wakeDate: wake, startedAt: start, endedAt: end, now: morning, timeZone: utc)
        #expect(corrected.source == .corrected && corrected.durationMinutes == 450 && corrected.bedtimeDeviationMinutes == 0)

        try await HealthSyncService(store: store, source: health).sync(now: morning + 60, timeZone: utc)
        #expect(try await store.sleepSessions().map(\.source).sorted { $0.rawValue < $1.rawValue } == [.corrected, .health])

        let state = try #require(try await TodayService(store: store).overview(now: morning + 120, timeZone: utc).vitals)
        #expect(state.lastNight?.session?.source == .corrected)
        #expect(state.lastNight?.session?.durationMinutes == 450)
        #expect(state.lastNight?.replaced?.durationMinutes == 330)
        #expect(state.lastNight?.quality == 1.0)

        let night = try await ChronicleService(store: store).feed(now: morning + 120, timeZone: utc)
            .flatMap(\.items).first { $0.badge == "исправлено" }
        #expect(night?.detail?.contains("было 5 ч 30 мин, Apple Health") == true)
    }

    @Test func repeatedCorrectionReplacesPrevious() async throws {
        _ = try await onboard(at: now)
        let morning = now + 14 * 3600
        let wake = LocalDate(morning, timeZone: utc)
        let sleep = SleepService(store: store)
        try await sleep.correct(wakeDate: wake, startedAt: morning - 8 * 3600, endedAt: morning - 3600, now: morning, timeZone: utc)
        try await sleep.correct(wakeDate: wake, startedAt: morning - 9 * 3600, endedAt: morning - 3600, now: morning + 60, timeZone: utc)
        let sessions = try await store.sleepSessions()
        #expect(sessions.count == 1 && sessions.first?.durationMinutes == 480)
    }

    @Test func correctionLimits() async throws {
        _ = try await onboard(at: now)
        let sleep = SleepService(store: store)
        let today = LocalDate(now, timeZone: utc)
        await #expect(throws: QuestlynError.cannotCorrectNight) {
            try await sleep.correct(wakeDate: today.adding(days: -7), startedAt: now - 9 * 3600, endedAt: now - 3600, now: now, timeZone: utc)
        }
        await #expect(throws: QuestlynError.invalidSleepInterval) {
            try await sleep.correct(wakeDate: today, startedAt: now - 3600, endedAt: now + 3600, now: now, timeZone: utc)
        }
        await #expect(throws: QuestlynError.invalidSleepInterval) {
            try await sleep.correct(wakeDate: today, startedAt: now - 3600, endedAt: now - 7200, now: now, timeZone: utc)
        }
        // Шестой день назад — ещё можно.
        try await sleep.correct(wakeDate: today.adding(days: -6), startedAt: now - 7 * 86400, endedAt: now - 7 * 86400 + 7 * 3600, now: now, timeZone: utc)
    }

    // MARK: 8.5 недельные отметки

    @Test func weeklyMarkOfCurrentWeekCanBeUnmarked() async throws {
        let monday = ISO8601DateFormatter().date(from: "2026-11-09T08:00:00Z")!
        _ = try await onboard(at: monday)
        let habits = HabitService(store: store)
        let habit = try await habits.create(HabitDraft(kind: .weekly, title: "Бег", targetPerWeek: 1), now: monday, timeZone: utc)
        _ = try await HabitMarkService(store: store).mark(habitId: habit.id, on: LocalDate(monday, timeZone: utc), now: monday + 60, timeZone: utc)
        _ = try await HabitMarkService(store: store).mark(habitId: habit.id, on: LocalDate(now, timeZone: utc), now: now, timeZone: utc)
        let mondayMark = try #require(try await store.occurrences(from: LocalDate(monday, timeZone: utc), through: LocalDate(monday, timeZone: utc)).first)
        let wednesday = now + 86400
        // Позавчерашнюю отметку недельного квеста снять можно — та же неделя.
        try await HabitMarkService(store: store).unmarkWeekly(occurrenceId: mondayMark.id, now: wednesday, timeZone: utc)
        let left = try await store.occurrences(from: LocalDate(monday, timeZone: utc), through: LocalDate(wednesday, timeZone: utc))
        #expect(left.count == 1 && left.first?.localDate == LocalDate(now, timeZone: utc))
        #expect(try await store.grants(sourceId: mondayMark.id).isEmpty)
    }

    @Test func weeklyMarkOfClosedWeekStays() async throws {
        let sunday = ISO8601DateFormatter().date(from: "2026-11-08T10:00:00Z")!
        _ = try await onboard(at: sunday)
        let habits = HabitService(store: store)
        let habit = try await habits.create(HabitDraft(kind: .weekly, title: "Бег", targetPerWeek: 1), now: sunday, timeZone: utc)
        _ = try await HabitMarkService(store: store).mark(habitId: habit.id, on: LocalDate(sunday, timeZone: utc), now: sunday + 60, timeZone: utc)
        let mark = try #require(try await store.occurrences(from: LocalDate(sunday, timeZone: utc), through: LocalDate(sunday, timeZone: utc)).first)
        await #expect(throws: QuestlynError.cannotMarkDate) {
            try await HabitMarkService(store: store).unmarkWeekly(occurrenceId: mark.id, now: now, timeZone: utc)
        }
    }

    @Test func dailyHabitIsNotUnmarkedAsWeekly() async throws {
        let monday = ISO8601DateFormatter().date(from: "2026-11-09T08:00:00Z")!
        _ = try await onboard(at: monday)
        let habits = HabitService(store: store)
        let habit = try await habits.create(HabitDraft(kind: .daily, title: "Зарядка"), now: monday, timeZone: utc)
        _ = try await HabitMarkService(store: store).mark(habitId: habit.id, on: LocalDate(monday, timeZone: utc), now: monday + 60, timeZone: utc)
        let mark = try #require(try await store.occurrences(from: LocalDate(monday, timeZone: utc), through: LocalDate(monday, timeZone: utc)).first)
        await #expect(throws: QuestlynError.cannotMarkDate) {
            try await HabitMarkService(store: store).unmarkWeekly(occurrenceId: mark.id, now: now + 86400, timeZone: utc)
        }
    }

    // MARK: 8.4 профессия у Epic

    @Test func epicsWithProfessionGoFirstBySlot() async throws {
        let professions = try await onboard(at: now)
        let epics = EpicService(store: store)
        let step = [QuestDraft(title: "Шаг")]
        try await epics.create(title: "Переезд", details: "", deadline: nil, steps: step, now: now, timeZone: utc)
        try await epics.create(title: "Полумарафон", details: "", deadline: nil, steps: step, professionId: professions[1].id, now: now + 1, timeZone: utc)
        let project = try await epics.create(title: "Пет-проект", details: "", deadline: nil, steps: step, professionId: professions[0].id, now: now + 2, timeZone: utc)
        let overview = try await TodayService(store: store).overview(now: now + 10, timeZone: utc)
        #expect(overview.epics.map(\.epic.title) == ["Пет-проект", "Полумарафон", "Переезд"])

        // Изменение без профессии убирает её.
        let steps = overview.epics.first { $0.epic.id == project.id }!.steps.map { EpicService.StepEdit(id: $0.quest.id, draft: QuestDraft(title: $0.quest.title)) }
        try await epics.update(epicId: project.id, title: "Пет-проект", details: "", deadline: nil, steps: steps, now: now + 20, timeZone: utc)
        #expect(try await store.epic(id: project.id)?.professionId == nil)
    }

    // MARK: 8.6 навык ↔ вид активности

    @Test func activityLinkIsOneToOne() async throws {
        let professions = try await onboard(at: now)
        let skills = SkillService(store: store)
        let run = try await skills.create(title: "Бег", professionId: professions[1].id, now: now)
        let walk = try await skills.create(title: "Ходьба", professionId: professions[1].id, now: now + 1)
        let cardio = try #require(ActivityTemplate.all.first { $0.id != ActivityTemplate.all[0].id }).id
        try await skills.linkActivity(templateId: cardio, skillId: run.id)
        try await skills.linkActivity(templateId: cardio, skillId: walk.id)
        var stored = Dictionary(uniqueKeysWithValues: try await store.skills().map { ($0.id, $0.activityTemplateId) })
        #expect(stored[run.id]! == nil && stored[walk.id]! == cardio)
        // У навыка один вид: новый вид заменяет прежний.
        let other = ActivityTemplate.all[0].id
        try await skills.linkActivity(templateId: other, skillId: walk.id)
        stored = Dictionary(uniqueKeysWithValues: try await store.skills().map { ($0.id, $0.activityTemplateId) })
        #expect(stored[walk.id]! == other)
        try await skills.linkActivity(templateId: nil, skillId: walk.id)
        #expect(try await store.skills().allSatisfy { $0.activityTemplateId == nil })
        await #expect(throws: QuestlynError.unknownActivityType) {
            try await skills.linkActivity(templateId: "нет-такого", skillId: run.id)
        }
    }

    // MARK: миграция v10

    @Test func v10KeepsSleepAndAllowsCorrected() throws {
        let queue = try DatabaseQueue()
        try Migrations.migrator.migrate(queue, upTo: Migrations.softDelete)
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO sleepSession (id, wakeDate, durationMinutes, source, timezoneId, createdAt)
                VALUES ('s', '2026-11-10', 450, 'health', 'UTC', '2026-11-10 07:00:00.000')
                """)
        }
        try Migrations.migrator.migrate(queue)
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO sleepSession (id, wakeDate, durationMinutes, source, timezoneId, createdAt)
                VALUES ('c', '2026-11-10', 420, 'corrected', 'UTC', '2026-11-10 09:00:00.000')
                """)
        }
        let rows = try queue.read { db in try Row.fetchAll(db, sql: "SELECT id, source FROM sleepSession ORDER BY id") }
        #expect(rows.map { $0["source"] as String } == ["corrected", "health"])
        let indexes = try queue.read { db in try db.indexes(on: "sleepSession").map(\.name) }
        #expect(indexes.contains("index_sleepSession_on_wakeDate"))
        let epicColumns = try queue.read { db in try db.columns(in: "epic").map(\.name) }
        let skillColumns = try queue.read { db in try db.columns(in: "skill").map(\.name) }
        #expect(epicColumns.contains("professionId") && skillColumns.contains("activityTemplateId"))
    }
}

private struct Stage8Health: HealthDataSource {
    var nights: [HealthSleepNight]
    var isAvailable: Bool { true }
    func requestAuthorization() async throws {}
    func sleepNights(from: Date, to: Date, timeZone: TimeZone) async throws -> [HealthSleepNight] { nights }
    func stepCounts(from: Date, to: Date, timeZone: TimeZone) async throws -> [LocalDate: Int] { [:] }
}
