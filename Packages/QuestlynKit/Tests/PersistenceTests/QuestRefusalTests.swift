import Foundation
import Testing
@testable import Application
@testable import Domain
@testable import Persistence

/// «Отказаться от квеста» (12.11.2026): квест скрыт, прогресс и выполнение остаются.
struct QuestRefusalTests {
    let store: GRDBStore
    let utc = TimeZone(identifier: "UTC")!
    let now = ISO8601DateFormatter().date(from: "2026-11-10T18:00:00Z")!

    init() throws { store = GRDBStore(try AppDatabase.inMemory()) }

    @Test func refusedQuestDisappearsButProgressStays() async throws {
        try await OnboardingService(store: store).start(heroName: "Арин", catalogItemIds: ["software-engineer"], classTitle: "К", now: now, timeZone: utc)
        let quests = QuestService(store: store)
        let open = try await quests.create(QuestDraft(title: "Отчёт"), now: now, timeZone: utc)
        let done = try await quests.create(QuestDraft(title: "Ревью"), now: now + 1, timeZone: utc)
        _ = try await CompletionService(store: store).complete(questId: done.id, now: now + 60, timeZone: utc)
        let grantsBefore = try await store.allGrants().count

        try await quests.delete(questId: open.id, now: now + 120)
        try await quests.delete(questId: done.id, now: now + 120)

        #expect(try await store.allQuests().isEmpty)
        #expect(try await store.allQuestsIncludingDeleted().count == 2)
        #expect(try await store.allGrants().count == grantsBefore)
        #expect(try await store.activeCompletion(questId: done.id) != nil)
        await #expect(throws: QuestlynError.questNotFound) { try await quests.delete(questId: open.id, now: now + 200) }
    }
}
