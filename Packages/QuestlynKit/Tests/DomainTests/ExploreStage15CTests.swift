import Foundation
import Testing
@testable import Domain

/// Этап 15C: карта сокровищ, пещеры, смотровые площадки.
struct ExploreStage15CTests {
    let utc = TimeZone(identifier: "UTC")!
    let last = LocalDate(year: 2026, month: 11, day: 10)

    func input(days: Int, done: [ExploreDoneQuest]) -> ExploreInput {
        let first = last.adding(days: -(days - 1))
        let quests = (0..<24).map { (title: "Квест \($0)", priority: QuestPriority.medium, date: Optional(first.adding(days: $0 * days / 24))) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var events: [ExploreEvent] = []
        for day in 0..<days {
            let date = first.adding(days: day)
            let noon = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 12))!
            events.append(ExploreEvent(title: "Встреча \(day % 6)", start: noon, minutes: 30, attendeeKeys: ["p\(day % 5)"]))
        }
        return ExploreInput(first: first, last: last, events: events, quests: quests, nights: [:], weekMoods: [:], hasCalendar: true, timeZone: utc)
            .with(doneQuests: done)
    }

    @Test func treasureIsMainQuestWithFragmentsOnDifferentIslands() {
        let done = [ExploreDoneQuest(title: "Отчёт", priority: .medium, minutes: 200),
                    ExploreDoneQuest(title: "Запуск сайта", priority: .high, minutes: 60),
                    ExploreDoneQuest(title: "Звонок", priority: .high, minutes: 30)]
        let data = input(days: 70, done: done)
        #expect(data.treasureQuest?.title == "Запуск сайта")
        let island = IslandGenerator.generate(data, seed: 2)
        let treasure = island.treasure
        #expect(treasure?.title == "Запуск сайта")
        let fragments = island.chests.filter { $0.fragment != nil }
        #expect(fragments.count == ExploreRules.treasureFragments)
        #expect(Set(fragments.compactMap(\.fragment)) == [0, 1, 2])
        let chestRegions = Set(island.chests.compactMap { island.region(at: $0.position)?.id })
        #expect(Set(fragments.compactMap { island.region(at: $0.position)?.id }).count == min(3, chestRegions.count))
        #expect(fragments.allSatisfy { $0.position.distance(to: island.start) > 8 })
        for region in island.regions {
            guard let spot = treasure?.spots[region.id] else { continue }
            #expect(region.contains(spot) && island.isWalkable(spot))
            #expect(island.cities.allSatisfy { $0.center.distance(to: spot) >= 10 })
        }
        // Без выполненных квестов клада нет.
        #expect(IslandGenerator.generate(input(days: 10, done: []), seed: 2).treasure == nil)
    }

    @Test func cavesAndLookouts() {
        let island = IslandGenerator.generate(input(days: 70, done: []), seed: 5)
        #expect(!island.lookouts.isEmpty)
        #expect(island.lookouts.allSatisfy { island.isWalkable($0.position) })
        for cave in island.caves {
            #expect(cave.entrance.distance(to: cave.exit) >= ExploreRules.caveMinSpan)
            #expect(island.isWalkable(cave.entrance) && island.isWalkable(cave.exit))
            #expect(island.region(at: cave.entrance)?.id == cave.region && island.region(at: cave.exit)?.id == cave.region)
            // Внутри всё достижимо от входа.
            #expect(cave.path(from: cave.start, to: cave.inner) != nil)
            #expect(cave.chests.count == ExploreRules.caveChests && cave.items.count == cave.chests.count)
            #expect(cave.chests.allSatisfy { cave.path(from: cave.start, to: $0) != nil })
        }
        #expect(!island.caves.isEmpty)
    }
}
