import Foundation
import Testing
import Domain
@testable import Application

private struct StubHeroes: HeroRepository {
    var hero: Hero?
    func currentHero() async throws -> Hero? { hero }
}

private actor SpyQuests: QuestRepository {
    var requested: [LocalDate] = []
    func quests(dueOn date: LocalDate) async throws -> [Quest] {
        requested.append(date)
        return []
    }
}

struct TodayServiceTests {
    @Test func asksForQuestsOnUsersLocalDate() async throws {
        let quests = SpyQuests()
        let service = TodayService(heroes: StubHeroes(hero: nil), quests: quests)
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-11-10T22:30:00Z"))
        let overview = try await service.overview(now: instant, timeZone: try #require(TimeZone(identifier: "Europe/Moscow")))
        #expect(overview.date.description == "2026-11-11")
        #expect(await quests.requested == [LocalDate(year: 2026, month: 11, day: 11)])
        #expect(overview.hero == nil)
    }
}
