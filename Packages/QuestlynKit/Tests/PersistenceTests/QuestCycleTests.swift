import Foundation
import Testing
import Domain
import Application
@testable import Persistence

/// Сценарий этапа 1: онбординг → навык → квест → выполнение → отмена → перезапуск.
struct QuestCycleTests {
    let store: GRDBStore
    let moscow = TimeZone(identifier: "Europe/Moscow")!
    /// 2026-11-10 12:00 по Москве.
    let now = Date(timeIntervalSince1970: 1_794_301_200)
    var today: LocalDate { LocalDate(now, timeZone: moscow) }

    init() throws { store = GRDBStore(try AppDatabase.inMemory()) }

    func onboard() async throws -> (engineer: Profession, athlete: Profession) {
        try await OnboardingService(store: store).start(
            heroName: "  Арин ", catalogItemIds: ["software-engineer", "athlete"], classTitle: "Инженер-атлет", now: now
        )
        let hero = try #require(try await store.currentHero())
        let professions = try await store.professions(heroId: hero.id)
        return (professions[0], professions[1])
    }

    @Test func onboardingCreatesHeroWithOrderedProfessions() async throws {
        let (engineer, athlete) = try await onboard()
        let hero = try #require(try await store.currentHero())
        #expect(hero.name == "Арин")
        #expect(engineer.slot == 1 && engineer.title == "Инженер-программист")
        #expect(engineer.attributes == [.intelligence, .mentality, .charisma])
        #expect(athlete.slot == 2 && athlete.catalogVersion == ProfessionCatalog.version)
        await #expect(throws: QuestlynError.heroAlreadyExists) {
            try await OnboardingService(store: store).start(heroName: "Ещё", catalogItemIds: ["athlete"], classTitle: "", now: now)
        }
    }

    @Test func onboardingValidates() async throws {
        let service = OnboardingService(store: store)
        await #expect(throws: QuestlynError.emptyName) {
            try await service.start(heroName: " ", catalogItemIds: ["athlete"], classTitle: "", now: now)
        }
        await #expect(throws: QuestlynError.invalidProfessionCount) {
            try await service.start(heroName: "Г", catalogItemIds: [], classTitle: "", now: now)
        }
        await #expect(throws: QuestlynError.invalidProfessionCount) {
            try await service.start(heroName: "Г", catalogItemIds: ["athlete", "athlete"], classTitle: "", now: now)
        }
    }

    @Test func completeUndoAndCompleteAgain() async throws {
        let (engineer, _) = try await onboard()
        let skill = try await SkillService(store: store).create(title: "Отчётность", professionId: engineer.id, now: now)
        let quest = try await QuestService(store: store).create(
            QuestDraft(title: "Сдать отчёт", skillId: skill.id, dueDate: today), now: now, timeZone: moscow
        )
        let completions = CompletionService(store: store)

        let report = try await completions.complete(questId: quest.id, now: now, timeZone: moscow)
        #expect(report.after.xp(.focus) == .xp(5))
        #expect(report.after.xp(.intelligence) == CentiXP(500))
        #expect(report.after.xp(.mentality) == CentiXP(375))
        #expect(report.after.xp(.charisma) == CentiXP(200))
        #expect(report.after.skillXP[skill.id] == .xp(10))
        #expect(report.before.xp(.focus) == .zero)
        #expect(report.completion.classSnapshot.entries.map(\.multiplierInQuarters) == [4, 5, 4])

        // Повторная отметка ничего не добавляет.
        await #expect(throws: QuestlynError.alreadyCompleted) {
            try await completions.complete(questId: quest.id, now: now, timeZone: moscow)
        }
        #expect(try await store.allGrants().count == 5)

        // Отмена удаляет начисления.
        try await completions.undo(questId: quest.id, now: now)
        #expect(try await store.allGrants().isEmpty)
        #expect(try await store.activeCompletion(questId: quest.id) == nil)

        // Снова выполнить — начисление одно.
        _ = try await completions.complete(questId: quest.id, now: now, timeZone: moscow)
        #expect(try await store.allGrants().count == 5)
    }

    @Test func questWithoutSkillGivesFocusOnly() async throws {
        _ = try await onboard()
        let quest = try await QuestService(store: store).create(QuestDraft(title: "Стоматолог", priority: .high), now: now, timeZone: moscow)
        let report = try await CompletionService(store: store).complete(questId: quest.id, now: now, timeZone: moscow)
        #expect(report.grants.count == 1)
        #expect(report.after.xp(.focus) == CentiXP(750))
    }

    @Test func levelUpIsReported() async throws {
        _ = try await onboard()
        let service = QuestService(store: store)
        let completions = CompletionService(store: store)
        var last: CompletionReport?
        for i in 1...4 {
            let quest = try await service.create(QuestDraft(title: "Квест \(i)"), now: now, timeZone: moscow)
            last = try await completions.complete(questId: quest.id, now: now, timeZone: moscow)
        }
        // 4 × 5 FOC = 20 XP → уровень 1.
        let report = try #require(last)
        #expect(report.levelUps.map(\.attribute) == [.focus])
        #expect(report.after.level(.focus) == 1)
    }

    @Test func todaySections() async throws {
        _ = try await onboard()
        let quests = QuestService(store: store)
        let yesterday = LocalDate(year: 2026, month: 11, day: 9)
        let tomorrow = LocalDate(year: 2026, month: 11, day: 11)
        _ = try await quests.create(QuestDraft(title: "Без даты"), now: now, timeZone: moscow)
        _ = try await quests.create(QuestDraft(title: "Вечер", dueDate: today, dueTime: LocalTime(hour: 18, minute: 0)), now: now, timeZone: moscow)
        _ = try await quests.create(QuestDraft(title: "Утро", dueDate: today, dueTime: LocalTime(hour: 9, minute: 0)), now: now, timeZone: moscow)
        _ = try await quests.create(QuestDraft(title: "Вчера", dueDate: yesterday), now: now, timeZone: moscow)
        _ = try await quests.create(QuestDraft(title: "Завтра", dueDate: tomorrow), now: now, timeZone: moscow)

        let overview = try await TodayService(store: store).overview(now: now, timeZone: moscow)
        #expect(overview.items.map(\.quest.title) == ["Вчера", "Утро", "Вечер", "Без даты"])
        #expect(overview.items.map(\.section) == [.overdue, .today, .today, .undated])
    }

    @Test func completedYesterdayIsHiddenToday() async throws {
        _ = try await onboard()
        let quest = try await QuestService(store: store).create(QuestDraft(title: "Без даты"), now: now, timeZone: moscow)
        _ = try await CompletionService(store: store).complete(questId: quest.id, now: now - 86_400, timeZone: moscow)
        let overview = try await TodayService(store: store).overview(now: now, timeZone: moscow)
        #expect(overview.items.isEmpty)
    }

    @Test func timeWithoutDateIsRejected() async throws {
        await #expect(throws: QuestlynError.timeWithoutDate) {
            try await QuestService(store: store).create(QuestDraft(title: "Т", dueTime: LocalTime(hour: 9, minute: 0)), now: now, timeZone: moscow)
        }
    }
}

/// Данные переживают перезапуск: БД на диске открывается заново (BACKLOG 1.10).
struct RelaunchTests {
    @Test func dataSurvivesReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "questlyn-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_794_301_200)
        let tz = TimeZone(identifier: "UTC")!

        do {
            let store = GRDBStore(try AppDatabase.onDisk(at: directory))
            try await OnboardingService(store: store).start(heroName: "Г", catalogItemIds: ["athlete"], classTitle: "Атлет", now: now)
            let quest = try await QuestService(store: store).create(QuestDraft(title: "Пробежка"), now: now, timeZone: tz)
            _ = try await CompletionService(store: store).complete(questId: quest.id, now: now, timeZone: tz)
        }

        let reopened = GRDBStore(try AppDatabase.onDisk(at: directory))
        #expect(try await reopened.currentHero()?.name == "Г")
        #expect(try await reopened.allGrants().count == 1)
        let overview = try await TodayService(store: reopened).overview(now: now, timeZone: tz)
        #expect(overview.items.first?.isCompleted == true)
    }
}
