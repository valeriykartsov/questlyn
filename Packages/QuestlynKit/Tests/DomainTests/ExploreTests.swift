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
                events.append(ExploreEvent(title: title, start: Date(timeIntervalSince1970: Double(day) * 86400), minutes: 30, attendeeKeys: keys))
            }
        }
        let priorities: [QuestPriority] = [.low, .medium, .high]
        let questList = (0..<quests).map { (title: "Квест \($0)", priority: priorities[$0 % 3]) }
        var nights: [LocalDate: Double] = [:]
        for day in 0..<days { nights[start.adding(days: day)] = 0.5 + Double(day % 5) / 10 }
        return ExploreInput(first: start, last: last, events: events, quests: questList, nights: nights,
                            weekMoods: [start.weekStart: .bad], hasCalendar: true)
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
            for target in island.cities.map(\.center) + island.chests.map(\.position) + island.campfires.map(\.position) {
                #expect(island.path(from: island.start, to: target) != nil)
            }
        }
    }

    @Test func objectsFollowRules() {
        let data = input()
        let island = IslandGenerator.generate(data, seed: data.seed(attempt: 0))
        #expect(island.size == .large)
        #expect(!island.cities.isEmpty && island.cities.count <= IslandSize.large.cityCap)
        #expect(island.cities.allSatisfy { $0.events >= 2 })
        for (i, a) in island.cities.enumerated() { for b in island.cities[(i + 1)...] {
            #expect(a.center.distance(to: b.center) >= Double(ExploreRules.cityMinDistance))
        } }
        #expect(island.start == island.cities[0].center)
        #expect(island.npcs.count <= IslandSize.large.npcCap)
        #expect(island.npcs.allSatisfy { $0.home.distance(to: island.start) >= Double(ExploreRules.npcMinDistanceFromStart) })
        #expect(island.npcs.allSatisfy { island.safeCity(at: $0.home) == nil })
        #expect(island.chests.count == ExploreRules.chestCap)
        #expect(island.campfires.count == 14)
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
