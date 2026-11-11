import Foundation

// Сущности этапа 1. Поля и инварианты — Product/03_DOMAIN_MODEL.md.

public struct Hero: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var classTitle: String
    public var appearance: HeroAppearance
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, classTitle: String, appearance: HeroAppearance = .default, createdAt: Date) {
        self.id = id
        self.name = name
        self.classTitle = classTitle
        self.appearance = appearance
        self.createdAt = createdAt
    }
}

/// Внешность героя (02): волосы, кожа и образ на выбор; цвет акцента одежды — по основной профессии.
public struct HeroAppearance: Hashable, Codable, Sendable {
    public enum Hair: String, CaseIterable, Codable, Sendable { case dark, red, blond, black }
    public enum Skin: String, CaseIterable, Codable, Sendable { case light, medium, tan, deep }
    /// Образ героя (02, 10.11.2026): выбирается на шаге «Класс», меняется в настройках. На начисления не влияет.
    public enum Outfit: String, CaseIterable, Codable, Sendable {
        case mage, warrior, archer, assassin, baller, coder
        /// Добавлены 11.11.2026 (холст 8.10).
        case sage, illusionist, master

        public var title: String {
            switch self {
            case .mage: "Маг"
            case .warrior: "Воин"
            case .archer: "Лучник"
            case .assassin: "Ассасин"
            case .baller: "Баскетболист"
            case .coder: "Программист"
            case .sage: "Мудрец"
            case .illusionist: "Иллюзионист"
            case .master: "Мастер"
            }
        }
    }

    /// Низ: деталь одного из образов или латная юбка (12.11.2026).
    public enum Bottom: Hashable, Codable, Sendable, RawRepresentable {
        case outfit(Outfit)
        case plateSkirt

        public init?(rawValue: String) {
            if rawValue == "plateSkirt" { self = .plateSkirt } else if let outfit = Outfit(rawValue: rawValue) { self = .outfit(outfit) } else { return nil }
        }
        public var rawValue: String {
            switch self {
            case let .outfit(outfit): outfit.rawValue
            case .plateSkirt: "plateSkirt"
            }
        }
        public var title: String {
            switch self {
            case let .outfit(outfit): outfit.title
            case .plateSkirt: "Латная юбка"
            }
        }
        public static var all: [Bottom] { Outfit.allCases.map(Bottom.outfit) + [.plateSkirt] }
    }

    /// Детали героя (10.1): каждая — из одного из девяти образов; головной убор необязателен.
    public struct Parts: Hashable, Codable, Sendable {
        public var hair: Outfit
        public var hat: Outfit?
        public var top: Outfit
        public var bottom: Bottom
        public var shoes: Outfit
        public var item: Outfit

        public init(hair: Outfit, hat: Outfit? = nil, top: Outfit, bottom: Bottom, shoes: Outfit, item: Outfit) {
            self.hair = hair
            self.hat = hat
            self.top = top
            self.bottom = bottom
            self.shoes = shoes
            self.item = item
        }

        /// Готовый набор — все детали одного образа.
        public static func preset(_ outfit: Outfit) -> Parts {
            Parts(hair: outfit, top: outfit, bottom: .outfit(outfit), shoes: outfit, item: outfit)
        }
    }

    public var hair: Hair
    public var skin: Skin
    /// Готовый образ — с него начинается настройка; без своих деталей герой рисуется этим образом.
    public var outfit: Outfit
    /// Свои детали (nil — набор образа `outfit`).
    public var parts: Parts?
    /// Свой цвет акцента одежды (nil — цвет основной профессии).
    public var accent: UInt32?

    public init(hair: Hair, skin: Skin, outfit: Outfit = .coder, parts: Parts? = nil, accent: UInt32? = nil) {
        self.hair = hair
        self.skin = skin
        self.outfit = outfit
        self.parts = parts
        self.accent = accent
    }

    public var resolvedParts: Parts { parts ?? .preset(outfit) }

    /// Как в макетах OnbHero и OnbClassLook: тёмные волосы, средняя кожа, программист.
    public static let `default` = HeroAppearance(hair: .dark, skin: .medium, outfit: .coder)
}

/// Самооценка мастерства навыка 1–5 — факт, меняется только вручную (07, раздел 6).
public struct SkillMastery: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var skillId: UUID
    public var value: Int
    public var assessedAt: Date

    public init(id: UUID = UUID(), skillId: UUID, value: Int, assessedAt: Date) {
        self.id = id
        self.skillId = skillId
        self.value = min(max(value, 1), 5)
        self.assessedAt = assessedAt
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
    /// Привязанный вид активности (`ActivityTemplate.id`): один к одному (02, 11.11.2026). Подставляет навык в «Новой активности».
    public var activityTemplateId: String?
    /// Удалён пользователем (8C.6): скрыт везде, XP и Летопись остаются.
    public var deletedAt: Date?

    public init(id: UUID = UUID(), professionId: UUID, title: String, isActive: Bool = true, createdAt: Date,
                activityTemplateId: String? = nil, deletedAt: Date? = nil) {
        self.deletedAt = deletedAt
        self.activityTemplateId = activityTemplateId
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
    /// Удалён (вместе с Epic или из его редактирования). Выполнения и начисления остаются — прогресс не отнимается.
    public var deletedAt: Date?
    /// Длительность, минуты (9.1): 15–180, необязательна; на XP не влияет.
    public var durationMinutes: Int?

    public init(
        id: UUID = UUID(), title: String, details: String? = nil, priority: QuestPriority = .default,
        skillId: UUID? = nil, dueDate: LocalDate? = nil, dueTime: LocalTime? = nil,
        timezoneId: String, epicId: UUID? = nil, createdAt: Date, deletedAt: Date? = nil, durationMinutes: Int? = nil
    ) {
        self.durationMinutes = durationMinutes
        self.deletedAt = deletedAt
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
    /// Стартовый бонус профессий при создании героя (02, 07).
    case onboardingBonus
    case activity
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
    /// Локальная дата факта (день выполнения, отметки, недели DIS) — по ней считаются спад и форма.
    public var effectiveDate: LocalDate

    public init(
        id: UUID = UUID(), sourceType: GrantSourceType, sourceId: UUID, ruleVersion: RuleVersion,
        target: GrantTarget, amount: CentiXP, reason: String, createdAt: Date, effectiveDate: LocalDate? = nil
    ) {
        self.effectiveDate = effectiveDate ?? LocalDate(createdAt, timeZone: TimeZone(identifier: "UTC")!)
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
