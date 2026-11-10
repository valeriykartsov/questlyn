import Foundation
import GRDB
import Domain

// Записи таблиц. Domain не знает про GRDB, поэтому соответствие — здесь.


struct HeroRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "hero"
    static let databaseUUIDEncodingStrategy = DatabaseUUIDEncodingStrategy.lowercaseString

    var id: UUID
    var name: String
    var classTitle: String
    var createdAt: Date

    init(_ hero: Hero) {
        id = hero.id
        name = hero.name
        classTitle = hero.classTitle
        createdAt = hero.createdAt
    }

    var domain: Hero { Hero(id: id, name: name, classTitle: classTitle, createdAt: createdAt) }
}

struct QuestRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "quest"
    static let databaseUUIDEncodingStrategy = DatabaseUUIDEncodingStrategy.lowercaseString

    var id: UUID
    var title: String
    var details: String?
    var priority: String
    var skillId: UUID?
    var dueDate: String?
    var dueTime: String?
    var timezoneId: String
    var createdAt: Date

    enum Columns {
        static let dueDate = Column(CodingKeys.dueDate)
        static let dueTime = Column(CodingKeys.dueTime)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    init(_ quest: Quest) {
        id = quest.id
        title = quest.title
        details = quest.details
        priority = quest.priority.rawValue
        skillId = quest.skillId
        dueDate = quest.dueDate?.description
        dueTime = quest.dueTime?.description
        timezoneId = quest.timezoneId
        createdAt = quest.createdAt
    }

    var domain: Quest {
        Quest(
            id: id, title: title, details: details,
            priority: QuestPriority(rawValue: priority) ?? .default,
            skillId: skillId,
            dueDate: dueDate.flatMap(LocalDate.init(string:)),
            dueTime: dueTime.flatMap(LocalTime.init(string:)),
            timezoneId: timezoneId, createdAt: createdAt
        )
    }
}
