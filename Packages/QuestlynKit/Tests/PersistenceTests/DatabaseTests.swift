import Foundation
import Testing
import GRDB
import Domain
@testable import Persistence

struct DatabaseTests {
    let database: AppDatabase
    init() throws { database = try AppDatabase.inMemory() }

    @Test func migrationCreatesSchema() throws {
        try database.writer.read { db in
            for table in ["hero", "profession", "professionAttribute", "skill", "quest", "questCompletion", "progressGrant"] {
                let exists = try db.tableExists(table)
                #expect(exists, "нет таблицы \(table)")
            }
        }
        #expect(try database.writer.read { try Migrations.migrator.appliedIdentifiers($0) } == [Migrations.initial])
    }

    @Test func questsForDateAreOrderedByTimeThenCreation() async throws {
        let repository = GRDBStore(database)
        let day = LocalDate(year: 2026, month: 11, day: 10)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let untimed = Quest(title: "Без времени", dueDate: day, timezoneId: "Europe/Moscow", createdAt: base)
        let late = Quest(title: "Вечер", dueDate: day, dueTime: LocalTime(hour: 18, minute: 0), timezoneId: "Europe/Moscow", createdAt: base + 1)
        let early = Quest(title: "Утро", priority: .high, dueDate: day, dueTime: LocalTime(hour: 9, minute: 30), timezoneId: "Europe/Moscow", createdAt: base + 2)
        let otherDay = Quest(title: "Завтра", dueDate: LocalDate(year: 2026, month: 11, day: 11), timezoneId: "Europe/Moscow", createdAt: base)
        let undated = Quest(title: "Когда-нибудь", timezoneId: "Europe/Moscow", createdAt: base)
        for quest in [untimed, late, early, otherDay, undated] { try await repository.save(quest) }

        let result = try await repository.quests(dueOn: day)
        #expect(result.map(\.title) == ["Утро", "Вечер", "Без времени"])
        #expect(result.first == early)
    }

    @Test func heroRoundTrip() async throws {
        let repository = GRDBStore(database)
        #expect(try await repository.currentHero() == nil)
        let hero = Hero(name: "Арин", classTitle: "Инженер-атлет", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        let profession = Profession(heroId: hero.id, title: "Атлет", slot: 1, attributes: [.strength, .endurance, .mentality], createdAt: hero.createdAt)
        try await repository.createHero(hero, professions: [profession])
        #expect(try await repository.currentHero() == hero)
        #expect(try await repository.professions(heroId: hero.id) == [profession])
    }

    @Test func schemaRejectsFocusInProfession() throws {
        _ = try database.writer.write { db in
            let heroId = UUID().uuidString.lowercased()
            let professionId = UUID().uuidString.lowercased()
            try db.execute(sql: "INSERT INTO hero (id, name, classTitle, createdAt) VALUES (?, 'Г', 'К', '2026-11-10')", arguments: [heroId])
            try db.execute(sql: "INSERT INTO profession (id, heroId, title, slot, createdAt) VALUES (?, ?, 'П', 1, '2026-11-10')", arguments: [professionId, heroId])
            try db.execute(sql: "INSERT INTO professionAttribute (professionId, position, attribute) VALUES (?, 1, 'INT')", arguments: [professionId])
            #expect(throws: DatabaseError.self) {
                try db.execute(sql: "INSERT INTO professionAttribute (professionId, position, attribute) VALUES (?, 2, 'FOC')", arguments: [professionId])
            }
        }
    }

    @Test func schemaRejectsTimeWithoutDate() throws {
        _ = try database.writer.write { db in
            #expect(throws: DatabaseError.self) {
                try db.execute(sql: "INSERT INTO quest (id, title, dueTime, timezoneId, createdAt) VALUES ('q', 'Т', '09:00', 'UTC', '2026-11-10')")
            }
        }
    }

    @Test func onlyOneActiveCompletionPerQuest() throws {
        _ = try database.writer.write { db in
            try db.execute(sql: "INSERT INTO quest (id, title, timezoneId, createdAt) VALUES ('q', 'Т', 'UTC', '2026-11-10')")
            let insert = "INSERT INTO questCompletion (id, questId, completedAt, localDate, timezoneId, undoneAt, classSnapshot) VALUES (?, 'q', '2026-11-10', '2026-11-10', 'UTC', ?, '{}')"
            try db.execute(sql: insert, arguments: ["c1", "2026-11-10"]) // отменено
            try db.execute(sql: insert, arguments: ["c2", nil])
            #expect(throws: DatabaseError.self) { try db.execute(sql: insert, arguments: ["c3", nil]) }
        }
    }

    @Test func grantIsUniquePerSourceRuleAndTarget() throws {
        _ = try database.writer.write { db in
            let insert = """
                INSERT INTO progressGrant (id, sourceType, sourceId, ruleVersion, targetKind, attribute, skillId, targetKey, amountCenti, reason, createdAt)
                VALUES (?, 'questCompletion', 'c1', '1.1', 'attribute', 'INT', NULL, 'attribute:INT', 500, '', '2026-11-10')
                """
            try db.execute(sql: insert, arguments: ["g1"])
            #expect(throws: DatabaseError.self) { try db.execute(sql: insert, arguments: ["g2"]) }
        }
    }
}

struct UUIDStorageTests {
    @Test func uuidsAreStoredAsLowercaseText() async throws {
        let database = try AppDatabase.inMemory()
        let hero = Hero(name: "Г", classTitle: "К", createdAt: .now)
        try await GRDBStore(database).createHero(hero, professions: [])
        let stored = try await database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT typeof(id) || ':' || id FROM hero")
        }
        #expect(stored == "text:\(hero.id.uuidString.lowercased())")
    }
}
