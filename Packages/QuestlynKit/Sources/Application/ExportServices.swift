import Foundation
import Domain

/// Экспорт всех данных героя (7.2): факты, начисления и настройки в одном JSON. Проекции (уровни, HP, MP) не выгружаются — они пересчитываются.
public struct QuestlynExport: Codable, Sendable {
    public static let formatVersion = 1

    public var formatVersion: Int
    public var exportedAt: Date
    public var ruleVersion: String
    public var hero: Hero?
    public var professions: [Profession]
    public var skills: [Skill]
    public var masteries: [SkillMastery]
    public var quests: [Quest]
    public var completions: [QuestCompletion]
    public var epics: [EpicQuest]
    public var habits: [HabitDefinition]
    public var habitOccurrences: [HabitOccurrence]
    public var activities: [Activity]
    public var grants: [ProgressGrant]
    public var sleepSessions: [SleepSession]
    public var stepDays: [StepDay]
    public var moods: [MoodEntry]
    public var harms: [HarmEntry]
    public var customHarmHabits: [CustomHarmHabit]
    public var chronicleEntries: [ChronicleEntry]
    public var vitalSettings: VitalSettings
}

public struct ExportService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    public func snapshot(now: Date) async throws -> QuestlynExport {
        let hero = try await store.currentHero()
        var professions: [Profession] = []
        if let hero { professions = try await store.professions(heroId: hero.id) }
        return QuestlynExport(
            formatVersion: QuestlynExport.formatVersion, exportedAt: now, ruleVersion: RuleVersion.current.rawValue, hero: hero,
            professions: professions, skills: try await store.skills(), masteries: try await store.masteries(),
            quests: try await store.allQuests(), completions: try await store.allCompletions(), epics: try await store.epics(),
            habits: try await store.habits(), habitOccurrences: try await store.allOccurrences(), activities: try await store.allActivities(),
            grants: try await store.allGrants(), sleepSessions: try await store.sleepSessions(), stepDays: try await store.stepDays(),
            moods: try await store.moodEntries(), harms: try await store.harmEntries(), customHarmHabits: try await store.customHarmHabits(),
            chronicleEntries: try await store.chronicleEntries(), vitalSettings: try await store.vitalSettings()
        )
    }

    /// JSON с отступами и датами ISO 8601 — читается человеком и другими программами.
    public func json(now: Date) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(try await snapshot(now: now))
    }
}
