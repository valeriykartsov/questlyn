import Foundation
import Domain

/// Данные экрана «Сегодня».
public struct TodayOverview: Sendable, Equatable {
    public var date: LocalDate
    public var hero: Hero?
    public var quests: [Quest]
}

/// Use case: собрать «Сегодня» на локальную дату пользователя.
public struct TodayService: Sendable {
    private let heroes: any HeroRepository
    private let quests: any QuestRepository

    public init(heroes: any HeroRepository, quests: any QuestRepository) {
        self.heroes = heroes
        self.quests = quests
    }

    public func overview(now: Date, timeZone: TimeZone) async throws -> TodayOverview {
        let date = LocalDate(now, timeZone: timeZone)
        return TodayOverview(
            date: date,
            hero: try await heroes.currentHero(),
            quests: try await quests.quests(dueOn: date)
        )
    }
}
