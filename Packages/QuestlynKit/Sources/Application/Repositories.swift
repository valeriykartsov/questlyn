import Foundation
import Domain

/// Порты хранения. Реализация — в Persistence (одна БД, транзакции внутри методов).
public protocol HeroRepository: Sendable {
    func currentHero() async throws -> Hero?
    /// Герой, профессии и стартовый бонус — одной транзакцией (первая БД после онбординга).
    func createHero(_ hero: Hero, professions: [Profession], grants: [ProgressGrant]) async throws
    func professions(heroId: UUID) async throws -> [Profession]
    func save(_ hero: Hero) async throws
    /// Смена профессий: сохранить новые и изменённые, отключить убранные вместе с навыками, вернуть навыки возвращённых.
    func applyProfessions(_ professions: [Profession]) async throws
}

public protocol SkillRepository: Sendable {
    func skills() async throws -> [Skill]
    func save(_ skill: Skill) async throws
    /// Привязка вида активности один к одному: вид снимается с другого навыка — одной транзакцией. nil — убрать привязку.
    func linkActivityTemplate(_ templateId: String?, toSkill skillId: UUID) async throws
    func masteries() async throws -> [SkillMastery]
    func save(_ mastery: SkillMastery) async throws
}

public protocol QuestRepository: Sendable {
    func quests(dueOn date: LocalDate) async throws -> [Quest]
    /// Квесты для «Сегодня»: на дату и раньше, без даты, а также выполненные в этот день.
    func questsForToday(_ date: LocalDate) async throws -> [Quest]
    func quest(id: UUID) async throws -> Quest?
    func save(_ quest: Quest) async throws
    /// Квесты без удалённых.
    func allQuests() async throws -> [Quest]
    /// Все квесты, включая удалённые, — для Летописи и HP/MP.
    func allQuestsIncludingDeleted() async throws -> [Quest]
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

public protocol ActivityRepository: Sendable {
    /// Активные (не удалённые) активности в диапазоне дат.
    func activities(from: LocalDate, through: LocalDate) async throws -> [Activity]
    func record(_ activity: Activity, grants: [ProgressGrant]) async throws
    /// Квест, закрытый активностью: факт выполнения, активность и все начисления — одной транзакцией.
    func record(_ completion: QuestCompletion, questGrants: [ProgressGrant], activity: Activity, activityGrants: [ProgressGrant]) async throws
    /// Удаление: `deletedAt` у факта, начисления удаляются.
    func deleteActivity(id: UUID, at date: Date) async throws
}

public protocol VitalsRepository: Sendable {
    func sleepSessions() async throws -> [SleepSession]
    /// Ручной ввод за ночь заменяет прежний ручной ввод за ту же дату.
    func saveManualSleep(_ session: SleepSession) async throws
    /// Исправление ночи заменяет прежнее исправление той же даты; записи HealthKit и ручной ввод остаются (для «было»).
    func saveCorrectedSleep(_ session: SleepSession) async throws
    func deleteSleep(id: UUID) async throws
    /// Записи сна из HealthKit за даты пробуждения заменяются целиком.
    func replaceHealthSleep(_ sessions: [SleepSession], wakeDates: [LocalDate]) async throws
    func stepDays() async throws -> [StepDay]
    func save(_ steps: [StepDay]) async throws
    func vitalSettings() async throws -> VitalSettings
    func save(_ settings: VitalSettings) async throws
}

/// Летопись: вехи и полная история фактов, включая отменённые (08, раздел 4).
public protocol ChronicleRepository: Sendable {
    func chronicleEntries() async throws -> [ChronicleEntry]
    /// Новые и изменённые вехи — одной транзакцией.
    func save(_ entries: [ChronicleEntry]) async throws
    func allCompletions() async throws -> [QuestCompletion]
    func allOccurrences() async throws -> [HabitOccurrence]
    func allActivities() async throws -> [Activity]
}

/// Настроение и блок «Здоровье» (этап 6). Удаление — пометкой, история остаётся в Летописи.
public protocol WellbeingRepository: Sendable {
    /// Все отметки настроения, включая удалённые.
    func moodEntries() async throws -> [MoodEntry]
    /// «Итог дня» снимает этот флаг с прежних отметок того же дня.
    func record(_ mood: MoodEntry) async throws
    func deleteMood(id: UUID, at date: Date) async throws
    /// Все отметки здоровья, включая удалённые.
    func harmEntries() async throws -> [HarmEntry]
    func record(_ harms: [HarmEntry]) async throws
    func deleteHarm(id: UUID, at date: Date) async throws
    func customHarmHabits() async throws -> [CustomHarmHabit]
    func save(_ habit: CustomHarmHabit) async throws
}

public protocol ResetRepository: Sendable {
    /// Удалить все данные и создать пустую схему заново.
    func eraseAll() async throws
}

public typealias QuestlynStore = HeroRepository & SkillRepository & QuestRepository & CompletionRepository & GrantRepository
    & EpicRepository & HabitRepository & DisciplineRepository & ResetRepository & ActivityRepository & VitalsRepository
    & ChronicleRepository & WellbeingRepository
