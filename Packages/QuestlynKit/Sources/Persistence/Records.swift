import Foundation
import GRDB
import Domain

// Записи таблиц. Domain не знает про GRDB, поэтому соответствие — здесь.

protocol QuestlynRecord: Codable, FetchableRecord, PersistableRecord, Sendable {}

extension QuestlynRecord {
    /// UUID хранятся строкой в нижнем регистре: так их можно сравнивать в SQL и читать глазами.
    static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }
}

struct HeroRecord: QuestlynRecord {
    static let databaseTableName = "hero"
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

struct ProfessionRecord: QuestlynRecord {
    static let databaseTableName = "profession"
    var id: UUID
    var heroId: UUID
    var title: String
    var slot: Int
    var catalogItemId: String?
    var catalogVersion: String?
    var isActive: Bool
    var createdAt: Date

    init(_ p: Profession) {
        id = p.id
        heroId = p.heroId
        title = p.title
        slot = p.slot
        catalogItemId = p.catalogItemId
        catalogVersion = p.catalogVersion
        isActive = p.isActive
        createdAt = p.createdAt
    }

    func domain(attributes: [Attribute]) -> Profession {
        Profession(id: id, heroId: heroId, title: title, slot: slot, attributes: attributes,
                   catalogItemId: catalogItemId, catalogVersion: catalogVersion, isActive: isActive, createdAt: createdAt)
    }
}

struct ProfessionAttributeRecord: QuestlynRecord {
    static let databaseTableName = "professionAttribute"
    var professionId: UUID
    var position: Int
    var attribute: String
}

struct SkillRecord: QuestlynRecord {
    static let databaseTableName = "skill"
    var id: UUID
    var professionId: UUID
    var title: String
    var isActive: Bool
    var createdAt: Date

    init(_ s: Skill) {
        id = s.id
        professionId = s.professionId
        title = s.title
        isActive = s.isActive
        createdAt = s.createdAt
    }

    var domain: Skill { Skill(id: id, professionId: professionId, title: title, isActive: isActive, createdAt: createdAt) }
}

struct QuestRecord: QuestlynRecord {
    static let databaseTableName = "quest"
    var id: UUID
    var title: String
    var details: String?
    var priority: String
    var skillId: UUID?
    var dueDate: String?
    var dueTime: String?
    var timezoneId: String
    var epicId: UUID?
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
        epicId = quest.epicId
        createdAt = quest.createdAt
    }

    var domain: Quest {
        Quest(
            id: id, title: title, details: details,
            priority: QuestPriority(rawValue: priority) ?? .default,
            skillId: skillId,
            dueDate: dueDate.flatMap(LocalDate.init(string:)),
            dueTime: dueTime.flatMap(LocalTime.init(string:)),
            timezoneId: timezoneId, epicId: epicId, createdAt: createdAt
        )
    }
}

struct QuestCompletionRecord: QuestlynRecord {
    static let databaseTableName = "questCompletion"
    var id: UUID
    var questId: UUID
    var completedAt: Date
    var localDate: String
    var timezoneId: String
    var undoneAt: Date?
    var classSnapshot: ClassSnapshot

    init(_ c: QuestCompletion) {
        id = c.id
        questId = c.questId
        completedAt = c.completedAt
        localDate = c.localDate.description
        timezoneId = c.timezoneId
        undoneAt = c.undoneAt
        classSnapshot = c.classSnapshot
    }

    var domain: QuestCompletion? {
        guard let date = LocalDate(string: localDate) else { return nil }
        return QuestCompletion(id: id, questId: questId, completedAt: completedAt, localDate: date,
                               timezoneId: timezoneId, undoneAt: undoneAt, classSnapshot: classSnapshot)
    }
}

struct ProgressGrantRecord: QuestlynRecord {
    static let databaseTableName = "progressGrant"
    var id: UUID
    var sourceType: String
    var sourceId: UUID
    var ruleVersion: String
    var targetKind: String
    var attribute: String?
    var skillId: UUID?
    var targetKey: String
    var amountCenti: Int
    var reason: String
    var createdAt: Date

    init(_ g: ProgressGrant) {
        id = g.id
        sourceType = g.sourceType.rawValue
        sourceId = g.sourceId
        ruleVersion = g.ruleVersion.rawValue
        switch g.target {
        case .attribute(let a):
            targetKind = "attribute"
            attribute = a.rawValue
            skillId = nil
            targetKey = "attribute:\(a.rawValue)"
        case .skill(let id):
            targetKind = "skill"
            attribute = nil
            skillId = id
            targetKey = "skill:\(id.uuidString.lowercased())"
        }
        amountCenti = g.amount.value
        reason = g.reason
        createdAt = g.createdAt
    }

    var domain: ProgressGrant? {
        guard let source = GrantSourceType(rawValue: sourceType) else { return nil }
        let target: GrantTarget
        if targetKind == "skill", let skillId {
            target = .skill(skillId)
        } else if let attribute, let a = Attribute(rawValue: attribute) {
            target = .attribute(a)
        } else {
            return nil
        }
        return ProgressGrant(id: id, sourceType: source, sourceId: sourceId, ruleVersion: RuleVersion(rawValue: ruleVersion),
                             target: target, amount: CentiXP(amountCenti), reason: reason, createdAt: createdAt)
    }
}

struct EpicRecord: QuestlynRecord {
    static let databaseTableName = "epic"
    var id: UUID
    var title: String
    var details: String?
    var deadline: String?
    var completedAt: Date?
    var createdAt: Date

    init(_ e: EpicQuest) {
        id = e.id
        title = e.title
        details = e.details
        deadline = e.deadline?.description
        completedAt = e.completedAt
        createdAt = e.createdAt
    }

    var domain: EpicQuest {
        EpicQuest(id: id, title: title, details: details, deadline: deadline.flatMap(LocalDate.init(string:)),
                  completedAt: completedAt, createdAt: createdAt)
    }
}

struct HabitRecord: QuestlynRecord {
    static let databaseTableName = "habit"
    var id: UUID
    var kind: String
    var title: String
    var details: String?
    var skillId: UUID?
    var weekdays: String
    var targetPerWeek: Int
    var time: String?
    var timezoneId: String
    var startDate: String
    var isActive: Bool
    var createdAt: Date

    init(_ h: HabitDefinition) {
        id = h.id
        kind = h.kind.rawValue
        title = h.title
        details = h.details
        skillId = h.skillId
        weekdays = h.weekdays.sorted().map { String($0.rawValue) }.joined(separator: ",")
        targetPerWeek = h.targetPerWeek
        time = h.time?.description
        timezoneId = h.timezoneId
        startDate = h.startDate.description
        isActive = h.isActive
        createdAt = h.createdAt
    }

    var domain: HabitDefinition? {
        guard let kind = HabitKind(rawValue: kind), let start = LocalDate(string: startDate) else { return nil }
        let days = Set(weekdays.split(separator: ",").compactMap { Int($0).flatMap(Weekday.init(rawValue:)) })
        return HabitDefinition(id: id, kind: kind, title: title, details: details, skillId: skillId, weekdays: days,
                               targetPerWeek: targetPerWeek, time: time.flatMap(LocalTime.init(string:)),
                               timezoneId: timezoneId, startDate: start, isActive: isActive, createdAt: createdAt)
    }
}

struct HabitOccurrenceRecord: QuestlynRecord {
    static let databaseTableName = "habitOccurrence"
    var id: UUID
    var habitId: UUID
    var localDate: String
    var completedAt: Date
    var timezoneId: String
    var undoneAt: Date?
    var classSnapshot: ClassSnapshot

    init(_ o: HabitOccurrence) {
        id = o.id
        habitId = o.habitId
        localDate = o.localDate.description
        completedAt = o.completedAt
        timezoneId = o.timezoneId
        undoneAt = o.undoneAt
        classSnapshot = o.classSnapshot
    }

    var domain: HabitOccurrence? {
        guard let date = LocalDate(string: localDate) else { return nil }
        return HabitOccurrence(id: id, habitId: habitId, localDate: date, completedAt: completedAt,
                               timezoneId: timezoneId, undoneAt: undoneAt, classSnapshot: classSnapshot)
    }
}
