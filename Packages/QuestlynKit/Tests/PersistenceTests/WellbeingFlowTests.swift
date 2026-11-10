import Foundation
import Testing
import Domain
import Application
@testable import Persistence

/// Этап 6A: лист «Как вы?», свои привычки, Летопись.
struct WellbeingFlowTests {
    let store: GRDBStore
    let utc = TimeZone(identifier: "UTC")!
    let now = ISO8601DateFormatter().date(from: "2026-11-10T18:00:00Z")!

    init() throws { store = GRDBStore(try AppDatabase.inMemory()) }

    func setUp() async throws {
        try await OnboardingService(store: store).start(heroName: "Арин", catalogItemIds: ["software-engineer"], classTitle: "К", now: now, timeZone: utc)
    }

    @Test func checkInRecordsMoodAndCounters() async throws {
        try await setUp()
        let service = WellbeingService(store: store)
        await #expect(throws: QuestlynError.emptyCheckIn) { try await service.checkIn(CheckInDraft(), now: now, timeZone: utc) }
        let report = try await service.checkIn(CheckInDraft(mood: .bad, note: " устал ", counts: [.smoking: 2, .fastFood: 1]), now: now + 60, timeZone: utc)
        #expect(report.harms.count == 3 && report.mood?.note == "устал")
        let overview = try await TodayService(store: store).overview(now: now + 120, timeZone: utc)
        #expect(overview.weather == .rain && overview.todayHarms.count == 3)
        // 100 − 3 − 3 − 5.
        #expect(overview.vitals?.hp == 89)
        try await service.deleteHarm(id: report.harms[2].id, now: now + 180)
        #expect(try await TodayService(store: store).overview(now: now + 240, timeZone: utc).vitals?.hp == 94)
    }

    @Test func daySummaryReplacesPrevious() async throws {
        try await setUp()
        let service = WellbeingService(store: store)
        try await service.checkIn(CheckInDraft(mood: .good, isDaySummary: true), now: now, timeZone: utc)
        try await service.checkIn(CheckInDraft(mood: .neutral, isDaySummary: true), now: now + 60, timeZone: utc)
        let moods = try await store.moodEntries()
        #expect(moods.filter(\.isDaySummary).map(\.mood) == [.neutral])
    }

    @Test func customHabitAndChronicle() async throws {
        try await setUp()
        let service = WellbeingService(store: store)
        await #expect(throws: QuestlynError.invalidHarmStrength) { try await service.createHabit(title: "Сладкое", damagePercent: 7, now: now) }
        let habit = try await service.createHabit(title: "Сладкое", damagePercent: 10, now: now)
        try await service.checkIn(CheckInDraft(customCounts: [habit.id: 1], alcohol: .little), now: now + 60, timeZone: utc)
        try await service.archiveHabit(id: habit.id)
        #expect(try await TodayService(store: store).overview(now: now + 70, timeZone: utc).customHarmHabits.isEmpty)
        let items = try await ChronicleService(store: store).feed(now: now + 120, timeZone: utc).flatMap(\.items)
        #expect(items.contains { $0.title == "Сладкое" && $0.changes == [.hp(-10)] })
        #expect(items.contains { $0.title == "Алкоголь — немного" && $0.category == .health })
    }
}
