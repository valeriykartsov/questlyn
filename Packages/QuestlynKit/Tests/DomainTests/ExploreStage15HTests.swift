import Foundation
import Testing
@testable import Domain

/// Этап 15H: главы равного объёма, столица, города-территории, мирные NPC, монстры, легенды.
struct ExploreStage15HTests {
    let utc = TimeZone(identifier: "UTC")!
    let last = LocalDate(year: 2026, month: 11, day: 10)

    func noon(_ day: LocalDate, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour))!
    }

    /// Первые 30 дней почти пусты, последние 30 — по 6 событий в день: главы должны разрезать по данным, а не по датам.
    func input(days: Int = 60) -> ExploreInput {
        let first = last.adding(days: -(days - 1))
        var events: [ExploreEvent] = []
        for day in 0..<days {
            let date = first.adding(days: day)
            let count = day < days / 2 ? (day % 5 == 0 ? 1 : 0) : 6
            for k in 0..<count {
                let title = day < days / 2 ? "Разное \(day)" : ["Стендап", "Ретро", "Кино"][k % 3]
                events.append(ExploreEvent(title: title, start: noon(date, hour: 9 + k),
                                           minutes: 30, attendeeKeys: ["p\((day + k) % 12)"]))
            }
        }
        return ExploreInput(first: first, last: last, events: events, quests: [], nights: [:], weekMoods: [:], hasCalendar: true, timeZone: utc)
    }

    @Test func chaptersSplitByDataNotByDates() {
        let data = input()
        let chapters = data.chapters
        #expect(chapters.count == ExploreRules.chapterCount(days: 60))
        // Пустая первая половина — одна длинная глава, плотная вторая — несколько коротких.
        #expect(chapters[0].first.days(until: chapters[0].last) + 1 > 30)
        let weights = chapters.map { data.weight(from: $0.first, through: $0.last) }
        let mean = Double(weights.reduce(0, +)) / Double(weights.count)
        #expect(weights.allSatisfy { abs(Double($0) - mean) <= mean * 0.35 })
        // Без данных — поровну по дням.
        let empty = ExploreInput(first: last.adding(days: -59), last: last, events: [], quests: [], nights: [:], weekMoods: [:], hasCalendar: false)
        #expect(empty.chapters.map { $0.first.days(until: $0.last) + 1 }.allSatisfy { (13...17).contains($0) })
    }

    @Test func capitalIsTheMostFrequentEventFirstAlphabetically() {
        let data = input()
        // «Кино», «Ретро» и «Стендап» поровну по 30+ раз; первое по алфавиту — «Кино».
        let capital = IslandGenerator.capitalTitle(data, chapters: data.chapters)
        #expect(capital?.title == "Кино")
        let island = IslandGenerator.generate(data, seed: 5)
        let capitals = island.cities.filter(\.isCapital)
        #expect(capitals.count == 1 && capitals[0].name == "Кино")
        // Столица — одна на мир: на других островах городов с этим названием нет.
        #expect(island.cities.filter { $0.name == "Кино" }.count == 1)
        #expect(capitals[0].radius > ExploreRules.cityRadius(events: capitals[0].events))
        // Торговец — в столице.
        #expect(island.merchants.contains { capitals[0].contains($0.position) })
    }

    @Test func monstersComeFromDebtsAndZones() {
        var data = input()
        data.overdue = [(title: "Отчёт", priority: .high, due: last.adding(days: -2)), (title: "Звонок", priority: .low, due: last.adding(days: -3))]
        data.habits = [ExploreHabitDays(title: "Зарядка", days: [], planned: nil)]
        data.harmDays = [last, last.adding(days: -1)]
        let island = IslandGenerator.generate(data, seed: 2)
        let kinds = island.npcs.compactMap(\.monster)
        #expect(kinds.filter { $0 == .deadline }.count == 2 * ExploreRules.debtMonsters)
        #expect(island.npcs.contains { $0.monster == .deadline && $0.tier == .regular })
        // «Лень» — одна на 3 пропуска, не больше 8 на остров.
        for region in island.regions {
            let sloths = island.npcs.filter { $0.monster == .sloth && region.contains($0.home) }.count
            #expect(sloths <= ExploreRules.monsterCap && sloths >= min(ExploreRules.monsterCap, region.days / ExploreRules.slothMisses) - 1)
        }
        #expect(kinds.filter { $0 == .lure }.count == 2 * ExploreRules.debtMonsters)
        // Звери — по климату места.
        for npc in island.npcs where npc.monster?.isBeast == true {
            #expect(npc.monster == .beast(island.zone(at: npc.home)))
        }
        let hasBeast = kinds.contains { $0.isBeast }
        #expect(hasBeast)
    }

    @Test func legendsLiveInCitiesAndAreNotOrdinaryNPC() {
        var data = input()
        data.legends = (0..<11).map { ExploreLegendPerson(key: "p\($0)", meetings: 50 - $0) }
        data = data.with(overdue: [], legends: data.legends)
        let island = IslandGenerator.generate(data, seed: 4)
        let legends = island.npcs.filter { $0.legend != nil }
        #expect(legends.count == ExploreRules.legendCount)
        #expect(Set(legends.compactMap(\.legend)) == Set(0..<9))
        #expect(legends.allSatisfy { npc in npc.isPeaceful && island.cities[npc.cityId!].contains(npc.home) })
        // Человек-легенда не дублируется обычным NPC.
        #expect(island.npcs.filter { $0.legend == nil && $0.key == "p0" }.isEmpty)
        #expect(CompanionSkill.of(legends.first { $0.legend == 1 }!) == .legend(.warrior))
    }

    @Test func talkChanceGrowsWithHelpAndCharisma() {
        var npc = IslandNPC(id: 0, tier: .colleague, home: TilePoint(0, 0), meetings: 3)
        #expect(npc.talkChance(charisma: 0, help: false) == 0.45)
        #expect(abs(npc.talkChance(charisma: 10, help: true) - 0.65) < 1e-9)
        #expect(abs(npc.talkChance(charisma: 100, help: false) - 0.60) < 1e-9)
        npc.legend = 0
        #expect(npc.talkChance(charisma: 0, help: false) == 0.20 && npc.talkHelpMP == 20)
    }

    @Test func cityTerritoryIsSafeAndStable() {
        let city = IslandCity(id: 0, name: "Стендап", center: TilePoint(50, 50), events: 12, houses: 10, isCity: true, radius: 9)
        #expect(city.contains(TilePoint(50, 50)) && city.contains(TilePoint(55, 50)))
        #expect(!city.contains(TilePoint(61, 50)))
        let island = Island(size: .small, terrain: [Terrain](repeating: .grass, count: 100 * 100), cities: [city], villages: [], npcs: [],
                            chests: [], campfires: [], start: TilePoint(0, 0))
        #expect(island.safeCity(at: TilePoint(53, 54))?.id == 0)
        #expect(island.safeCity(at: TilePoint(70, 70)) == nil)
    }

    @Test func legendCompanionSkillsBoostFights() {
        var levels: [Attribute: Int] = [:]
        for attribute in Attribute.allCases { levels[attribute] = 3 }
        let hero = ExploreHero(levels: levels, hp: 120, maxHP: 120, mp: 100, maxMP: 100, rankLetter: "G", skills: [])
        var plain = Encounter(tier: .regular, hero: hero, heroHP: 120, heroMP: 100, seed: 1)
        var boosted = Encounter(tier: .regular, hero: hero, heroHP: 120, heroMP: 100, seed: 1)
        boosted.firstStrikeFactor = ExploreRules.assassinFirstStrike
        boosted.opponentName = MonsterKind.bear.title
        plain.perform(.fight)
        boosted.perform(.fight)
        #expect(boosted.npcHP < plain.npcHP)
        #expect(boosted.opponentTitle == "Огр")
    }
}
