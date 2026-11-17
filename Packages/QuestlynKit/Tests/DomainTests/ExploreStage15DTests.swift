import Foundation
import Testing
@testable import Domain

/// Этап 15D: торговцы, ночные NPC, умения спутника.
struct ExploreStage15DTests {
    let utc = TimeZone(identifier: "UTC")!
    let last = LocalDate(year: 2026, month: 11, day: 10)

    func input(days: Int) -> ExploreInput {
        let first = last.adding(days: -(days - 1))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var events: [ExploreEvent] = []
        for day in 0..<days {
            let date = first.adding(days: day)
            let noon = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 12))!
            let evening = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 20))!
            events.append(ExploreEvent(title: "Встреча \(day % 4)", start: noon, minutes: 30, attendeeKeys: ["day\(day % 5)"]))
            events.append(ExploreEvent(title: "Ужин \(day % 3)", start: evening, minutes: 60, attendeeKeys: ["night\(day % 4)"]))
        }
        return ExploreInput(first: first, last: last, events: events, quests: [], nights: [:], weekMoods: [:], hasCalendar: true, timeZone: utc)
    }

    @Test func nightNPCsComeFromEveningEvents() {
        let island = IslandGenerator.generate(input(days: 20), seed: 3)
        let night = island.npcs.filter(\.isNight)
        #expect(!night.isEmpty)
        for region in island.regions { #expect(night.filter { region.contains($0.home) }.count <= ExploreRules.nightNPCCap) }
        #expect(island.npcs.filter { !$0.isNight }.count >= 1)
        #expect(night.allSatisfy { $0.chaseRadius == $0.tier.chaseRadius + 1 })
        #expect(island.npcs.map(\.id) == Array(island.npcs.indices))
    }

    @Test func merchantStandsInBusiestCity() {
        let island = IslandGenerator.generate(input(days: 20), seed: 3)
        let merchant = island.merchants.first
        #expect(island.merchants.count == island.regions.count || island.merchants.count == 1)
        let city = island.cities.max { $0.events < $1.events }
        #expect(merchant.map { island.safeCity(at: $0.position) != nil && island.isWalkable($0.position) } == true)
        #expect(merchant?.cityId == city?.id)
    }

    @Test func nightFightsAreHarder() {
        var levels: [Attribute: Int] = [:]
        for a in Attribute.allCases { levels[a] = 1 }
        let hero = ExploreHero(levels: levels, hp: 100, maxHP: 100, mp: 100, maxMP: 100, rankLetter: "G", skills: [])
        let day = Encounter(tier: .colleague, hero: hero, heroHP: 100, heroMP: 100, seed: 1)
        let night = Encounter(tier: .colleague, hero: hero, heroHP: 100, heroMP: 100, seed: 1, night: true)
        #expect(night.npcMaxHP == day.npcMaxHP * 1.5 && night.npcHP == night.npcMaxHP)
        var a = day, b = night
        a.perform(.flee); b.perform(.flee)
        // Урон ночью ×1,25 (тот же бросок).
        if a.outcome == nil && b.outcome == nil { #expect(abs((100 - b.heroHP) - (100 - a.heroHP) * 1.25) <= 1) }
        let active = ActiveFight(tier: .colleague, hero: hero, heroHP: 100, heroMP: 100, seed: 1, night: true)
        #expect(active.npcMaxHP == NPCTier.colleague.hp * 1.5 && active.escapeDistance == NPCTier.colleague.chaseRadius + 1)
        #expect(CompanionSkill(.acquaintance) == .scout && CompanionSkill(.colleague) == .guide && CompanionSkill(.regular) == .healer)
    }
}
