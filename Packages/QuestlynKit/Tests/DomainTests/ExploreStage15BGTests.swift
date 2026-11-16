import Foundation
import Testing
@testable import Domain

/// Этапы 15B и 15G: старт и финальная башня, сектора навыков, памятники Epic, монументы полезного, болото.
struct ExploreStage15BGTests {
    let utc = TimeZone(identifier: "UTC")!
    let last = LocalDate(year: 2026, month: 11, day: 10)

    func input(days: Int) -> ExploreInput {
        let first = last.adding(days: -(days - 1))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var events: [ExploreEvent] = []
        var random = ExploreRandom(3)
        for day in 0..<days {
            let date = first.adding(days: day)
            let noon = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 12))!
            for _ in 0..<2 { events.append(ExploreEvent(title: "Встреча \(random.int(12))", start: noon, minutes: 30, attendeeKeys: ["p\(random.int(10))"])) }
        }
        let gains = [ExploreSkillGain(title: "Бег", gains: [first: 120]), ExploreSkillGain(title: "Swift", gains: [first.adding(days: 1): 40]),
                     ExploreSkillGain(title: "Гитара", gains: [:])]
        let epic = ExploreClosedEpic(title: "Сайт", steps: 5, started: first.adding(days: -20), closed: first.adding(days: 2))
        let harms = (0..<6).map { first.adding(days: $0) }
        let benefits: [(date: LocalDate, buff: ExploreBuff)] = [(first, .water), (first.adding(days: 1), .water), (first, .walk)]
        return ExploreInput(first: first, last: last, events: events, quests: [], nights: [:], weekMoods: [:], hasCalendar: true, timeZone: utc)
            .with(skillGains: gains, closedEpics: [epic], harmDays: harms, benefits: benefits)
    }

    @Test func startsOnNorthWestShoreAndEndsAtFinalTower() throws {
        let data = input(days: 10)
        let island = IslandGenerator.generate(data, seed: 4)
        let start = island.start
        #expect(island.isWalkable(start))
        #expect([(1, 0), (-1, 0), (0, 1), (0, -1)].contains { island.terrain(at: TilePoint(start.x + $0.0, start.y + $0.1)) == .water })
        let minX = (0..<(island.side * island.side)).filter { island.isWalkable(TilePoint($0 % island.side, $0 / island.side)) }.map { $0 % island.side }.min()!
        #expect(start.x == minX)
        let finalTower = island.towers.first { $0.isFinal }
        let final = try #require(finalTower)
        #expect(final.guardianHP == ExploreRules.finalTowerHP(days: 10) && final.guardianDamageShare == 0.15)
        #expect(island.path(from: start, to: final.position) != nil)
    }

    @Test func sectorsMonumentsShrinesAndSwamp() {
        let island = IslandGenerator.generate(input(days: 10), seed: 4)
        #expect(island.sectors.map(\.title) == ["Бег", "Swift", "Гитара"])
        #expect(island.sectors.map(\.isWaste) == [false, false, true])
        #expect(island.sector(at: island.sectors[0].sign)?.title == "Бег")
        #expect(island.monuments.map(\.epic.title) == ["Сайт"])
        #expect(Set(island.shrines.map(\.buff)) == [.water, .walk])
        #expect(island.shrines.first { $0.buff == .water }?.strength == 0.2)
        // Болото: 6 вредных − 3 полезных = 3 пятна; не на дорогах и не у старта.
        let swamp = (0..<island.swamp.count).filter { island.swamp[$0] }.map { TilePoint($0 % island.side, $0 / island.side) }
        #expect(!swamp.isEmpty)
        #expect(swamp.allSatisfy { island.road(at: $0) == nil && island.isWalkable($0) })
        #expect(ExploreBuff.water.effect(1) == "+0,5% HP в секунду" && ExploreBuff.walk.effect(0.5) == "скорость +10%")
    }

    @Test func buffsChangeFightNumbers() {
        var levels: [Attribute: Int] = [:]
        for a in Attribute.allCases { levels[a] = 1 }
        let hero = ExploreHero(levels: levels, hp: 100, maxHP: 100, mp: 100, maxMP: 100, rankLetter: "G", skills: [])
        var plain = Encounter(tier: .regular, hero: hero, heroHP: 100, heroMP: 100, seed: 9)
        var calm = Encounter(tier: .regular, hero: hero, heroHP: 100, heroMP: 100, seed: 9)
        calm.damageTakenFactor = 0.75
        plain.perform(.fight)
        calm.perform(.fight)
        #expect(abs((100 - calm.heroHP) - (100 - plain.heroHP) * 0.75) <= 1)
        var fight = ActiveFight(tier: .regular, hero: hero, heroHP: 100, heroMP: 100, seed: 9)
        fight.cooldownFactor = 0.7
        #expect(abs(fight.abilityCooldown - Double(hero.cooldown) * ExploreRules.activeTurnSeconds * 0.7) < 0.0001)
    }
}
