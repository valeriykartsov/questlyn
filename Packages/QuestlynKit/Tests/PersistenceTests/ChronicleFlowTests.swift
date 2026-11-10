import Foundation
import Testing
import Domain
import Application
@testable import Persistence

/// Этап 5: лента Летописи и вехи (08, раздел 4 и 4.1).
struct ChronicleFlowTests {
    let store: GRDBStore
    let utc = TimeZone(identifier: "UTC")!
    let now = ISO8601DateFormatter().date(from: "2026-11-10T18:00:00Z")!

    init() throws { store = GRDBStore(try AppDatabase.inMemory()) }

    func setUp() async throws {
        try await OnboardingService(store: store).start(heroName: "Арин", catalogItemIds: ["software-engineer"], classTitle: "К", now: now, timeZone: utc)
    }

    func items(at date: Date) async throws -> [ChronicleItem] {
        try await ChronicleService(store: store).feed(now: date, timeZone: utc).flatMap(\.items)
    }

    @Test func questRowShowsGrantsAndManaThenCancelled() async throws {
        try await setUp()
        let quest = try await QuestService(store: store).create(QuestDraft(title: "Сдать отчёт"), now: now, timeZone: utc)
        _ = try await CompletionService(store: store).complete(questId: quest.id, now: now + 60, timeZone: utc)
        var row = try #require(try await items(at: now + 120).first { $0.title == "Сдать отчёт" })
        #expect(row.category == .quests && !row.isCancelled)
        #expect(row.changes.contains(.mp(-4)))
        #expect(row.changes.contains { if case let .xp(label, amount) = $0 { label == "FOC" && amount == .xp(5) } else { false } })

        try await CompletionService(store: store).undo(questId: quest.id, now: now + 180)
        row = try #require(try await items(at: now + 240).first { $0.title == "Сдать отчёт" })
        #expect(row.isCancelled && row.changes.isEmpty && row.note == ChronicleService.cancelledNote)
    }

    @Test func milestonesFirstReachAndCancelledByUndo() async throws {
        try await setUp()
        let service = ChronicleService(store: store)
        try await service.syncMilestones(now: now + 1, timeZone: utc)
        // Стартовый бонус: INT уровень 1.
        #expect(try await store.chronicleEntries().map(\.key).contains("level:INT:1"))

        // FOC: 4 квеста по 5 XP = 20 XP → уровень 1.
        var ids: [UUID] = []
        for index in 0..<4 {
            let quest = try await QuestService(store: store).create(QuestDraft(title: "К\(index)"), now: now, timeZone: utc)
            _ = try await CompletionService(store: store).complete(questId: quest.id, now: now + Double(10 + index), timeZone: utc)
            ids.append(quest.id)
        }
        try await service.syncMilestones(now: now + 60, timeZone: utc)
        try await service.syncMilestones(now: now + 61, timeZone: utc)
        var focus = try await store.chronicleEntries().filter { $0.key == "level:FOC:1" }
        #expect(focus.count == 1 && focus[0].isActive)

        try await CompletionService(store: store).undo(questId: ids[3], now: now + 70)
        try await service.syncMilestones(now: now + 80, timeZone: utc)
        focus = try await store.chronicleEntries().filter { $0.key == "level:FOC:1" }
        #expect(focus.count == 1 && focus[0].cancelledAt != nil)
        let row = try #require(try await items(at: now + 90).first { $0.title == "FOC · уровень 1" })
        #expect(row.isCancelled && row.isMilestone)
    }

    @Test func epicCompletionIsMilestone() async throws {
        try await setUp()
        let epic = try await EpicService(store: store).create(title: "Полумарафон", details: "", deadline: nil,
                                                              steps: [QuestDraft(title: "Шаг")], now: now, timeZone: utc)
        let step = try #require(try await store.allQuests().first { $0.epicId == epic.id })
        _ = try await CompletionService(store: store).complete(questId: step.id, now: now + 30, timeZone: utc)
        try await EpicService(store: store).complete(epicId: epic.id, now: now + 60)
        let stepRow = try #require(try await items(at: now + 61).first { $0.title == "Шаг" })
        #expect(stepRow.detail == "Шаг 1 из 1 · Полумарафон")
        try await ChronicleService(store: store).syncMilestones(now: now + 61, timeZone: utc)
        let row = try #require(try await items(at: now + 62).first { $0.title == "Epic завершён · «Полумарафон»" })
        #expect(row.category == .quests && row.isMilestone)
        try await EpicService(store: store).reopen(epicId: epic.id)
        try await ChronicleService(store: store).syncMilestones(now: now + 70, timeZone: utc)
        #expect(try await items(at: now + 71).first { $0.title == "Epic завершён · «Полумарафон»" }?.isCancelled == true)
    }

    @Test func neutralNightAppearsInHealth() async throws {
        try await setUp()
        let morning = now + 14 * 3600
        let night = try #require(try await items(at: morning).first { $0.category == .health })
        #expect(night.title == "Сон: нет данных · ночь нейтральная")
    }
}
