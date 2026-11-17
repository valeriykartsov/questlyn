import Foundation
import Testing
@testable import Domain

/// Этап 15E: один корабль, квест на стартовом острове, море — шторма, течения, обломки, встречные корабли, змей.
struct ExploreStage15ETests {
    let utc = TimeZone(identifier: "UTC")!
    let last = LocalDate(year: 2026, month: 11, day: 10)

    func input(days: Int = 60) -> ExploreInput {
        let first = last.adding(days: -(days - 1))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var events: [ExploreEvent] = []
        var nights: [LocalDate: Double] = [:]
        for day in 0..<days {
            let date = first.adding(days: day)
            for k in 0..<3 {
                let start = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 9 + k))!
                events.append(ExploreEvent(title: ["Стендап", "Ретро", "Кино"][k], start: start, minutes: 30, attendeeKeys: ["p\((day + k) % 9)"]))
            }
            nights[date] = day % 4 == 0 ? 0.2 : 0.8
        }
        var data = ExploreInput(first: first, last: last, events: events, quests: [], nights: nights, weekMoods: [:], hasCalendar: true, timeZone: utc)
        data.habits = [ExploreHabitDays(title: "Зарядка", days: Set((0..<days).map { first.adding(days: $0) }))]
        data = data.with(doneQuests: (0..<30).map { ExploreDoneQuest(title: "Квест \($0)", priority: .medium, minutes: 30, date: first.adding(days: $0 * 2)) })
        data.epics = [ExploreEpic(title: "Сайт", steps: 4, dates: [last.adding(days: -3)]),
                      ExploreEpic(title: "Книга", steps: 6, dates: [last.adding(days: -1)])]
        data.closedEpics = [ExploreClosedEpic(title: "Книга", steps: 6, started: first, closed: last)]
        return data
    }

    @Test func oneShipAndQuestMonstersOnStartIsland() {
        let island = IslandGenerator.generate(input(), seed: 3)
        #expect(island.regions.count > 1)
        #expect(island.ships.count == 1)
        let ship = island.ships[0]
        #expect(!island.isLand(ship.position) && island.landing(near: ship.position).map { island.regions[0].contains($0) } == true)
        let monsters = island.npcs.filter { !$0.isPeaceful && island.regions[0].contains($0.home) }
        #expect(monsters.count >= ExploreRules.shipQuestKills)
        #expect(monsters.allSatisfy { $0.home.distance(to: ship.position) >= ExploreRules.harbourRadius })
    }

    @Test func seaEventsComeFromData() {
        let data = input()
        let island = IslandGenerator.generate(data, seed: 3)
        // Шторма — из плохих ночей, не больше 3 на главу, в воде.
        #expect(!island.storms.isEmpty && island.storms.count <= ExploreRules.stormCap * island.regions.count)
        #expect(island.storms.allSatisfy { !island.isLand($0.center) })
        // Течения — серия «Зарядки», между соседними островами, по воде.
        #expect(!island.currents.isEmpty && island.currents.allSatisfy { $0.title == "Зарядка" && $0.tiles.allSatisfy { !island.isLand($0) } })
        // Обломки — одни на 3 выполненных квеста, в воде, 1–2 доски.
        #expect(!island.wrecks.isEmpty && island.wrecks.count <= 30 / ExploreRules.wreckQuests)
        #expect(island.wrecks.allSatisfy { !island.isLand($0.position) && (1...2).contains($0.planks) })
        // Встречные — по одному на пролив.
        #expect(island.traders.count == island.regions.count - 1)
        // Змей — незакрытый Epic с самым дальним сроком («Книга» закрыта).
        #expect(island.serpent?.title == "Сайт" && island.serpent.map { !island.isLand($0.position) } == true)
        #expect(island.serpent?.hp == ExploreRules.serpentBaseHP + 4 * ExploreRules.serpentHPPerStep)
    }

    @Test func singleChapterHasNoSea() {
        let island = IslandGenerator.generate(input(days: 15), seed: 1)
        #expect(island.regions.count == 1 && island.ships.isEmpty && island.storms.isEmpty && island.serpent == nil)
    }

    @Test func upgradesCost14Planks() {
        #expect(ShipUpgrade.allCases.map(\.planks).reduce(0, +) == 14)
    }
}
