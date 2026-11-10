import Foundation
import Domain

private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

/// Профессия, выбранная в онбординге или при смене: из каталога или своя; атрибуты можно переопределить.
public struct ProfessionChoice: Sendable, Equatable {
    public var catalogItemId: String?
    public var title: String
    public var attributes: [Attribute]

    public init(catalogItemId: String? = nil, title: String, attributes: [Attribute]) {
        self.catalogItemId = catalogItemId
        self.title = title
        self.attributes = attributes
    }

    public static func catalog(_ id: String) -> ProfessionChoice? {
        ProfessionCatalog.item(id: id).map { ProfessionChoice(catalogItemId: $0.id, title: $0.title, attributes: $0.attributes) }
    }

    func validate() throws {
        guard !trimmed(title).isEmpty else { throw QuestlynError.emptyName }
        guard (1...3).contains(attributes.count), Set(attributes).count == attributes.count,
              attributes.allSatisfy(\.isSelectableForProfession) else { throw QuestlynError.invalidProfessionAttributes }
    }
}

/// Онбординг: герой и внешность → 1–3 профессии (каталог или своя) → атрибуты → класс (BACKLOG 1.2, 3.5).
/// Создаёт первую БД и стартовый бонус (02, 07).
public struct OnboardingService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    /// Короткая форма: профессии из каталога без правки атрибутов.
    @discardableResult
    public func start(heroName: String, catalogItemIds: [String], classTitle: String, now: Date,
                      timeZone: TimeZone = .current) async throws -> Hero {
        let choices = try catalogItemIds.map { id in
            guard let choice = ProfessionChoice.catalog(id) else { throw QuestlynError.unknownCatalogItem(id) }
            return choice
        }
        guard Set(catalogItemIds).count == catalogItemIds.count else { throw QuestlynError.invalidProfessionCount }
        return try await start(heroName: heroName, appearance: .default, professions: choices, classTitle: classTitle, now: now, timeZone: timeZone)
    }

    /// Порядок `professions` — порядок слотов: первая — основная профессия.
    @discardableResult
    public func start(heroName: String, appearance: HeroAppearance, professions choices: [ProfessionChoice],
                      classTitle: String, now: Date, timeZone: TimeZone) async throws -> Hero {
        let name = trimmed(heroName)
        guard !name.isEmpty else { throw QuestlynError.emptyName }
        guard (1...3).contains(choices.count) else { throw QuestlynError.invalidProfessionCount }
        try choices.forEach { try $0.validate() }
        guard try await store.currentHero() == nil else { throw QuestlynError.heroAlreadyExists }
        let title = trimmed(classTitle)
        let hero = Hero(name: name, classTitle: title.isEmpty ? choices.map(\.title).joined(separator: " · ") : title,
                        appearance: appearance, createdAt: now)
        let professions = choices.enumerated().map { index, choice in
            Profession(
                heroId: hero.id, title: trimmed(choice.title), slot: index + 1, attributes: choice.attributes,
                catalogItemId: choice.catalogItemId, catalogVersion: choice.catalogItemId == nil ? nil : ProfessionCatalog.version,
                createdAt: now
            )
        }
        let bonus = GrantCalculator.onboardingBonusGrants(heroId: hero.id, professions: professions, createdAt: now,
                                                          effectiveDate: LocalDate(now, timeZone: timeZone))
        try await store.createHero(hero, professions: professions, grants: bonus)
        return hero
    }
}

/// Смена профессий и названия класса (02): навыки убранной профессии становятся неактивными,
/// возвращённая профессия (тот же пункт каталога или то же своё название) получает навыки обратно.
/// Уровни атрибутов не меняются.
/// Внешность героя: волосы, кожа и образ (3.6). Меняется в настройках без последствий для прогресса.
public struct HeroService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    @discardableResult
    public func updateAppearance(_ appearance: HeroAppearance) async throws -> Hero {
        guard var hero = try await store.currentHero() else { throw QuestlynError.heroNotFound }
        hero.appearance = appearance
        try await store.save(hero)
        return hero
    }
}

public struct ProfessionService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    public func update(professions choices: [ProfessionChoice], classTitle: String, now: Date) async throws {
        guard var hero = try await store.currentHero() else { throw QuestlynError.heroNotFound }
        guard (1...3).contains(choices.count) else { throw QuestlynError.invalidProfessionCount }
        try choices.forEach { try $0.validate() }
        var existing = try await store.professions(heroId: hero.id)
        var result: [Profession] = []
        for (index, choice) in choices.enumerated() {
            let title = trimmed(choice.title)
            if let match = existing.firstIndex(where: { old in
                choice.catalogItemId.map { $0 == old.catalogItemId } ?? (old.catalogItemId == nil && old.title == title)
            }) {
                var profession = existing.remove(at: match)
                profession.slot = index + 1
                profession.attributes = choice.attributes
                profession.title = title
                profession.isActive = true
                result.append(profession)
            } else {
                result.append(Profession(
                    heroId: hero.id, title: title, slot: index + 1, attributes: choice.attributes,
                    catalogItemId: choice.catalogItemId, catalogVersion: choice.catalogItemId == nil ? nil : ProfessionCatalog.version,
                    createdAt: now
                ))
            }
        }
        for var removed in existing where removed.isActive {
            removed.isActive = false
            result.append(removed)
        }
        try await store.applyProfessions(result)
        let title = trimmed(classTitle)
        if !title.isEmpty, title != hero.classTitle {
            hero.classTitle = title
            try await store.save(hero)
        }
    }
}

/// Создание навыка в профессии (BACKLOG 1.3).
public struct SkillService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    @discardableResult
    public func create(title: String, professionId: UUID, mastery: Int? = nil, now: Date) async throws -> Skill {
        let name = trimmed(title)
        guard !name.isEmpty else { throw QuestlynError.emptyName }
        guard let hero = try await store.currentHero() else { throw QuestlynError.heroNotFound }
        guard try await store.professions(heroId: hero.id).contains(where: { $0.id == professionId && $0.isActive }) else {
            throw QuestlynError.professionNotFound
        }
        let skill = Skill(professionId: professionId, title: name, createdAt: now)
        try await store.save(skill)
        if let mastery { try await store.save(SkillMastery(skillId: skill.id, value: mastery, assessedAt: now)) }
        return skill
    }

    /// Мастерство 1–5 меняется только вручную и хранится как факт оценки (07, раздел 6).
    public func assess(skillId: UUID, mastery: Int, now: Date) async throws {
        guard try await store.skills().contains(where: { $0.id == skillId }) else { throw QuestlynError.skillNotFound }
        try await store.save(SkillMastery(skillId: skillId, value: mastery, assessedAt: now))
    }
}

/// Черновик квеста из формы «Новый квест».
public struct QuestDraft: Sendable, Equatable {
    public var title: String
    public var details: String
    public var priority: QuestPriority
    public var skillId: UUID?
    public var dueDate: LocalDate?
    public var dueTime: LocalTime?
    public var epicId: UUID?

    public init(title: String = "", details: String = "", priority: QuestPriority = .default,
                skillId: UUID? = nil, dueDate: LocalDate? = nil, dueTime: LocalTime? = nil, epicId: UUID? = nil) {
        self.epicId = epicId
        self.title = title
        self.details = details
        self.priority = priority
        self.skillId = skillId
        self.dueDate = dueDate
        self.dueTime = dueTime
    }
}

/// Создание квеста (BACKLOG 1.4). Создание не даёт XP.
public struct QuestService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    @discardableResult
    public func create(_ draft: QuestDraft, now: Date, timeZone: TimeZone) async throws -> Quest {
        let title = trimmed(draft.title)
        guard !title.isEmpty else { throw QuestlynError.emptyName }
        guard draft.dueTime == nil || draft.dueDate != nil else { throw QuestlynError.timeWithoutDate }
        if let skillId = draft.skillId, try await !store.skills().contains(where: { $0.id == skillId }) {
            throw QuestlynError.skillNotFound
        }
        if let epicId = draft.epicId, try await store.epic(id: epicId) == nil { throw QuestlynError.epicNotFound }
        let quest = try Self.makeQuest(draft, now: now, timeZone: timeZone)
        try await store.save(quest)
        return quest
    }

    static func makeQuest(_ draft: QuestDraft, now: Date, timeZone: TimeZone, epicId: UUID? = nil) throws -> Quest {
        let title = trimmed(draft.title)
        guard !title.isEmpty else { throw QuestlynError.emptyName }
        guard draft.dueTime == nil || draft.dueDate != nil else { throw QuestlynError.timeWithoutDate }
        let details = trimmed(draft.details)
        return Quest(
            title: title, details: details.isEmpty ? nil : details, priority: draft.priority,
            skillId: draft.skillId, dueDate: draft.dueDate, dueTime: draft.dueTime,
            timezoneId: timeZone.identifier, epicId: epicId ?? draft.epicId, createdAt: now
        )
    }

    /// Изменить и перенести квест (BACKLOG 2.7). У выполненного нельзя менять приоритет и навык:
    /// начисления уже посчитаны по ним (рабочая гипотеза, 02).
    @discardableResult
    public func update(questId: UUID, with draft: QuestDraft) async throws -> Quest {
        guard let existing = try await store.quest(id: questId) else { throw QuestlynError.questNotFound }
        if try await store.activeCompletion(questId: questId) != nil,
           draft.priority != existing.priority || draft.skillId != existing.skillId {
            throw QuestlynError.lockedWhileCompleted
        }
        if let skillId = draft.skillId, skillId != existing.skillId, try await !store.skills().contains(where: { $0.id == skillId }) {
            throw QuestlynError.skillNotFound
        }
        var quest = try Self.makeQuest(draft, now: existing.createdAt, timeZone: TimeZone(identifier: existing.timezoneId) ?? .current)
        quest.id = existing.id
        quest.timezoneId = existing.timezoneId
        quest.createdAt = existing.createdAt
        try await store.save(quest)
        return quest
    }
}

/// Что изменилось после выполнения или отмены — для экрана «Квест выполнен» (BACKLOG 1.7).
public struct CompletionReport: Sendable, Equatable, Identifiable {
    public var id: UUID { completion.id }
    public var quest: Quest
    public var completion: QuestCompletion
    public var grants: [ProgressGrant]
    public var before: HeroProgress
    public var after: HeroProgress

    /// Атрибуты, у которых вырос уровень.
    public var levelUps: [(attribute: Attribute, level: Int)] {
        Attribute.allCases.compactMap { a in
            after.level(a) > before.level(a) ? (a, after.level(a)) : nil
        }
    }

    public var rankChanged: Bool { before.rank != after.rank }

    public static func == (lhs: CompletionReport, rhs: CompletionReport) -> Bool {
        lhs.completion == rhs.completion && lhs.grants == rhs.grants && lhs.before == rhs.before && lhs.after == rhs.after
    }
}

/// Выполнение квеста и отмена (BACKLOG 1.6–1.7).
public struct CompletionService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    public func complete(questId: UUID, now: Date, timeZone: TimeZone) async throws -> CompletionReport {
        try await complete(questId: questId, now: now, timeZone: timeZone, activity: nil)
    }

    func complete(questId: UUID, now: Date, timeZone: TimeZone, activity draft: ActivityDraft?) async throws -> CompletionReport {
        guard let quest = try await store.quest(id: questId) else { throw QuestlynError.questNotFound }
        guard try await store.activeCompletion(questId: questId) == nil else { throw QuestlynError.alreadyCompleted }

        guard let hero = try await store.currentHero() else { throw QuestlynError.heroNotFound }
        let professions = try await store.professions(heroId: hero.id)

        var skill: Skill?
        var skillProfession: Profession?
        if let skillId = quest.skillId {
            skill = try await store.skills().first { $0.id == skillId }
            skillProfession = professions.first { $0.id == skill?.professionId }
        }
        // Навык неактивной профессии: навык растёт, атрибуты — по составу этой профессии.
        let snapshot = skillProfession.map { ClassRules.snapshot(skillProfession: $0, activeProfessions: professions) } ?? .empty

        let completion = QuestCompletion(
            questId: questId, completedAt: now, localDate: LocalDate(now, timeZone: timeZone),
            timezoneId: timeZone.identifier, classSnapshot: snapshot
        )
        // С активностью квест даёт только FOC: навык и атрибуты начисляет Activity.
        var grants = GrantCalculator.questCompletionGrants(
            completionId: completion.id, priority: quest.priority, skill: draft == nil ? skill : nil,
            skillProfessionTitle: skillProfession?.title, snapshot: draft == nil ? snapshot : .empty,
            createdAt: now, effectiveDate: completion.localDate
        )
        let classAttributes = ClassRules.classAttributes(of: professions)
        let today = completion.localDate
        let before = HeroProgress(grants: try await store.allGrants(), classAttributes: classAttributes, today: today)
        if let draft {
            let (activity, activityGrants) = try await ActivityService(store: store)
                .prepare(draft, now: now, timeZone: timeZone, questCompletionId: completion.id)
            try await store.record(completion, questGrants: grants, activity: activity, activityGrants: activityGrants)
            grants += activityGrants
        } else {
            try await store.record(completion, grants: grants)
        }
        let after = HeroProgress(grants: try await store.allGrants(), classAttributes: classAttributes, today: today)
        return CompletionReport(quest: quest, completion: completion, grants: grants, before: before, after: after)
    }

    public func undo(questId: UUID, now: Date) async throws {
        guard let completion = try await store.activeCompletion(questId: questId) else { throw QuestlynError.notCompleted }
        try await store.undo(completionId: completion.id, at: now)
    }
}

/// Раздел «Сегодня», в котором показан квест.
public enum TodaySection: Int, Sendable, Comparable {
    case overdue, today, undated
    public static func < (lhs: TodaySection, rhs: TodaySection) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct TodayItem: Sendable, Equatable, Identifiable {
    public var quest: Quest
    public var completion: QuestCompletion?
    public var section: TodaySection
    public var skill: Skill?
    public var id: UUID { quest.id }
    public var isCompleted: Bool { completion != nil }
}

/// Данные экрана «Сегодня».
public struct TodayOverview: Sendable, Equatable {
    public var date: LocalDate
    public var hero: Hero?
    public var professions: [Profession]
    public var skills: [Skill]
    public var items: [TodayItem]
    public var progress: HeroProgress
    /// Daily и Weekly со статусом на сегодня и неделю.
    public var habits: [HabitStatus]
    public var epics: [EpicStatus]
    /// Все обычные квесты для журнала.
    public var journal: [TodayItem]
    /// DIS за прошлую неделю, если уже посчитан.
    public var lastDiscipline: ProgressGrant?
    /// Последняя оценка мастерства по навыкам.
    public var masteries: [UUID: Int]
    /// Активности сегодня.
    public var activities: [Activity]
    /// HP и MP на сейчас (08); nil — героя ещё нет.
    public var vitals: VitalsState?
    public var vitalSettings: VitalSettings = .default
    /// Ночь пробуждения сегодня уже внесена (вручную или из Apple Health).
    public var hasSleepToday = false
}

/// Сборка «Сегодня» и «Героя» (BACKLOG 1.5, 1.8).
public struct TodayService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    public func overview(now: Date, timeZone: TimeZone) async throws -> TodayOverview {
        try await DisciplineService(store: store).settle(now: now, timeZone: timeZone)
        let date = LocalDate(now, timeZone: timeZone)
        let hero = try await store.currentHero()
        var professions: [Profession] = []
        if let hero { professions = try await store.professions(heroId: hero.id) }
        let skills = try await store.skills()
        let quests = try await store.questsForToday(date)
        let completions = try await store.activeCompletions(questIds: quests.map(\.id))

        let items: [TodayItem] = quests.compactMap { quest in
            let completion = completions[quest.id]
            let doneToday = completion?.localDate == date
            let section: TodaySection
            switch quest.dueDate {
            case let due? where due == date:
                section = .today
            case let due? where due < date:
                // Просроченный — пока не выполнен; выполненный сегодня переезжает в «Сегодня».
                if completion == nil { section = .overdue } else if doneToday { section = .today } else { return nil }
            case .some:
                // Будущий квест, выполненный заранее, показываем в день выполнения.
                guard doneToday else { return nil }
                section = .today
            case nil:
                guard completion == nil || doneToday else { return nil }
                section = .undated
            }
            return TodayItem(quest: quest, completion: completion, section: section, skill: skills.first { $0.id == quest.skillId })
        }
        .sorted { lhs, rhs in
            if lhs.section != rhs.section { return lhs.section < rhs.section }
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            switch (lhs.quest.dueTime, rhs.quest.dueTime) {
            case let (l?, r?) where l != r: return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.quest.createdAt < rhs.quest.createdAt
            }
        }

        let progress = HeroProgress(grants: try await store.allGrants(), classAttributes: ClassRules.classAttributes(of: professions), today: date)
        let masteries = Dictionary(try await store.masteries().map { ($0.skillId, $0.value) }, uniquingKeysWith: { _, latest in latest })

        // Журнал: все обычные квесты; выполненные — с фактом выполнения.
        let allQuests = try await store.allQuests()
        let allCompletions = try await store.activeCompletions(questIds: allQuests.map(\.id))
        let journal = allQuests.map { quest in
            let completion = allCompletions[quest.id]
            let section: TodaySection = quest.dueDate.map { $0 < date ? .overdue : .today } ?? .undated
            return TodayItem(quest: quest, completion: completion, section: section, skill: skills.first { $0.id == quest.skillId })
        }

        let habits = try await HabitStatusBuilder(store: store).statuses(today: date, skills: skills)
        let epics = try await store.epics().map { epic in
            let steps = journal.filter { $0.quest.epicId == epic.id }.sorted { lhs, rhs in
                (lhs.quest.dueDate ?? LocalDate(year: 9999, month: 1, day: 1), lhs.quest.createdAt)
                    < (rhs.quest.dueDate ?? LocalDate(year: 9999, month: 1, day: 1), rhs.quest.createdAt)
            }
            return EpicStatus(epic: epic, steps: steps)
        }
        let lastWeek = date.weekStart.adding(days: -7)
        let lastDiscipline = try await store.disciplineGrants().first { $0.sourceId == DisciplineCalculator.sourceId(weekStart: lastWeek) }
        let settings = try await store.vitalSettings()
        let sleeps = try await store.sleepSessions()
        var vitals: VitalsState?
        if let hero {
            vitals = try await VitalsService(store: store).state(hero: hero, journal: journal, sleeps: sleeps, settings: settings,
                                                                 grants: progress.grants, now: now, timeZone: timeZone)
        }
        return TodayOverview(date: date, hero: hero, professions: professions, skills: skills, items: items, progress: progress,
                             habits: habits, epics: epics, journal: journal, lastDiscipline: lastDiscipline, masteries: masteries,
                             activities: try await store.activities(from: date, through: date),
                             vitals: vitals, vitalSettings: settings, hasSleepToday: sleeps.contains { $0.wakeDate == date })
    }
}
