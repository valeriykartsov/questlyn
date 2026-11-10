/// Каталог предустановленных профессий (02). Лежит в бандле с версией:
/// при выборе атрибуты копируются в профессию пользователя, поэтому обновление каталога не меняет историю.
public struct ProfessionCatalogItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    /// Основной, вторичный, третичный.
    public let attributes: [Attribute]
}

public enum ProfessionCatalog {
    public static let version = "1"

    /// Стартовый набор — только профессии, подтверждённые в 02 (H1). Расширение до 20–30 — этап 3.5.
    public static let items: [ProfessionCatalogItem] = [
        .init(id: "software-engineer", title: "Инженер-программист", attributes: [.intelligence, .mentality, .charisma]),
        .init(id: "athlete", title: "Атлет", attributes: [.strength, .endurance, .mentality]),
        .init(id: "project-manager", title: "Менеджер проектов", attributes: [.charisma, .mentality, .intelligence]),
        .init(id: "basketball-player", title: "Баскетболист", attributes: [.endurance, .strength, .mentality]),
        .init(id: "prompt-engineer", title: "Промпт-инженер", attributes: [.intelligence, .mentality, .charisma]),
    ]

    public static func item(id: String) -> ProfessionCatalogItem? {
        items.first { $0.id == id }
    }
}
