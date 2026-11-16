import Foundation
import Testing
@testable import Domain

/// Этап 15A: мир ×3, горы, климат, дороги и погода прогулки.
struct ExploreStage15Tests {
    let utc = TimeZone(identifier: "UTC")!
    let last = LocalDate(year: 2026, month: 11, day: 10)

    func input(days: Int, habits: [ExploreHabitDays] = [], moods: [ExploreMood] = []) -> ExploreInput {
        let first = last.adding(days: -(days - 1))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var events: [ExploreEvent] = []
        var random = ExploreRandom(7)
        for day in 0..<days {
            let date = first.adding(days: day)
            let noon = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 12))!
            for _ in 0..<2 {
                events.append(ExploreEvent(title: "Встреча \(random.int(16))", start: noon, minutes: 30, attendeeKeys: ["p\(random.int(20))"]))
            }
        }
        let quests = (0..<20).map { (title: "Квест \($0)", priority: QuestPriority.medium, date: Optional(first.adding(days: $0 % days))) }
        var nights: [LocalDate: Double] = [:]
        for day in 0..<days { nights[first.adding(days: day)] = 0.7 }
        return ExploreInput(first: first, last: last, events: events, quests: quests, nights: nights, weekMoods: [:], hasCalendar: true, timeZone: utc)
            .with(diary: [], epics: [], habits: habits)
            .with(moods: moods)
    }

    @Test func areaIsThreeTimesLarger() {
        #expect(IslandSize.small.tiles == 83 && IslandSize.medium.tiles == 125 && IslandSize.large.tiles == 166)
        for size in IslandSize.allCases {
            let old = [IslandSize.small: 48.0, .medium: 72, .large: 96][size]!
            #expect(abs(Double(size.tiles * size.tiles) / (old * old) - 3) < 0.03)
        }
    }

    @Test func mountainsStayInlandAndEverythingIsReachable() {
        let data = input(days: 40)
        let island = IslandGenerator.generate(data, seed: data.seed(attempt: 0))
        let side = island.side
        var mountains = 0
        for y in 0..<side { for x in 0..<side where island.terrain(at: TilePoint(x, y)) == .mountain {
            mountains += 1
            #expect(island.height(at: TilePoint(x, y)) >= 2)
            #expect(![(1, 0), (-1, 0), (0, 1), (0, -1)].contains { island.terrain(at: TilePoint(x + $0.0, y + $0.1)) == .water })
        } }
        #expect(mountains > 0)
        // С каждого острова-месяца пешком доступно всё: города, деревни, сундуки, костры.
        for region in island.regions {
            let places = (island.cities + island.villages).map(\.center) + island.chests.map(\.position) + island.campfires.map(\.position)
            let mine = places.filter { region.contains($0) }
            guard let from = mine.first else { continue }
            for place in mine { #expect(island.path(from: from, to: place) != nil) }
        }
    }

    @Test func roadsJoinCitiesOverWalkableLand() {
        let data = input(days: 40)
        let island = IslandGenerator.generate(data, seed: data.seed(attempt: 1))
        for region in island.regions {
            let cities = island.cities.filter { region.contains($0.center) }
            let roads = island.roads.filter { region.contains($0.tiles[0]) }
            #expect(roads.count >= max(0, cities.count - 1))
        }
        for road in island.roads {
            let from = island.cities[road.from].center, to = island.cities[road.to].center
            #expect(road.tiles.first == from && road.tiles.last == to)
            #expect(road.tiles.allSatisfy { island.isWalkable($0) })
            #expect(road.habit == nil && road.wear == .dirt)
            #expect(island.road(at: road.tiles[road.tiles.count / 2]) != nil)
        }
    }

    @Test func roadWearFollowsHabitPercent() {
        #expect(RoadWear.of(percent: 92) == .paved && RoadWear.of(percent: 80) == .paved)
        #expect(RoadWear.of(percent: 64) == .dirt && RoadWear.of(percent: 34) == .overgrown && RoadWear.of(percent: 12) == .faint)
        let first = last.adding(days: -9)
        // Запланированы 10 дней, отмечены 8 — 80%.
        let planned = Set((0..<10).map { first.adding(days: $0) })
        let habit = ExploreHabitDays(title: "Зарядка", days: Set((0..<8).map { first.adding(days: $0) }), planned: planned)
        #expect(habit.percent(from: first, through: last) == 80)
        #expect(ExploreHabitDays(title: "Нет", days: [], planned: []).percent(from: first, through: last) == nil)
        let data = input(days: 10, habits: [habit])
        let island = IslandGenerator.generate(data, seed: 3)
        #expect(!island.roads.isEmpty)
        #expect(island.roads.allSatisfy { $0.habit == "Зарядка" && $0.percent == 80 && $0.wear == .paved })
        #expect(island.roads[0].caption == "Дорога «Зарядка» · 80% · мощёная")
        #expect(RoadWear.paved.speedFactor == 1.3 && RoadWear.dirt.speedFactor == 1.15 && RoadWear.faint.speedFactor == 1)
    }

    @Test func climateRunsFromNorthToSouth() {
        let data = input(days: 40)
        let island = IslandGenerator.generate(data, seed: 5)
        let side = island.side
        #expect(island.zone(at: TilePoint(0, 0)) == .tundra)
        #expect(island.zone(at: TilePoint(side - 1, side - 1)) == .desert)
        #expect(island.zone(at: TilePoint(side / 2, side / 2)) == .temperate)
        #expect(ClimateZone.tundra.isCold && !ClimateZone.desert.isCold)
    }

    @Test func weatherIsRandomMoodOfMonth() {
        let first = last.adding(days: -9)
        let bad = (0..<5).map { ExploreMood(date: first.adding(days: $0), mood: .bad) }
        #expect(IslandGenerator.generate(input(days: 10, moods: bad), seed: 1).regionWeather == [.rain])
        let neutral = [ExploreMood(date: first, mood: .neutral)]
        #expect(IslandGenerator.generate(input(days: 10, moods: neutral), seed: 1).regionWeather == [.cloudy])
        #expect(IslandGenerator.generate(input(days: 10), seed: 1).regionWeather == [.clear])
        // Отметки другого месяца не влияют.
        let other = [ExploreMood(date: first.adding(days: -40), mood: .bad)]
        #expect(IslandGenerator.generate(input(days: 10, moods: other), seed: 1).regionWeather == [.clear])
    }
}
