import Foundation
import Testing
import Domain
import Application
@testable import Persistence

/// Сброс всех данных: только с подтверждением, после — пустая БД с актуальной схемой.
struct ResetTests {
    @Test func resetRequiresConfirmationAndErasesEverything() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "questlyn-reset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_794_301_200)
        let tz = TimeZone(identifier: "UTC")!
        let store = GRDBStore(try AppDatabase.onDisk(at: directory))

        try await OnboardingService(store: store).start(heroName: "Арин", catalogItemIds: ["athlete"], classTitle: "Атлет", now: now)
        let quest = try await QuestService(store: store).create(QuestDraft(title: "Бег"), now: now, timeZone: tz)
        _ = try await CompletionService(store: store).complete(questId: quest.id, now: now, timeZone: tz)
        try await HabitService(store: store).create(HabitDraft(kind: .daily, title: "Зарядка"), now: now, timeZone: tz)

        let reset = ResetService(store: store)
        await #expect(throws: QuestlynError.resetNotConfirmed) { try await reset.resetEverything(confirmation: "да") }
        #expect(try await store.currentHero() != nil)

        try await reset.resetEverything(confirmation: " сброс ")
        #expect(try await store.currentHero() == nil)
        #expect(try await store.allQuests().isEmpty)
        #expect(try await store.allGrants().isEmpty)
        #expect(try await store.habits().isEmpty)

        // После сброса можно начать заново, в том числе после перезапуска.
        try await OnboardingService(store: store).start(heroName: "Новый", catalogItemIds: ["athlete"], classTitle: "", now: now)
        let reopened = GRDBStore(try AppDatabase.onDisk(at: directory))
        #expect(try await reopened.currentHero()?.name == "Новый")
    }
}
