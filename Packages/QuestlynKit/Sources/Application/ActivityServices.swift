import Foundation
import Domain

/// Черновик Activity из экранов «Новая активность» и «Выполнить с активностью».
public struct ActivityDraft: Sendable, Equatable {
    public var templateId: String
    public var durationMinutes: Int
    public var skillId: UUID?
    public var startedAt: Date

    public init(templateId: String, durationMinutes: Int, skillId: UUID? = nil, startedAt: Date) {
        self.templateId = templateId
        self.durationMinutes = durationMinutes
        self.skillId = skillId
        self.startedAt = startedAt
    }
}

/// Итог записи активности — для подсказок и экрана награды.
public struct ActivityReport: Sendable, Equatable {
    public var activity: Activity
    public var grants: [ProgressGrant]
    /// Сколько минут не вошло в XP из-за предела 3 ч.
    public var overCapMinutes: Int { activity.durationMinutes - activity.creditedMinutes }
}

/// Запись Activity (BACKLOG 3.3, 07 раздел 2). MP не тратит (H7).
public struct ActivityService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    /// Строит активность и её начисления с учётом предела дня, ничего не сохраняя.
    func prepare(_ draft: ActivityDraft, now: Date, timeZone: TimeZone, questCompletionId: UUID? = nil) async throws -> (Activity, [ProgressGrant]) {
        guard let template = ActivityTemplate.template(id: draft.templateId) else { throw QuestlynError.unknownActivityType }
        guard (1...ActivityRules.maxDurationMinutes).contains(draft.durationMinutes) else { throw QuestlynError.invalidDuration }
        let date = LocalDate(draft.startedAt, timeZone: timeZone)
        guard date <= LocalDate(now, timeZone: timeZone) else { throw QuestlynError.cannotMarkDate }
        guard let hero = try await store.currentHero() else { throw QuestlynError.heroNotFound }
        let professions = try await store.professions(heroId: hero.id)
        var skill: Skill?
        if let skillId = draft.skillId {
            guard let found = try await store.skills().first(where: { $0.id == skillId }) else { throw QuestlynError.skillNotFound }
            skill = found
        }
        let profession = professions.first { $0.id == skill?.professionId }
        let snapshot = profession.map { ClassRules.snapshot(skillProfession: $0, activeProfessions: professions) } ?? .empty
        let already = try await store.activities(from: date, through: date)
            .filter { $0.templateId == template.id }.reduce(0) { $0 + $1.creditedMinutes }
        let credited = ActivityRules.creditedMinutes(duration: draft.durationMinutes, alreadyCreditedToday: already)
        let activity = Activity(templateId: template.id, skillId: skill?.id, durationMinutes: draft.durationMinutes, creditedMinutes: credited,
                                localDate: date, startedAt: draft.startedAt, timezoneId: timeZone.identifier,
                                questCompletionId: questCompletionId, classSnapshot: snapshot)
        let grants = GrantCalculator.activityGrants(activityId: activity.id, template: template, creditedMinutes: credited, skill: skill,
                                                    skillProfessionTitle: profession?.title, snapshot: snapshot,
                                                    createdAt: now, effectiveDate: date)
        return (activity, grants)
    }

    @discardableResult
    public func record(_ draft: ActivityDraft, now: Date, timeZone: TimeZone) async throws -> ActivityReport {
        let (activity, grants) = try await prepare(draft, now: now, timeZone: timeZone)
        try await store.record(activity, grants: grants)
        return ActivityReport(activity: activity, grants: grants)
    }

    public func delete(activityId: UUID, now: Date) async throws {
        try await store.deleteActivity(id: activityId, at: now)
    }
}

extension CompletionService {
    /// «Выполнить с активностью» (макет 8.2): навык и атрибуты — от Activity, от квеста — только FOC (07, без двойного начисления).
    public func complete(questId: UUID, with draft: ActivityDraft, now: Date, timeZone: TimeZone) async throws -> CompletionReport {
        try await complete(questId: questId, now: now, timeZone: timeZone, activity: draft)
    }
}
