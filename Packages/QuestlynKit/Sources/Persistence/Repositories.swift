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
