import Foundation

// Сущности этапа 1. Поля и инварианты — Product/03_DOMAIN_MODEL.md.

public struct Hero: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var classTitle: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, classTitle: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.classTitle = classTitle
        self.createdAt = createdAt
    }
}

public struct Profession: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var heroId: UUID
    public var title: String
    /// 1 — основная профессия.
    public var slot: Int
    /// Атрибуты по порядку: основной, вторичный, третичный.
    public var attributes: [Attribute]
    public var catalogItemId: String?
    public var catalogVersion: String?
    public var isActive: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(), heroId: UUID, title: String, slot: Int, attributes: [Attribute],
        catalogItemId: String? = nil, catalogVersion: String? = nil, isActive: Bool = true, createdAt: Date
    ) {
        self.id = id
        self.heroId = heroId
        self.title = title
        self.slot = slot
        self.attributes = attributes
        self.catalogItemId = catalogItemId
        self.catalogVersion = catalogVersion
        self.isActive = isActive
        self.createdAt = createdAt
    }

    /// Инвариант: 1–3 атрибута без повторов, без FOC и DIS (02).
    public var hasValidAttributes: Bool {
        (1...3).contains(attributes.count)
            && Set(attributes).count == attributes.count
            && attributes.allSatisfy(\.isSelectableForProfession)
    }
}

public struct Skill: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var professionId: UUID
    public var title: String
    public var isActive: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), professionId: UUID, title: String, isActive: Bool = true, createdAt: Date) {
        self.id = id
        self.professionId = professionId
        self.title = title
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

public struct Quest: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var details: String?
    public var priority: QuestPriority
    public var skillId: UUID?
    public var dueDate: LocalDate?
    /// Только вместе с `dueDate`.
    public var dueTime: LocalTime?
    public var timezoneId: String
    /// Шаг Epic: квест принадлежит не более чем одному Epic (02).
    public var epicId: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(), title: String, details: String? = nil, priority: QuestPriority = .default,
        skillId: UUID? = nil, dueDate: LocalDate? = nil, dueTime: LocalTime? = nil,
        timezoneId: String, epicId: UUID? = nil, createdAt: Date
    ) {
        self.epicId = epicId
        self.id = id
        self.title = title
        self.details = details
        self.priority = priority
        self.skillId = skillId
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.timezoneId = timezoneId
        self.createdAt = createdAt
    }
}

/// Снимок состава профессии навыка на момент выполнения (03: рабочая гипотеза).
public struct ClassSnapshot: Hashable, Codable, Sendable {
    public struct Entry: Hashable, Codable, Sendable {
        public var attribute: Attribute
        /// Class Multiplier в четвертях: 4 → ×1,0; 5 → ×1,25; 6 → ×1,5.
        public var multiplierInQuarters: Int

        public init(attribute: Attribute, multiplierInQuarters: Int) {
            self.attribute = attribute
            self.multiplierInQuarters = multiplierInQuarters
        }
    }

    public var professionId: UUID?
    public var entries: [Entry]

    public init(professionId: UUID?, entries: [Entry]) {
        self.professionId = professionId
        self.entries = entries
    }

    public static let empty = ClassSnapshot(professionId: nil, entries: [])
}

/// Факт: выполнение квеста. `id` — это `sourceId` начислений.
public struct QuestCompletion: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var questId: UUID
    public var completedAt: Date
    public var localDate: LocalDate
    public var timezoneId: String
    public var undoneAt: Date?
    public var classSnapshot: ClassSnapshot

    public init(
        id: UUID = UUID(), questId: UUID, completedAt: Date, localDate: LocalDate,
        timezoneId: String, undoneAt: Date? = nil, classSnapshot: ClassSnapshot
    ) {
        self.id = id
        self.questId = questId
        self.completedAt = completedAt
        self.localDate = localDate
        self.timezoneId = timezoneId
        self.undoneAt = undoneAt
        self.classSnapshot = classSnapshot
    }

    public var isActive: Bool { undoneAt == nil }
}

public enum GrantSourceType: String, Codable, Sendable {
    case questCompletion
    case habitOccurrence
    case weeklyDiscipline
}

public enum GrantTarget: Hashable, Codable, Sendable {
    case attribute(Attribute)
    case skill(UUID)
}

/// Производное начисление прогресса (07, раздел 1).
public struct ProgressGrant: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sourceType: GrantSourceType
    public var sourceId: UUID
    public var ruleVersion: RuleVersion
    public var target: GrantTarget
    public var amount: CentiXP
    /// Причина для объяснимости — текст экрана «Квест выполнен».
    public var reason: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(), sourceType: GrantSourceType, sourceId: UUID, ruleVersion: RuleVersion,
        target: GrantTarget, amount: CentiXP, reason: String, createdAt: Date
    ) {
        self.id = id
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.ruleVersion = ruleVersion
        self.target = target
        self.amount = amount
        self.reason = reason
        self.createdAt = createdAt
    }
}
