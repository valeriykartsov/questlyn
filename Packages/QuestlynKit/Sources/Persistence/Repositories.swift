import Foundation
import GRDB
import Domain
import Application

public struct GRDBHeroRepository: HeroRepository {
    private let database: AppDatabase

    public init(_ database: AppDatabase) { self.database = database }

    public func currentHero() async throws -> Hero? {
        try await database.writer.read { db in
            try HeroRecord.order(Column("createdAt")).fetchOne(db)?.domain
        }
    }

    public func save(_ hero: Hero) async throws {
        try await database.writer.write { db in try HeroRecord(hero).save(db) }
    }
}

public struct GRDBQuestRepository: QuestRepository {
    private let database: AppDatabase

    public init(_ database: AppDatabase) { self.database = database }

    /// Квесты на дату: сначала со временем (по времени), потом без времени (по созданию).
    public func quests(dueOn date: LocalDate) async throws -> [Quest] {
        try await database.writer.read { db in
            try QuestRecord
                .filter(QuestRecord.Columns.dueDate == date.description)
                .order(QuestRecord.Columns.dueTime.ascNullsLast, QuestRecord.Columns.createdAt)
                .fetchAll(db)
                .map(\.domain)
        }
    }

    public func save(_ quest: Quest) async throws {
        try await database.writer.write { db in try QuestRecord(quest).save(db) }
    }
}
