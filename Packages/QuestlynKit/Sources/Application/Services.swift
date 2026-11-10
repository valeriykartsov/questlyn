import Foundation
import Domain

private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

/// Онбординг: имя → 1–3 профессии из каталога → название класса (BACKLOG 1.2).
public struct OnboardingService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    /// Порядок `catalogItemIds` — порядок слотов: первая — основная профессия.
    @discardableResult
    public func start(heroName: String, catalogItemIds: [String], classTitle: String, now: Date) async throws -> Hero {
        let name = trimmed(heroName)
        guard !name.isEmpty else { throw QuestlynError.emptyName }
        guard (1...3).contains(catalogItemIds.count), Set(catalogItemIds).count == catalogItemIds.count else {
            throw QuestlynError.invalidProfessionCount
        }
        guard try await store.currentHero() == nil else { throw QuestlynError.heroAlreadyExists }
        let items = try catalogItemIds.map { id in
            guard let item = ProfessionCatalog.item(id: id) else { throw QuestlynError.unknownCatalogItem(id) }
            return item
        }
        let title = trimmed(classTitle)
        let hero = Hero(name: name, classTitle: title.isEmpty ? items.map(\.title).joined(separator: " · ") : title, createdAt: now)
        let professions = items.enumerated().map { index, item in
            Profession(
                heroId: hero.id, title: item.title, slot: index + 1, attributes: item.attributes,
                catalogItemId: item.id, catalogVersion: ProfessionCatalog.version, createdAt: now
            )
        }
        try await store.createHero(hero, professions: professions)
        return hero
    }
}

/// Создание навыка в профессии (BACKLOG 1.3).
public struct SkillService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    @discardableResult
    public func create(title: String, professionId: UUID, now: Date) async throws -> Skill {
        let name = trimmed(title)
        guard !name.isEmpty else { throw QuestlynError.emptyName }
        guard let hero = try await store.currentHero() else { throw QuestlynError.heroNotFound }
        guard try await store.professions(heroId: hero.id).contains(where: { $0.id == professionId && $0.isActive }) else {
            throw QuestlynError.professionNotFound
        }
        let skill = Skill(professionId: professionId, title: name, createdAt: now)
        try await store.save(skill)
        return skill
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

    public init(title: String = "", details: String = "", priority: QuestPriority = .default,
                skillId: UUID? = nil, dueDate: LocalDate? = nil, dueTime: LocalTime? = nil) {
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
        let details = trimmed(draft.details)
        let quest = Quest(
            title: title, details: details.isEmpty ? nil : details, priority: draft.priority,
            skillId: draft.skillId, dueDate: draft.dueDate, dueTime: draft.dueTime,
            timezoneId: timeZone.identifier, createdAt: now
        )
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
        let grants = GrantCalculator.questCompletionGrants(
            completionId: completion.id, priority: quest.priority, skill: skill,
            skillProfessionTitle: skillProfession?.title, snapshot: snapshot, createdAt: now
        )
        let classAttributes = ClassRules.classAttributes(of: professions)
        let before = HeroProgress(grants: try await store.allGrants(), classAttributes: classAttributes)
        try await store.record(completion, grants: grants)
        let after = HeroProgress(grants: try await store.allGrants(), classAttributes: classAttributes)
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
}

/// Сборка «Сегодня» и «Героя» (BACKLOG 1.5, 1.8).
public struct TodayService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    public func overview(now: Date, timeZone: TimeZone) async throws -> TodayOverview {
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

        let progress = HeroProgress(grants: try await store.allGrants(), classAttributes: ClassRules.classAttributes(of: professions))
        return TodayOverview(date: date, hero: hero, professions: professions, skills: skills, items: items, progress: progress)
    }
}
