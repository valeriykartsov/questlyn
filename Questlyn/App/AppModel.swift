import Foundation
import Observation
import Domain
import Application

/// Состояние приложения для Presentation. Все изменения идут через use cases Application.
@Observable
final class AppModel {
    private(set) var overview: TodayOverview?
    private(set) var isLoaded = false
    var errorMessage: String?

    private let store: any QuestlynStore
    private var timeZone: TimeZone { .current }

    init(store: any QuestlynStore) {
        self.store = store
    }

    var hero: Hero? { overview?.hero }
    var progress: HeroProgress { overview?.progress ?? HeroProgress(grants: [], classAttributes: []) }
    var activeProfessions: [Profession] { overview?.professions.filter(\.isActive) ?? [] }
    var skills: [Skill] { overview?.skills ?? [] }

    func skill(id: UUID?) -> Skill? { skills.first { $0.id == id } }
    func profession(id: UUID?) -> Profession? { overview?.professions.first { $0.id == id } }

    func reload() async {
        await run { [self] in
            overview = try await TodayService(store: store).overview(now: .now, timeZone: timeZone)
        }
        isLoaded = true
    }

    func startAdventure(name: String, appearance: HeroAppearance, professions: [ProfessionChoice], classTitle: String) async -> Bool {
        await run { [self] in
            try await OnboardingService(store: store).start(heroName: name, appearance: appearance, professions: professions,
                                                            classTitle: classTitle, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    /// Цвет акцента одежды героя — по основной профессии (слот 1).
    var heroAccent: UInt32 { HeroAccent.hex(catalogItemId: activeProfessions.min { $0.slot < $1.slot }?.catalogItemId) }

    func updateAppearance(_ appearance: HeroAppearance) async -> Bool {
        await run { [self] in
            try await HeroService(store: store).updateAppearance(appearance)
            await reload()
        }
    }

    func updateProfessions(_ professions: [ProfessionChoice], classTitle: String) async -> Bool {
        await run { [self] in
            try await ProfessionService(store: store).update(professions: professions, classTitle: classTitle, now: .now)
            await reload()
        }
    }

    func createSkill(title: String, professionId: UUID, mastery: Int? = nil) async -> Skill? {
        var created: Skill?
        await run { [self] in
            created = try await SkillService(store: store).create(title: title, professionId: professionId, mastery: mastery, now: .now)
            await reload()
        }
        return created
    }

    func assessMastery(skillId: UUID, value: Int) async {
        await run { [self] in
            try await SkillService(store: store).assess(skillId: skillId, mastery: value, now: .now)
            await reload()
        }
    }

    func mastery(skillId: UUID) -> Int? { overview?.masteries[skillId] }

    func createQuest(_ draft: QuestDraft) async -> Bool {
        await run { [self] in
            try await QuestService(store: store).create(draft, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    func complete(questId: UUID) async -> CompletionReport? {
        var report: CompletionReport?
        await run { [self] in
            report = try await CompletionService(store: store).complete(questId: questId, now: .now, timeZone: timeZone)
            await reload()
        }
        return report
    }

    func updateQuest(_ questId: UUID, with draft: QuestDraft) async -> Bool {
        await run { [self] in
            try await QuestService(store: store).update(questId: questId, with: draft)
            await reload()
        }
    }

    // MARK: Привычки

    var today: LocalDate { overview?.date ?? LocalDate(.now, timeZone: timeZone) }
    var habits: [HabitStatus] { overview?.habits ?? [] }
    func habit(id: UUID) -> HabitStatus? { habits.first { $0.id == id } }

    func createHabit(_ draft: HabitDraft) async -> Bool {
        await run { [self] in
            try await HabitService(store: store).create(draft, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    func updateHabit(_ habitId: UUID, with draft: HabitDraft) async -> Bool {
        await run { [self] in
            try await HabitService(store: store).update(habitId: habitId, with: draft)
            await reload()
        }
    }

    func markHabit(_ habitId: UUID, on date: LocalDate) async {
        await run { [self] in
            try await HabitMarkService(store: store).mark(habitId: habitId, on: date, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    func unmarkHabit(_ habitId: UUID, on date: LocalDate) async {
        await run { [self] in
            try await HabitMarkService(store: store).unmark(habitId: habitId, on: date, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    // MARK: Activity

    var activities: [Activity] { overview?.activities ?? [] }

    func recordActivity(_ draft: ActivityDraft) async -> ActivityReport? {
        var report: ActivityReport?
        await run { [self] in
            report = try await ActivityService(store: store).record(draft, now: .now, timeZone: timeZone)
            await reload()
        }
        return report
    }

    func deleteActivity(_ id: UUID) async {
        await run { [self] in
            try await ActivityService(store: store).delete(activityId: id, now: .now)
            await reload()
        }
    }

    func complete(questId: UUID, with draft: ActivityDraft) async -> CompletionReport? {
        var report: CompletionReport?
        await run { [self] in
            report = try await CompletionService(store: store).complete(questId: questId, with: draft, now: .now, timeZone: timeZone)
            await reload()
        }
        return report
    }

    /// Предпросмотр начислений Activity по тем же правилам, с учётом предела дня (только для сегодняшних записей).
    func previewActivity(_ draft: ActivityDraft) -> (credited: Int, grants: [ProgressGrant]) {
        guard let template = ActivityTemplate.template(id: draft.templateId) else { return (0, []) }
        let date = LocalDate(draft.startedAt, timeZone: timeZone)
        let already = date == today ? activities.filter { $0.templateId == template.id }.reduce(0) { $0 + $1.creditedMinutes } : 0
        let credited = ActivityRules.creditedMinutes(duration: draft.durationMinutes, alreadyCreditedToday: already)
        let skill = skill(id: draft.skillId)
        let profession = profession(id: skill?.professionId)
        let snapshot = profession.map { ClassRules.snapshot(skillProfession: $0, activeProfessions: activeProfessions) } ?? .empty
        let grants = GrantCalculator.activityGrants(activityId: UUID(), template: template, creditedMinutes: credited, skill: skill,
                                                    skillProfessionTitle: profession?.title, snapshot: snapshot, createdAt: .now, effectiveDate: date)
        return (credited, grants)
    }

    /// «Бег +6,67 · STR +3,33 · …»
    func grantSummary(_ grants: [ProgressGrant]) -> String {
        grants.map { grant in
            switch grant.target {
            case .attribute(let a): "\(a.code) \(Format.signedXP(grant.amount))"
            case .skill(let id): "«\(skill(id: id)?.title ?? "Навык")» \(Format.signedXP(grant.amount))"
            }
        }
        .joined(separator: " · ")
    }

    // MARK: Сброс

    /// Удалить всё и вернуться к онбордингу.
    func resetEverything(confirmation: String) async -> Bool {
        await run { [self] in
            try await ResetService(store: store).resetEverything(confirmation: confirmation)
            await reload()
        }
    }

    // MARK: Epic

    var epics: [EpicStatus] { overview?.epics ?? [] }
    func epic(id: UUID?) -> EpicStatus? { epics.first { $0.id == id } }

    func createEpic(title: String, details: String, deadline: LocalDate?, steps: [QuestDraft]) async -> Bool {
        await run { [self] in
            try await EpicService(store: store).create(title: title, details: details, deadline: deadline, steps: steps, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    func completeEpic(_ epicId: UUID) async {
        await run { [self] in
            try await EpicService(store: store).complete(epicId: epicId, now: .now)
            await reload()
        }
    }

    func reopenEpic(_ epicId: UUID) async {
        await run { [self] in
            try await EpicService(store: store).reopen(epicId: epicId)
            await reload()
        }
    }

    /// Квест из журнала (любой, не только на сегодня).
    func questItem(id: UUID) -> TodayItem? { overview?.journal.first { $0.quest.id == id } }

    func undo(questId: UUID) async {
        await run { [self] in
            try await CompletionService(store: store).undo(questId: questId, now: .now)
            await reload()
        }
    }

    @discardableResult
    private func run(_ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            return true
        } catch let error as QuestlynError {
            errorMessage = error.description
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }
}
