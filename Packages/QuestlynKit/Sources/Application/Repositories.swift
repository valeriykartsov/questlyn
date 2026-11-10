import Domain

/// Порты хранения. Реализации — в Persistence.
public protocol HeroRepository: Sendable {
    func currentHero() async throws -> Hero?
}

public protocol QuestRepository: Sendable {
    func quests(dueOn date: LocalDate) async throws -> [Quest]
}
