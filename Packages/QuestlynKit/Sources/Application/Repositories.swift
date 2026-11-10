import Foundation
import Domain

/// Порты хранения. Реализация — в Persistence (одна БД, транзакции внутри методов).
public protocol HeroRepository: Sendable {
    func currentHero() async throws -> Hero?
    /// Герой и его профессии — одной транзакцией (первая БД после онбординга).
    func createHero(_ hero: Hero, professions: [Profession]) async throws
    func professions(heroId: UUID) async throws -> [Profession]
}

public protocol SkillRepository: Sendable {
    func skills() async throws -> [Skill]
    func save(_ skill: Skill) async throws
}

public protocol QuestRepository: Sendable {
    func quests(dueOn date: LocalDate) async throws -> [Quest]
    /// Квесты для «Сегодня»: на дату и раньше, без даты, а также выполненные в этот день.
    func questsForToday(_ date: LocalDate) async throws -> [Quest]
    func quest(id: UUID) async throws -> Quest?
    func save(_ quest: Quest) async throws
    func allQuests() async throws -> [Quest]
}

public protocol EpicRepository: Sendable {
    func epics() async throws -> [EpicQuest]
    func epic(id: UUID) async throws -> EpicQuest?
    func save(_ epic: EpicQuest) async throws
    /// Epic и его шаги — одной транзакцией.
    func createEpic(_ epic: EpicQuest, steps: [Quest]) async throws
}

public protocol HabitRepository: Sendable {
    func habits() async throws -> [HabitDefinition]
    func habit(id: UUID) async throws -> HabitDefinition?
    func save(_ habit: HabitDefinition) async throws
    /// Активные (не отменённые) отметки в диапазоне дат включительно.
    func occurrences(from: LocalDate, through: LocalDate) async throws -> [HabitOccurrence]
    func record(_ occurrence: HabitOccurrence, grants: [ProgressGrant]) async throws
    func undoOccurrence(id: UUID, at date: Date) async throws
}

public protocol DisciplineRepository: Sendable {
    /// Начисления DIS по неделям (sourceType = weeklyDiscipline).
    func disciplineGrants() async throws -> [ProgressGrant]
    /// Заменить начисление недели (удалить старое, записать новое).
    func replaceDisciplineGrant(sourceId: UUID, with grant: ProgressGrant) async throws
}

public protocol CompletionRepository: Sendable {
    func activeCompletion(questId: UUID) async throws -> QuestCompletion?
    func activeCompletions(questIds: [UUID]) async throws -> [UUID: QuestCompletion]
    /// Факт выполнения и его начисления — одной транзакцией. Повтор для квеста с активным выполнением — ошибка.
    func record(_ completion: QuestCompletion, grants: [ProgressGrant]) async throws
    /// Отмена: `undoneAt` у факта, начисления факта удаляются (07, раздел 1).
    func undo(completionId: UUID, at date: Date) async throws
}

public protocol GrantRepository: Sendable {
    func allGrants() async throws -> [ProgressGrant]
    func grants(sourceId: UUID) async throws -> [ProgressGrant]
}

public protocol ResetRepository: Sendable {
    /// Удалить все данные и создать пустую схему заново.
    func eraseAll() async throws
}

public typealias QuestlynStore = HeroRepository & SkillRepository & QuestRepository & CompletionRepository & GrantRepository
    & EpicRepository & HabitRepository & DisciplineRepository & ResetRepository
