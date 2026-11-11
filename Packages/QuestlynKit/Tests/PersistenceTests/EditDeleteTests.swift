import Foundation
import Testing
import Domain
import Application
@testable import Persistence

/// Изменение и удаление Epic и привычек (пункты 3, 4 от 11.11.2026).
struct EditDeleteTests {
    let store: GRDBStore
    let utc = TimeZone(identifier: "UTC")!
    let now = ISO8601DateFormatter().date(from: "2026-11-10T18:00:00Z")!

    init() throws { store = GRDBStore(try AppDatabase.inMemory()) }

    func setUp() async throws {
        try await OnboardingService(store: store).start(heroName: "Арин", catalogItemIds: ["software-engineer"], classTitle: "К", now: now, timeZone: utc)
    }

    @Test func epicWithoutDeadlineEditAndDelete() async throws {
        try await setUp()
        let service = EpicService(store: store)
        let epic = try await service.create(title: "Полумарафон", details: "", deadline: nil,
                                            steps: [QuestDraft(title: "Шаг 1"), QuestDraft(title: "Шаг 2")], now: now, timeZone: utc)
        var steps = try await store.allQuests().filter { $0.epicId == epic.id }
        _ = try await CompletionService(store: store).complete(questId: steps[0].id, now: now + 10, timeZone: utc)
        _ = try await TodayService(store: store).overview(now: now + 20, timeZone: utc)

        // Переименовать, убрать второй шаг, добавить новый.
        try await service.update(epicId: epic.id, title: "Марафон", details: "весной", deadline: LocalDate(year: 2026, month: 12, day: 1),
                                 steps: [.init(id: steps[0].id, draft: QuestDraft(title: "Шаг 1")), .init(draft: QuestDraft(title: "Шаг 3"))],
                                 now: now + 30, timeZone: utc)
        steps = try await store.allQuests().filter { $0.epicId == epic.id }
        #expect(steps.map(\.title) == ["Шаг 1", "Шаг 3"], "\(steps.map(\.title))")
        #expect(try await store.epic(id: epic.id)?.title == "Марафон")
        await #expect(throws: QuestlynError.epicNeedsStep) {
            try await service.update(epicId: epic.id, title: "М", details: "", deadline: nil, steps: [], now: now, timeZone: utc)
        }

        let xpBefore = try await store.allGrants().count
        try await service.delete(epicId: epic.id, now: now + 40)
        #expect(try await store.epics().isEmpty)
        #expect(try await store.allQuests().filter { $0.epicId == epic.id }.isEmpty)
        #expect(try await store.allGrants().count == xpBefore, "прогресс не отнимается")
        // Летопись помнит выполненный шаг удалённого Epic.
        let items = try await ChronicleService(store: store).feed(now: now + 50, timeZone: utc).flatMap(\.items)
        #expect(items.contains { $0.title == "Шаг 1" })
    }

    @Test func archivedHabitLeavesListsAndCurrentWeek() async throws {
        try await setUp()
        let habit = try await HabitService(store: store).create(HabitDraft(kind: .daily, title: "Зарядка"), now: now, timeZone: utc)
        try await HabitService(store: store).archive(habitId: habit.id, now: now + 60, timeZone: utc)
        let overview = try await TodayService(store: store).overview(now: now + 120, timeZone: utc)
        #expect(overview.habits.isEmpty)
        let archived = try #require(try await store.habit(id: habit.id))
        #expect(!archived.isScheduled(on: LocalDate(now, timeZone: utc)))
        #expect(archived.archivedOn == LocalDate(now, timeZone: utc))
    }
}
