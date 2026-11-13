import Foundation
import Testing
@testable import Domain

/// «Побродить» (8B): генерация острова, встреча и симуляция баланса (09, раздел 8).
struct ExploreTests {
    let first = LocalDate(year: 2026, month: 8, day: 12)
    let last = LocalDate(year: 2026, month: 11, day: 10)

    func input(days: Int = 91, people: Int = 30, titles: Int = 12, quests: Int = 40) -> ExploreInput {
        let start = last.adding(days: -(days - 1))
        var events: [ExploreEvent] = []
        var random = ExploreRandom(42)
        for day in 0..<days {
            for _ in 0..<2 {
                let title = "Событие \(random.int(titles * 2))"
                let count = random.int(4)
                let keys = (0..<count).map { _ in "p\(random.int(people))" }
                events.append(ExploreEvent(title: title, start: noon(start.adding(days: day)), minutes: 30, attendeeKeys: keys))
            }
        }
        let priorities: [QuestPriority] = [.low, .medium, .high]
        let questList = (0..<quests).map { (title: "Квест \($0)", priority: priorities[$0 % 3], date: Optional(start.adding(days: $0 * days / max(quests, 1)))) }
        var nights: [LocalDate: Double] = [:]
        for day in 0..<days { nights[start.adding(days: day)] = 0.5 + Double(day % 5) / 10 }
        return ExploreInput(first: start, last: last, events: events, quests: questList, nights: nights,
                            weekMoods: [start.weekStart: .bad], hasCalendar: true, timeZone: utc)
    }

    let utc = TimeZone(identifier: "UTC")!
    func noon(_ day: LocalDate) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))!
    }

    func hero(level: Int = 1, skills: [ExploreSkill] = []) -> ExploreHero {
        var levels: [Attribute: Int] = [:]
        for attribute in Attribute.allCases { levels[attribute] = level }
        let max = 100 + 5 * Double(level * 5)
        return ExploreHero(levels: levels, hp: max, maxHP: max, mp: max, maxMP: max, rankLetter: "G", skills: skills)
    }

    // MARK: Остров

    @Test func sizeStepsByDays() {
        #expect(ExploreRules.islandSize(days: 14) == .small)
        #expect(ExploreRules.islandSize(days: 15) == .medium)
        #expect(ExploreRules.islandSize(days: 43) == .large)
        let today = LocalDate(year: 2026, month: 11, day: 11)
        #expect(ExploreInput.isValidRange(first: today.adding(days: -92), last: today.adding(days: -1), today: today))
        #expect(!ExploreInput.isValidRange(first: today.adding(days: -93), last: today.adding(days: -1), today: today))
        #expect(!ExploreInput.isValidRange(first: today.adding(days: -3), last: today, today: today))
    }

    @Test func generationIsDeterministicAndSeedChangesIt() {
        let data = input()
        let a = IslandGenerator.generate(data, seed: data.seed(attempt: 0))
        let b = IslandGenerator.generate(data, seed: data.seed(attempt: 0))
        let c = IslandGenerator.generate(data, seed: data.seed(attempt: 1))
        #expect(a.terrain == b.terrain && a.cities == b.cities && a.npcs == b.npcs)
        #expect(a.terrain != c.terrain)
    }

    @Test func everythingIsReachableFromStart() {
        for attempt in 0..<10 {
            let data = input()
            let island = IslandGenerator.generate(data, seed: data.seed(attempt: attempt))
            #expect(island.isLand(island.start))
            #expect(island.region(at: island.start)?.id == island.regions.count - 1)
            // Каждый остров: всё достижимо пешком от места высадки у его корабля; корабли связаны морем.
            for ship in island.ships {
                #expect(!island.isLand(ship.position))
                #expect(island.npcs.allSatisfy { $0.home.distance(to: ship.position) >= ExploreRules.harbourRadius })
                guard let landing = island.landing(near: ship.position) else { Issue.record("нет берега у корабля"); continue }
                #expect(island.region(at: landing)?.id == ship.region)
                let region = island.regions[ship.region]
                for target in island.cities.map(\.center) + island.chests.map(\.position) + island.campfires.map(\.position) where region.contains(target) {
                    #expect(island.path(from: landing, to: target) != nil)
                }
                #expect(island.seaPath(from: island.ships[0].position, to: ship.position) != nil)
            }
        }
    }

    @Test func archipelagoHasIslandPerMonth() {
        let data = input()
        let island = IslandGenerator.generate(data, seed: data.seed(attempt: 0))
        // 12.08–10.11: август 20 дней, сентябрь 30, октябрь 31, ноябрь 10.
        #expect(island.regions.map(\.days) == [20, 30, 31, 10])
        #expect(island.regions.map(\.size) == [.medium, .medium, .medium, .small])
        #expect(island.regions.map(\.monthTitle) == ["Август", "Сентябрь", "Октябрь", "Ноябрь"])
        #expect(island.ships.count == 4)
        // Острова не пересекаются и разделены водой.
        for (i, a) in island.regions.enumerated() { for b in island.regions[(i + 1)...] {
            let apart = a.origin.x + a.side + ExploreRules.islandGap <= b.origin.x || b.origin.x + b.side + ExploreRules.islandGap <= a.origin.x
                || a.origin.y + a.side + ExploreRules.islandGap <= b.origin.y || b.origin.y + b.side + ExploreRules.islandGap <= a.origin.y
            #expect(apart)
        } }
        // Пешком между островами не дойти.
        let otherCity = island.cities.first { island.region(at: $0.center)?.id == 0 }
        if let otherCity { #expect(island.path(from: island.start, to: otherCity.center) == nil) }
        // Мини-остров из короткого куска месяца — тоже отдельный.
        let short = input(days: 12)
        #expect(IslandGenerator.generate(short, seed: 1).regions.map(\.days) == [2, 10])
        // Один месяц — один остров без кораблей.
        let one = input(days: 10)
        let single = IslandGenerator.generate(one, seed: 1)
        #expect(single.regions.count == 1 && single.ships.isEmpty && single.side == IslandSize.small.tiles)
    }

    @Test func objectsFollowRules() {
        let data = input()
        let island = IslandGenerator.generate(data, seed: data.seed(attempt: 0))
        #expect(island.size == .medium)
        #expect(!island.cities.isEmpty && island.cities.count <= island.regions.map(\.size.cityCap).reduce(0, +))
        #expect(island.cities.allSatisfy { $0.events >= 2 })
        for (i, a) in island.cities.enumerated() { for b in island.cities[(i + 1)...] {
            #expect(a.center.distance(to: b.center) >= Double(ExploreRules.cityMinDistance))
        } }
        #expect(Set(island.cities.map(\.id)) == Set(island.cities.indices))
        #expect(island.npcs.map(\.id) == Array(island.npcs.indices))
        #expect(island.region(at: island.start)?.id == 3)
        #expect(island.npcs.allSatisfy { $0.home.distance(to: island.start) >= Double(ExploreRules.npcMinDistanceFromStart) })
        #expect(island.npcs.allSatisfy { island.safeCity(at: $0.home) == nil })
        // Квесты по датам — на острове своего месяца.
        #expect(island.chests.count == 40)
        #expect(island.campfires.count >= 13)
        #expect(island.weatherBands.count == 14 && island.weatherBands.first == .rain)
    }

    @Test func withoutCalendarThereAreNoCitiesOrNPC() {
        var data = input()
        data.events = []
        data.hasCalendar = false
        let island = IslandGenerator.generate(data, seed: 7)
        #expect(island.cities.isEmpty && island.npcs.isEmpty && !island.chests.isEmpty)
        #expect(island.isLand(island.start))
    }

    @Test func npcTiersAndAbilities() {
        #expect(NPCTier.of(meetings: 1) == .acquaintance && NPCTier.of(meetings: 4) == .colleague && NPCTier.of(meetings: 5) == .regular)
        #expect(ExploreAbility.of(activityTemplateId: "cardio", professionMain: .strength) == .dash)
        #expect(ExploreAbility.of(activityTemplateId: nil, professionMain: .charisma) == .persuade)
        #expect(ExploreAbility.of(activityTemplateId: nil, professionMain: nil) == nil)
        #expect(ExploreRules.power(skillXP: 49) == 1 && ExploreRules.power(skillXP: 230) == 1.5 && ExploreRules.power(skillXP: 900) == 2)
    }

    // MARK: Встреча

    @Test func dashAlwaysEscapesAndCostsMana() {
        let dash = ExploreSkill(id: UUID(), title: "Бег", ability: .dash, skillXP: 0)
        let h = hero(skills: [dash])
        var encounter = Encounter(tier: .regular, hero: h, heroHP: h.hp, heroMP: h.mp, seed: 1)
        encounter.perform(.ability(dash))
        #expect(encounter.outcome == .fled)
        #expect(encounter.heroMP == h.mp - encounter.cost(.dash))
    }

    @Test func lossEndsEncounter() {
        let h = hero(level: 0)
        var encounter = Encounter(tier: .regular, hero: h, heroHP: 5, heroMP: h.mp, seed: 3)
        while encounter.outcome == nil { encounter.perform(.fight) }
        #expect(encounter.outcome == .lost || encounter.outcome == .won)
    }

    // MARK: Симуляция баланса (09, раздел 8)

    struct FightStats { var winRate = 0.0; var turns = 0.0; var hpLost = 0.0 }

    func simulateFights(tier: NPCTier, level: Int, runs: Int = 2000) -> FightStats {
        var stats = FightStats(), wins = 0
        for seed in 0..<runs {
            let h = hero(level: level)
            var encounter = Encounter(tier: tier, hero: h, heroHP: h.hp, heroMP: h.mp, seed: UInt64(seed))
            while encounter.outcome == nil { encounter.perform(.fight) }
            if encounter.outcome == .won { wins += 1 }
            stats.turns += Double(encounter.turn)
            stats.hpLost += (h.hp - encounter.heroHP) / h.maxHP
        }
        stats.winRate = Double(wins) / Double(runs)
        stats.turns /= Double(runs)
        stats.hpLost /= Double(runs)
        return stats
    }

    @Test func balanceSimulation() {
        var report = ["Симуляция 09 (по 2000 боёв, только «Сражаться»):", "уровень · тип · победы · ходов · потеря HP"]
        for level in [1, 5, 10] {
            for tier in NPCTier.allCases {
                let s = simulateFights(tier: tier, level: level)
                report.append("L\(level) · \(tier.title) · \(Int((s.winRate * 100).rounded()))% · \(String(format: "%.1f", s.turns)) · \(Int((s.hpLost * 100).rounded()))%")
            }
        }
        let fresh = hero(level: 1)
        let escape = ExploreRules.escapeChance(mentality: fresh.level(.mentality), tier: .regular)
        report.append("Побег новичка от «Постоянного»: \(Int((escape * 100).rounded()))%")
        print(report.joined(separator: "\n"))

        // Цели раздела 8.
        let acquaintance = simulateFights(tier: .acquaintance, level: 1)
        #expect(acquaintance.winRate == 1)
        #expect((2...3).contains(Int(acquaintance.turns.rounded())))
        #expect(acquaintance.hpLost <= 0.20)
        let regular = simulateFights(tier: .regular, level: 1)
        #expect(regular.turns >= 6)
        #expect((0.35...0.45).contains(escape))
    }

    @Test func densitySimulation() {
        // На большом острове с 40 NPC путь от старта к городу проходит рядом (в радиусе погони) не больше чем с 2–3 NPC в среднем.
        var total = 0.0, paths = 0
        for attempt in 0..<20 {
            let data = input(people: 60)
            let island = IslandGenerator.generate(data, seed: data.seed(attempt: attempt))
            for city in island.cities.dropFirst() {
                guard let path = island.path(from: island.start, to: city.center) else { continue }
                let met = island.npcs.filter { npc in path.contains { $0.distance(to: npc.home) <= npc.tier.chaseRadius } }.count
                total += Double(met)
                paths += 1
            }
        }
        let average = total / Double(max(paths, 1))
        print("Симуляция плотности: в среднем \(String(format: "%.1f", average)) NPC на пути к городу")
        #expect(average <= 3)
    }
}
