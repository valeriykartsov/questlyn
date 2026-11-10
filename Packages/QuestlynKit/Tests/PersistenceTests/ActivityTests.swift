import Foundation
import Testing
import Domain
import Application
@testable import Persistence

/// Этап 3.3: запись Activity, предел 3 ч, «Выполнить с активностью», отмена.
struct ActivityFlowTests {
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

    func activityGrants() async throws -> [ProgressGrant] { try await store.allGrants().filter { $0.sourceType == .activity } }

    @Test func capAcrossActivitiesOfSameType() async throws {
        _ = try await setUp()
        let service = ActivityService(store: store)
        let first = try await service.record(ActivityDraft(templateId: "deep-work", durationMinutes: 150, startedAt: now), now: now, timeZone: utc)
        #expect(first.activity.creditedMinutes == 150 && first.overCapMinutes == 0)
        let second = try await service.record(ActivityDraft(templateId: "deep-work", durationMinutes: 60, startedAt: now), now: now, timeZone: utc)
        #expect(second.activity.creditedMinutes == 30 && second.overCapMinutes == 30)
        // Другой тип — свой предел.
        let walk = try await service.record(ActivityDraft(templateId: "walk", durationMinutes: 60, startedAt: now), now: now, timeZone: utc)
        #expect(walk.activity.creditedMinutes == 60)
        // Работа в фокусе: 180 мин = 30 XP поровну на INT и MNT.
        let progress = HeroProgress(grants: try await activityGrants(), classAttributes: [])
        #expect(progress.xp(.intelligence) == .xp(15) && progress.xp(.mentality) == .xp(15))
        #expect(progress.xp(.endurance) == .xp(10))
        #expect(progress.xp(.focus) == .zero)
    }

    @Test func deleteRemovesGrants() async throws {
        let skill = try await setUp()
        let report = try await ActivityService(store: store).record(
            ActivityDraft(templateId: "cardio", durationMinutes: 40, skillId: skill.id, startedAt: now), now: now, timeZone: utc)
        #expect(report.grants.map(\.amount.value) == [667, 333, 200, 167])
        try await ActivityService(store: store).delete(activityId: report.activity.id, now: now)
        #expect(try await activityGrants().isEmpty)
        #expect(try await store.activities(from: report.activity.localDate, through: report.activity.localDate).isEmpty)
    }

    @Test func completeWithActivityGivesQuestOnlyFocus() async throws {
        let skill = try await setUp()
        let quest = try await QuestService(store: store).create(QuestDraft(title: "Пробежать 10 км", skillId: skill.id), now: now, timeZone: utc)
        let report = try await CompletionService(store: store).complete(
            questId: quest.id, with: ActivityDraft(templateId: "cardio", durationMinutes: 55, skillId: skill.id, startedAt: now), now: now, timeZone: utc)
        let questGrants = report.grants.filter { $0.sourceType == .questCompletion }
        #expect(questGrants.map(\.target) == [.attribute(.focus)])
        // Мокап 8.2: «Бег» +9,17 · STR +4,58 · END +2,75 · MNT +2,29.
        #expect(report.grants.filter { $0.sourceType == .activity }.map(\.amount.value) == [917, 458, 275, 229])
        #expect(report.after.skillXP[skill.id] == CentiXP(917))

        // Отмена выполнения убирает и активность.
        try await CompletionService(store: store).undo(questId: quest.id, now: now)
        #expect(try await activityGrants().isEmpty)
        #expect(try await store.activities(from: report.completion.localDate, through: report.completion.localDate).isEmpty)
    }

    @Test func futureActivityAndBadDurationRejected() async throws {
        _ = try await setUp()
        let service = ActivityService(store: store)
        await #expect(throws: QuestlynError.invalidDuration) {
            try await service.record(ActivityDraft(templateId: "walk", durationMinutes: 0, startedAt: now), now: now, timeZone: utc)
        }
        await #expect(throws: QuestlynError.cannotMarkDate) {
            try await service.record(ActivityDraft(templateId: "walk", durationMinutes: 30, startedAt: now + 86_400 * 2), now: now, timeZone: utc)
        }
        await #expect(throws: QuestlynError.unknownActivityType) {
            try await service.record(ActivityDraft(templateId: "dex", durationMinutes: 30, startedAt: now), now: now, timeZone: utc)
        }
    }
}
