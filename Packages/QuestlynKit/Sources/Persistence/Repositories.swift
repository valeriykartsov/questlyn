import Foundation
import GRDB
import Domain
import Application

/// Реализация портов Application поверх одной БД.
public struct GRDBStore: QuestlynStore {
    private let database: AppDatabase

    public init(_ database: AppDatabase) { self.database = database }

    private var writer: any DatabaseWriter { database.writer }

    // MARK: Hero

    public func currentHero() async throws -> Hero? {
        try await writer.read { db in
            try HeroRecord.order(Column("createdAt")).fetchOne(db)?.domain
        }
    }

    public func createHero(_ hero: Hero, professions: [Profession], grants: [ProgressGrant]) async throws {
        try await writer.write { db in
            try HeroRecord(hero).insert(db)
            for profession in professions { try Self.write(profession, db) }
            for grant in grants { try ProgressGrantRecord(grant).insert(db) }
        }
    }

    public func save(_ hero: Hero) async throws {
        try await writer.write { db in try HeroRecord(hero).save(db) }
    }

    public func applyProfessions(_ professions: [Profession]) async throws {
        try await writer.write { db in
            // Сначала отключаем все, чтобы уникальный индекс активных слотов не мешал перестановке.
            try db.execute(sql: "UPDATE profession SET isActive = 0")
            for profession in professions {
                try Self.write(profession, db)
                try db.execute(sql: "UPDATE skill SET isActive = ? WHERE professionId = ?",
                               arguments: [profession.isActive, profession.id.uuidString.lowercased()])
            }
        }
    }

    private static func write(_ profession: Profession, _ db: Database) throws {
        try ProfessionRecord(profession).save(db)
        try ProfessionAttributeRecord.filter(Column("professionId") == profession.id.uuidString.lowercased()).deleteAll(db)
        for (index, attribute) in profession.attributes.enumerated() {
            try ProfessionAttributeRecord(professionId: profession.id, position: index + 1, attribute: attribute.rawValue).insert(db)
        }
    }

    public func professions(heroId: UUID) async throws -> [Profession] {
        try await writer.read { db in
            let records = try ProfessionRecord
                .filter(Column("heroId") == heroId.uuidString.lowercased())
                .order(Column("isActive").desc, Column("slot"))
                .fetchAll(db)
            let attributes = try ProfessionAttributeRecord.order(Column("position")).fetchAll(db)
            let byProfession = Dictionary(grouping: attributes, by: \.professionId)
            return records.map { record in
                record.domain(attributes: (byProfession[record.id] ?? []).compactMap { Attribute(rawValue: $0.attribute) })
            }
        }
    }

    // MARK: Skill

    public func skills() async throws -> [Skill] {
        try await writer.read { db in try SkillRecord.order(Column("createdAt")).fetchAll(db).map(\.domain) }
    }

    public func save(_ skill: Skill) async throws {
        try await writer.write { db in try SkillRecord(skill).save(db) }
    }

    public func linkActivityTemplate(_ templateId: String?, toSkill skillId: UUID) async throws {
        try await writer.write { db in
            if let templateId {
                try db.execute(sql: "UPDATE skill SET activityTemplateId = NULL WHERE activityTemplateId = ? AND id != ?",
                               arguments: [templateId, skillId.uuidString.lowercased()])
            }
            try db.execute(sql: "UPDATE skill SET activityTemplateId = ? WHERE id = ?", arguments: [templateId, skillId.uuidString.lowercased()])
        }
    }

    public func masteries() async throws -> [SkillMastery] {
        try await writer.read { db in try SkillMasteryRecord.order(Column("assessedAt")).fetchAll(db).map(\.domain) }
    }

    public func save(_ mastery: SkillMastery) async throws {
        try await writer.write { db in try SkillMasteryRecord(mastery).insert(db) }
    }

    // MARK: Quest

    public func quests(dueOn date: LocalDate) async throws -> [Quest] {
        try await writer.read { db in
            try QuestRecord
                .filter(QuestRecord.Columns.dueDate == date.description && Column("deletedAt") == nil)
                .order(QuestRecord.Columns.dueTime.ascNullsLast, QuestRecord.Columns.createdAt)
                .fetchAll(db)
                .map(\.domain)
        }
    }

    public func questsForToday(_ date: LocalDate) async throws -> [Quest] {
        try await writer.read { db in
            try QuestRecord.fetchAll(db, sql: """
                SELECT * FROM quest
                WHERE deletedAt IS NULL AND (dueDate IS NULL OR dueDate <= ?
                   OR id IN (SELECT questId FROM questCompletion WHERE undoneAt IS NULL AND localDate = ?))
                ORDER BY createdAt
                """, arguments: [date.description, date.description])
            .map(\.domain)
        }
    }

    public func quest(id: UUID) async throws -> Quest? {
        try await writer.read { db in try QuestRecord.fetchOne(db, key: id.uuidString.lowercased())?.domain }
    }

    public func save(_ quest: Quest) async throws {
        try await writer.write { db in try QuestRecord(quest).save(db) }
    }

    public func allQuests() async throws -> [Quest] {
        try await writer.read { db in
            try QuestRecord.filter(Column("deletedAt") == nil).order(QuestRecord.Columns.createdAt).fetchAll(db).map(\.domain)
        }
    }

    public func allQuestsIncludingDeleted() async throws -> [Quest] {
        try await writer.read { db in try QuestRecord.order(QuestRecord.Columns.createdAt).fetchAll(db).map(\.domain) }
    }

    // MARK: Epic

    public func epics() async throws -> [EpicQuest] {
        try await writer.read { db in try EpicRecord.filter(Column("deletedAt") == nil).order(Column("createdAt")).fetchAll(db).map(\.domain) }
    }

    public func epic(id: UUID) async throws -> EpicQuest? {
        try await writer.read { db in try EpicRecord.fetchOne(db, key: id.uuidString.lowercased())?.domain }
    }

    public func save(_ epic: EpicQuest) async throws {
        try await writer.write { db in try EpicRecord(epic).save(db) }
    }

    public func createEpic(_ epic: EpicQuest, steps: [Quest]) async throws {
        try await writer.write { db in
            try EpicRecord(epic).insert(db)
            for step in steps { try QuestRecord(step).insert(db) }
        }
    }

    // MARK: Habit

    public func habits() async throws -> [HabitDefinition] {
        try await writer.read { db in try HabitRecord.order(Column("createdAt")).fetchAll(db).compactMap(\.domain) }
    }

    public func habit(id: UUID) async throws -> HabitDefinition? {
        try await writer.read { db in try HabitRecord.fetchOne(db, key: id.uuidString.lowercased())?.domain }
    }

    public func save(_ habit: HabitDefinition) async throws {
        try await writer.write { db in try HabitRecord(habit).save(db) }
    }

    public func occurrences(from: LocalDate, through: LocalDate) async throws -> [HabitOccurrence] {
        try await writer.read { db in
            try HabitOccurrenceRecord
                .filter(Column("undoneAt") == nil && Column("localDate") >= from.description && Column("localDate") <= through.description)
                .order(Column("completedAt"))
                .fetchAll(db)
                .compactMap(\.domain)
        }
    }

    public func record(_ occurrence: HabitOccurrence, grants: [ProgressGrant]) async throws {
        try await writer.write { db in
            try HabitOccurrenceRecord(occurrence).insert(db)
            for grant in grants { try ProgressGrantRecord(grant).insert(db) }
        }
    }

    public func undoOccurrence(id: UUID, at date: Date) async throws {
        try await writer.write { db in
            let key = id.uuidString.lowercased()
            guard var record = try HabitOccurrenceRecord.fetchOne(db, key: key), record.undoneAt == nil else {
                throw QuestlynError.notCompleted
            }
            record.undoneAt = date
            try record.update(db)
            try ProgressGrantRecord
                .filter(Column("sourceType") == GrantSourceType.habitOccurrence.rawValue && Column("sourceId") == key)
                .deleteAll(db)
        }
    }

    // MARK: Discipline

    public func disciplineGrants() async throws -> [ProgressGrant] {
        try await writer.read { db in
            try ProgressGrantRecord.filter(Column("sourceType") == GrantSourceType.weeklyDiscipline.rawValue)
                .order(Column("sourceId"))
                .fetchAll(db).compactMap(\.domain)
        }
    }

    public func replaceDisciplineGrant(sourceId: UUID, with grant: ProgressGrant) async throws {
        try await writer.write { db in
            try ProgressGrantRecord
                .filter(Column("sourceType") == GrantSourceType.weeklyDiscipline.rawValue && Column("sourceId") == sourceId.uuidString.lowercased())
                .deleteAll(db)
            try ProgressGrantRecord(grant).insert(db)
        }
    }

    // MARK: Completion

    public func activeCompletion(questId: UUID) async throws -> QuestCompletion? {
        try await writer.read { db in
            try QuestCompletionRecord
                .filter(Column("questId") == questId.uuidString.lowercased() && Column("undoneAt") == nil)
                .fetchOne(db)?.domain
        }
    }

    public func activeCompletions(questIds: [UUID]) async throws -> [UUID: QuestCompletion] {
        try await writer.read { db in
            let ids = questIds.map { $0.uuidString.lowercased() }
            let records = try QuestCompletionRecord
                .filter(ids.contains(Column("questId")) && Column("undoneAt") == nil)
                .fetchAll(db)
            return Dictionary(records.compactMap(\.domain).map { ($0.questId, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    public func record(_ completion: QuestCompletion, grants: [ProgressGrant]) async throws {
        do {
            try await writer.write { db in
                try QuestCompletionRecord(completion).insert(db)
                for grant in grants { try ProgressGrantRecord(grant).insert(db) }
            }
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            throw QuestlynError.alreadyCompleted
        }
    }

    public func undo(completionId: UUID, at date: Date) async throws {
        try await writer.write { db in
            let id = completionId.uuidString.lowercased()
            guard var record = try QuestCompletionRecord.fetchOne(db, key: id), record.undoneAt == nil else {
                throw QuestlynError.notCompleted
            }
            record.undoneAt = date
            try record.update(db)
            try ProgressGrantRecord
                .filter(Column("sourceType") == GrantSourceType.questCompletion.rawValue && Column("sourceId") == id)
                .deleteAll(db)
            // Квест, закрытый активностью: отмена убирает и эту активность — они записаны одним действием (02).
            let linked = try String.fetchAll(db, sql: "SELECT id FROM activity WHERE questCompletionId = ? AND deletedAt IS NULL", arguments: [id])
            for activityId in linked { try Self.deleteActivity(activityId, at: date, db) }
        }
    }

    // MARK: Activity

    public func activities(from: LocalDate, through: LocalDate) async throws -> [Activity] {
        try await writer.read { db in
            try ActivityRecord
                .filter(Column("deletedAt") == nil && Column("localDate") >= from.description && Column("localDate") <= through.description)
                .order(Column("startedAt"))
                .fetchAll(db).compactMap(\.domain)
        }
    }

    public func record(_ activity: Activity, grants: [ProgressGrant]) async throws {
        try await writer.write { db in
            try ActivityRecord(activity).insert(db)
            for grant in grants { try ProgressGrantRecord(grant).insert(db) }
        }
    }

    public func record(_ completion: QuestCompletion, questGrants: [ProgressGrant], activity: Activity, activityGrants: [ProgressGrant]) async throws {
        do {
            try await writer.write { db in
                try QuestCompletionRecord(completion).insert(db)
                for grant in questGrants { try ProgressGrantRecord(grant).insert(db) }
                try ActivityRecord(activity).insert(db)
                for grant in activityGrants { try ProgressGrantRecord(grant).insert(db) }
            }
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            throw QuestlynError.alreadyCompleted
        }
    }

    public func deleteActivity(id: UUID, at date: Date) async throws {
        try await writer.write { db in try Self.deleteActivity(id.uuidString.lowercased(), at: date, db) }
    }

    private static func deleteActivity(_ key: String, at date: Date, _ db: Database) throws {
        guard var record = try ActivityRecord.fetchOne(db, key: key), record.deletedAt == nil else { throw QuestlynError.notCompleted }
        record.deletedAt = date
        try record.update(db)
        try ProgressGrantRecord.filter(Column("sourceType") == GrantSourceType.activity.rawValue && Column("sourceId") == key).deleteAll(db)
    }

    // MARK: Vitals

    public func sleepSessions() async throws -> [SleepSession] {
        try await writer.read { db in try SleepSessionRecord.order(Column("wakeDate")).fetchAll(db).compactMap(\.domain) }
    }

    public func saveManualSleep(_ session: SleepSession) async throws {
        try await writer.write { db in
            try SleepSessionRecord
                .filter(Column("source") == SleepSource.manual.rawValue && Column("wakeDate") == session.wakeDate.description)
                .deleteAll(db)
            try SleepSessionRecord(session).insert(db)
        }
    }

    public func saveCorrectedSleep(_ session: SleepSession) async throws {
        try await writer.write { db in
            try SleepSessionRecord
                .filter(Column("source") == SleepSource.corrected.rawValue && Column("wakeDate") == session.wakeDate.description)
                .deleteAll(db)
            try SleepSessionRecord(session).insert(db)
        }
    }

    public func deleteSleep(id: UUID) async throws {
        try await writer.write { db in _ = try SleepSessionRecord.deleteOne(db, key: id.uuidString.lowercased()) }
    }

    public func replaceHealthSleep(_ sessions: [SleepSession], wakeDates: [LocalDate]) async throws {
        try await writer.write { db in
            try SleepSessionRecord
                .filter(Column("source") == SleepSource.health.rawValue && wakeDates.map(\.description).contains(Column("wakeDate")))
                .deleteAll(db)
            for session in sessions { try SleepSessionRecord(session).insert(db) }
        }
    }

    public func stepDays() async throws -> [StepDay] {
        try await writer.read { db in try StepDayRecord.order(Column("date")).fetchAll(db).compactMap(\.domain) }
    }

    public func save(_ steps: [StepDay]) async throws {
        try await writer.write { db in for day in steps { try StepDayRecord(day).save(db) } }
    }

    private static let settingsKey = "vitalSettings"

    public func vitalSettings() async throws -> VitalSettings {
        try await writer.read { db in
            guard let record = try SettingRecord.fetchOne(db, key: Self.settingsKey),
                  let settings = try? JSONDecoder().decode(VitalSettings.self, from: Data(record.value.utf8)) else { return .default }
            return settings
        }
    }

    public func save(_ settings: VitalSettings) async throws {
        let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        try await writer.write { db in try SettingRecord(key: Self.settingsKey, value: json).save(db) }
    }

    // MARK: Chronicle

    public func chronicleEntries() async throws -> [ChronicleEntry] {
        try await writer.read { db in try ChronicleEntryRecord.order(Column("occurredAt")).fetchAll(db).compactMap(\.domain) }
    }

    public func save(_ entries: [ChronicleEntry]) async throws {
        try await writer.write { db in for entry in entries { try ChronicleEntryRecord(entry).save(db) } }
    }

    public func allCompletions() async throws -> [QuestCompletion] {
        try await writer.read { db in try QuestCompletionRecord.order(Column("completedAt")).fetchAll(db).compactMap(\.domain) }
    }

    public func allOccurrences() async throws -> [HabitOccurrence] {
        try await writer.read { db in try HabitOccurrenceRecord.order(Column("completedAt")).fetchAll(db).compactMap(\.domain) }
    }

    public func allActivities() async throws -> [Activity] {
        try await writer.read { db in try ActivityRecord.order(Column("startedAt")).fetchAll(db).compactMap(\.domain) }
    }

    // MARK: Wellbeing

    public func moodEntries() async throws -> [MoodEntry] {
        try await writer.read { db in try MoodEntryRecord.order(Column("at")).fetchAll(db).compactMap(\.domain) }
    }

    public func record(_ mood: MoodEntry) async throws {
        try await writer.write { db in
            if mood.isDaySummary {
                try db.execute(sql: "UPDATE moodEntry SET isDaySummary = 0 WHERE localDate = ? AND deletedAt IS NULL",
                               arguments: [mood.localDate.description])
            }
            try MoodEntryRecord(mood).insert(db)
        }
    }

    public func deleteMood(id: UUID, at date: Date) async throws {
        try await writer.write { db in
            guard var record = try MoodEntryRecord.fetchOne(db, key: id.uuidString.lowercased()), record.deletedAt == nil else { return }
            record.deletedAt = date
            try record.update(db)
        }
    }

    public func harmEntries() async throws -> [HarmEntry] {
        try await writer.read { db in try HarmEntryRecord.order(Column("at")).fetchAll(db).compactMap(\.domain) }
    }

    public func record(_ harms: [HarmEntry]) async throws {
        try await writer.write { db in for harm in harms { try HarmEntryRecord(harm).insert(db) } }
    }

    public func deleteHarm(id: UUID, at date: Date) async throws {
        try await writer.write { db in
            guard var record = try HarmEntryRecord.fetchOne(db, key: id.uuidString.lowercased()), record.deletedAt == nil else { return }
            record.deletedAt = date
            try record.update(db)
        }
    }

    public func customHarmHabits() async throws -> [CustomHarmHabit] {
        try await writer.read { db in try CustomHarmHabitRecord.order(Column("createdAt")).fetchAll(db).map(\.domain) }
    }

    public func save(_ habit: CustomHarmHabit) async throws {
        try await writer.write { db in try CustomHarmHabitRecord(habit).save(db) }
    }

    // MARK: Reset

    public func eraseAll() async throws {
        try await database.eraseAndMigrate()
    }

    // MARK: Grants

    public func allGrants() async throws -> [ProgressGrant] {
        try await writer.read { db in try ProgressGrantRecord.order(Column("createdAt")).fetchAll(db).compactMap(\.domain) }
    }

    public func grants(sourceId: UUID) async throws -> [ProgressGrant] {
        try await writer.read { db in
            try ProgressGrantRecord.filter(Column("sourceId") == sourceId.uuidString.lowercased()).fetchAll(db).compactMap(\.domain)
        }
    }
}
