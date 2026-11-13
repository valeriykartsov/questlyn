import Foundation
import Testing
import Domain
import Application
@testable import Persistence

/// Этап 8C: полезные действия, удаление и переименование навыка, недельные отметки за любой день, порядок привычек.
struct Stage8CTests {
    let store: GRDBStore
    let utc = TimeZone(identifier: "UTC")!
    /// Вторник, 10 ноября 2026.
    let now = ISO8601DateFormatter().date(from: "2026-11-10T18:00:00Z")!

    init() throws { store = GRDBStore(try AppDatabase.inMemory()) }

    func onboard(at date: Date) async throws -> [Profession] {
        try await OnboardingService(store: store).start(heroName: "Арин", catalogItemIds: ["software-engineer", "athlete"], classTitle: "К", now: date, timeZone: utc)
        let hero = try #require(try await store.currentHero())
        return try await store.professions(heroId: hero.id)
    }

    func vitals(at date: Date) async throws -> VitalsState {
        try #require(try await TodayService(store: store).overview(now: date, timeZone: utc).vitals)
    }

    // MARK: Полезные действия (08, 2.3)

    @Test func benefitsHealThreePercentUpToTenPerDay() async throws {
        _ = try await onboard(at: now - 3600)
        // Курение ×15 = −15% (−1% за отметку с 13.11.2026), затем 4 полезных: +3% ×3 и +1% до предела 10%.
        try await WellbeingService(store: store).checkIn(CheckInDraft(counts: [.smoking: 15]), now: now, timeZone: utc)
        let damaged = try await vitals(at: now + 1).hp
        let report = try await WellbeingService(store: store)
            .checkIn(CheckInDraft(benefits: [.water: 1, .stretching: 2, .custom: 1], customBenefitTitle: "Баня"), now: now + 60, timeZone: utc)
        #expect(report.benefits.count == 4 && report.benefits.last?.title == "Баня")
        let healed = try await vitals(at: now + 120).hp
        #expect(abs(healed - damaged - 105 * 0.10) < 0.01)
        // Удаление отметки пересчитывает HP.
        try await WellbeingService(store: store).deleteBenefit(id: report.benefits[0].id, now: now + 180)
        #expect(abs(try await vitals(at: now + 240).hp - (damaged + 105 * 0.09)) < 0.01)
        let feed = try await ChronicleService(store: store).feed(now: now + 300, timeZone: utc).flatMap(\.items)
        #expect(feed.contains { $0.title == "Полезное: Баня" && !$0.isCancelled })
        #expect(feed.contains { $0.title == "Полезное: Вода 2 л" && $0.isCancelled })
    }

    @Test func customBenefitNeedsTitle() async throws {
        _ = try await onboard(at: now)
        await #expect(throws: QuestlynError.emptyName) {
            try await WellbeingService(store: store).checkIn(CheckInDraft(benefits: [.custom: 1]), now: now, timeZone: utc)
        }
    }

    // MARK: Навыки (8C.6)

    @Test func deletingSkillKeepsHistoryAndClearsOpenLinks() async throws {
        let professions = try await onboard(at: now)
        let skills = SkillService(store: store)
        let run = try await skills.create(title: "Бег", professionId: professions[1].id, now: now)
        try await skills.rename(skillId: run.id, title: " Бег трусцой ")
        try await skills.linkActivity(templateId: "cardio", skillId: run.id)
        let quests = QuestService(store: store)
        let open = try await quests.create(QuestDraft(title: "Пробежка", skillId: run.id), now: now, timeZone: utc)
        let done = try await quests.create(QuestDraft(title: "Забег", skillId: run.id), now: now, timeZone: utc)
        _ = try await CompletionService(store: store).complete(questId: done.id, now: now + 60, timeZone: utc)
        let habit = try await HabitService(store: store).create(HabitDraft(kind: .daily, title: "Трусца", skillId: run.id), now: now, timeZone: utc)
        let xpBefore = try await TodayService(store: store).overview(now: now + 90, timeZone: utc).progress.skillXP[run.id]

        try await skills.delete(skillId: run.id, now: now + 120)
        let stored = try #require(try await store.skills().first { $0.id == run.id })
        #expect(stored.title == "Бег трусцой" && stored.deletedAt != nil && !stored.isActive && stored.activityTemplateId == nil)
        #expect(try await store.quest(id: open.id)?.skillId == nil)
        #expect(try await store.quest(id: done.id)?.skillId == run.id)
        #expect(try await store.habit(id: habit.id)?.skillId == nil)
        let overview = try await TodayService(store: store).overview(now: now + 180, timeZone: utc)
        #expect(!overview.skills.contains { $0.id == run.id })
        #expect(overview.progress.skillXP[run.id] == xpBefore)
        await #expect(throws: QuestlynError.skillNotFound) { try await skills.rename(skillId: run.id, title: "x") }
    }

    @Test func returningProfessionDoesNotRestoreDeletedSkill() async throws {
        let professions = try await onboard(at: now)
        let skill = try await SkillService(store: store).create(title: "Жим", professionId: professions[1].id, now: now)
        try await SkillService(store: store).delete(skillId: skill.id, now: now + 1)
        try await store.applyProfessions(professions)
        #expect(try await store.skills().first { $0.id == skill.id }?.isActive == false)
    }

    // MARK: Недельные отметки (8C.8) и порядок привычек (8C.5)

    @Test func weeklyCanBeMarkedForAnyDayOfCurrentWeek() async throws {
        let monday = ISO8601DateFormatter().date(from: "2026-11-09T08:00:00Z")!
        _ = try await onboard(at: monday)
        let habits = HabitService(store: store)
        let weekly = try await habits.create(HabitDraft(kind: .weekly, title: "Бег", targetPerWeek: 3), now: monday, timeZone: utc)
        let daily = try await habits.create(HabitDraft(kind: .daily, title: "Зарядка"), now: monday, timeZone: utc)
        let thursday = ISO8601DateFormatter().date(from: "2026-11-12T09:00:00Z")!
        let mark = HabitMarkService(store: store)
        _ = try await mark.mark(habitId: weekly.id, on: LocalDate(monday, timeZone: utc), now: thursday, timeZone: utc)
        await #expect(throws: QuestlynError.cannotMarkDate) {
            _ = try await mark.mark(habitId: daily.id, on: LocalDate(monday, timeZone: utc), now: thursday, timeZone: utc)
        }
        await #expect(throws: QuestlynError.cannotMarkDate) {
            _ = try await mark.mark(habitId: weekly.id, on: LocalDate(thursday, timeZone: utc).adding(days: 1), now: thursday, timeZone: utc)
        }
    }

    @Test func habitsAreSortedByTimeWithUntimedLast() async throws {
        _ = try await onboard(at: now)
        let habits = HabitService(store: store)
        _ = try await habits.create(HabitDraft(kind: .daily, title: "Без времени"), now: now, timeZone: utc)
        _ = try await habits.create(HabitDraft(kind: .daily, title: "Вечер", time: LocalTime(hour: 21, minute: 0)), now: now + 1, timeZone: utc)
        _ = try await habits.create(HabitDraft(kind: .daily, title: "Утро", time: LocalTime(hour: 7, minute: 30)), now: now + 2, timeZone: utc)
        let order = try await TodayService(store: store).overview(now: now + 10, timeZone: utc).habits.map(\.habit.title)
        #expect(order == ["Утро", "Вечер", "Без времени"])
    }
}

/// Этап 9: длительность квеста сохраняется и проверяется.
struct Stage9Tests {
    @Test func questDurationRoundTripAndValidation() async throws {
        let store = GRDBStore(try AppDatabase.inMemory())
        let utc = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-11-10T18:00:00Z")!
        let quests = QuestService(store: store)
        let quest = try await quests.create(QuestDraft(title: "Слайды", dueDate: LocalDate(now, timeZone: utc),
                                                       dueTime: LocalTime(hour: 15, minute: 0), durationMinutes: 120), now: now, timeZone: utc)
        #expect(try await store.quest(id: quest.id)?.durationMinutes == 120)
        var draft = QuestDraft(quest: quest)
        draft.durationMinutes = 45
        await #expect(throws: QuestlynError.invalidDuration) { try await quests.update(questId: quest.id, with: draft) }
        draft.durationMinutes = nil
        try await quests.update(questId: quest.id, with: draft)
        #expect(try await store.quest(id: quest.id)?.durationMinutes == nil)
    }
}
