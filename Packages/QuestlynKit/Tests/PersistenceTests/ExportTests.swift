import Foundation
import Testing
import Domain
import Application
@testable import Persistence

/// 7.2: экспорт всех фактов в JSON.
struct ExportTests {
    let now = ISO8601DateFormatter().date(from: "2026-11-10T18:00:00Z")!

    @Test func exportContainsFactsAndDecodes() async throws {
        let store = GRDBStore(try AppDatabase.inMemory())
        try await OnboardingService(store: store).start(heroName: "Арин", catalogItemIds: ["software-engineer"], classTitle: "К", now: now, timeZone: .gmt)
        let quest = try await QuestService(store: store).create(QuestDraft(title: "Отчёт"), now: now, timeZone: .gmt)
        _ = try await CompletionService(store: store).complete(questId: quest.id, now: now + 60, timeZone: .gmt)
        try await WellbeingService(store: store).checkIn(CheckInDraft(mood: .good), now: now + 120, timeZone: .gmt)

        let data = try await ExportService(store: store).json(now: now + 180)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(QuestlynExport.self, from: data)
        #expect(export.hero?.name == "Арин" && export.quests.count == 1 && export.completions.count == 1)
        #expect(export.moods.count == 1 && !export.grants.isEmpty && export.formatVersion == 1)
        #expect(String(decoding: data, as: UTF8.self).contains("\"ruleVersion\" : \"1.1\""))
    }
}
