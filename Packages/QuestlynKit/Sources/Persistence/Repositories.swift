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

    public func createHero(_ hero: Hero, professions: [Profession]) async throws {
        try await writer.write { db in
            try HeroRecord(hero).insert(db)
            for profession in professions {
                try ProfessionRecord(profession).insert(db)
                for (index, attribute) in profession.attributes.enumerated() {
                    try ProfessionAttributeRecord(professionId: profession.id, position: index + 1, attribute: attribute.rawValue).insert(db)
                }
            }
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

    // MARK: Quest

    public func quests(dueOn date: LocalDate) async throws -> [Quest] {
        try await writer.read { db in
            try QuestRecord
                .filter(QuestRecord.Columns.dueDate == date.description)
                .order(QuestRecord.Columns.dueTime.ascNullsLast, QuestRecord.Columns.createdAt)
                .fetchAll(db)
                .map(\.domain)
        }
    }

    public func questsForToday(_ date: LocalDate) async throws -> [Quest] {
        try await writer.read { db in
            try QuestRecord.fetchAll(db, sql: """
                SELECT * FROM quest
                WHERE dueDate IS NULL OR dueDate <= ?
                   OR id IN (SELECT questId FROM questCompletion WHERE undoneAt IS NULL AND localDate = ?)
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
        try await writer.read { db in try QuestRecord.order(QuestRecord.Columns.createdAt).fetchAll(db).map(\.domain) }
    }

    // MARK: Epic

    public func epics() async throws -> [EpicQuest] {
        try await writer.read { db in try EpicRecord.order(Column("createdAt")).fetchAll(db).map(\.domain) }
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
        }
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
