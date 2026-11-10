import Foundation
import Testing
import Domain
import Application
@testable import Persistence

/// Этап 4: MP от квестов и возврат при отмене, сон вручную, настройки, перенос из Apple Health.
struct VitalsFlowTests {
    let store: GRDBStore
    let utc = TimeZone(identifier: "UTC")!
    let now = ISO8601DateFormatter().date(from: "2026-11-10T18:00:00Z")!

    init() throws { store = GRDBStore(try AppDatabase.inMemory()) }

    func setUp() async throws -> Skill {
        try await OnboardingService(store: store).start(heroName: "Арин", catalogItemIds: ["software-engineer", "athlete"], classTitle: "К", now: now, timeZone: utc)
        let hero = try #require(try await store.currentHero())
        let athlete = try await store.professions(heroId: hero.id)[1]
        return try await SkillService(store: store).create(title: "Бег", professionId: athlete.id, now: now)
    }

    func vitals(at date: Date) async throws -> VitalsState {
        try #require(try await TodayService(store: store).overview(now: date, timeZone: utc).vitals)
    }

    @Test func questSpendsManaAndUndoReturnsIt() async throws {
        let skill = try await setUp()
        // Стартовый бонус: INT 1 и STR 1 — максимумы 105.
        let start = try await vitals(at: now + 60)
        #expect(start.maxHP == 105 && start.maxMP == 105 && start.mp == 105)
        let quest = try await QuestService(store: store).create(QuestDraft(title: "Пробежка", priority: .high, skillId: skill.id), now: now, timeZone: utc)
        _ = try await CompletionService(store: store).complete(questId: quest.id, now: now + 120, timeZone: utc)
        #expect(try await vitals(at: now + 180).mp == 96)
        try await CompletionService(store: store).undo(questId: quest.id, now: now + 240)
        #expect(try await vitals(at: now + 300).mp == 105)
    }

    @Test func manualSleepReplacesSameNight() async throws {
        _ = try await setUp()
        let morning = now + 14 * 3600
        let sleep = SleepService(store: store)
        try await sleep.recordManual(duration: .h5to6, bedtime: .muchLater, now: morning, timeZone: utc)
        try await sleep.recordManual(duration: .h7to8, bedtime: .onTime, now: morning, timeZone: utc)
        let sessions = try await store.sleepSessions()
        #expect(sessions.count == 1 && sessions.first?.durationMinutes == 450)
        let overview = try await TodayService(store: store).overview(now: morning, timeZone: utc)
        #expect(overview.hasSleepToday)
        #expect(overview.vitals?.lastNight?.quality == 1.0)
    }

    @Test func settingsRoundTripAndValidation() async throws {
        #expect(try await store.vitalSettings() == .default)
        let custom = VitalSettings(sleepWindow: SleepWindow(start: LocalTime(hour: 0, minute: 30)!, end: LocalTime(hour: 8, minute: 0)!), stepGoal: 8000)
        try await VitalsService(store: store).updateSettings(custom)
        #expect(try await store.vitalSettings() == custom)
        await #expect(throws: QuestlynError.invalidStepGoal) {
            try await VitalsService(store: store).updateSettings(VitalSettings(stepGoal: 0))
        }
    }

    @Test func healthSyncStoresNightsAndSteps() async throws {
        _ = try await setUp()
        let morning = now + 14 * 3600
        let wake = LocalDate(morning, timeZone: utc)
        let source = FakeHealth(nights: [HealthSleepNight(wakeDate: wake, asleepMinutes: 450, startedAt: morning - 9 * 3600, endedAt: morning - 600)],
                                steps: [LocalDate(now, timeZone: utc): 3200])
        try await HealthSyncService(store: store, source: source).sync(now: morning, timeZone: utc)
        try await HealthSyncService(store: store, source: source).sync(now: morning, timeZone: utc)
        let sessions = try await store.sleepSessions()
        #expect(sessions.count == 1 && sessions.first?.source == .health)
        // Отбой 23:00 по UTC — ровно по режиму.
        #expect(sessions.first?.bedtimeDeviationMinutes == 0)
        #expect(try await store.stepDays().map(\.steps) == [3200])
        // Сидячий день: 105 − 5% = 99,75, потом ночь Q = 1: +63 → максимум.
        let state = try await vitals(at: morning)
        #expect(state.hp == 105)
        #expect(state.lastNight?.hpBefore == 99.75)
    }
}

private struct FakeHealth: HealthDataSource {
    var nights: [HealthSleepNight]
    var steps: [LocalDate: Int]
    var isAvailable: Bool { true }
    func requestAuthorization() async throws {}
    func sleepNights(from: Date, to: Date, timeZone: TimeZone) async throws -> [HealthSleepNight] { nights }
    func stepCounts(from: Date, to: Date, timeZone: TimeZone) async throws -> [LocalDate: Int] { steps }
}
