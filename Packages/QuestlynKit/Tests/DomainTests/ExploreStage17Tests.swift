import Foundation
import Testing
@testable import Domain

/// Этап 17: уровни монстров, уровень героя в прогулке, стая.
struct ExploreStage17Tests {
    @Test func monsterLevelsGrowByChapterAndTowers() {
        #expect(ExploreRules.monsterLevel(chapter: 0, nearTower: false) == 1)
        #expect(ExploreRules.monsterLevel(chapter: 3, nearTower: true) == 6)
        let data = ExploreStage15HTests().input()
        let island = IslandGenerator.generate(data, seed: 2)
        for npc in island.npcs where npc.monster != nil {
            let chapter = island.region(at: npc.home)?.id ?? 0
            let near = island.towers.contains { $0.position.distance(to: npc.home) <= ExploreRules.towerLevelRadius }
            #expect(npc.level == ExploreRules.monsterLevel(chapter: chapter, nearTower: near))
        }
        #expect(island.npcs.filter(\.isPeaceful).allSatisfy { $0.level == 1 })
    }

    @Test func levelScalesFights() {
        var levels: [Attribute: Int] = [:]
        for attribute in Attribute.allCases { levels[attribute] = 2 }
        let hero = ExploreHero(levels: levels, hp: 120, maxHP: 120, mp: 50, maxMP: 50, rankLetter: "G", skills: [])
        var fight = Encounter(tier: .colleague, hero: hero, heroHP: 120, heroMP: 50, seed: 1)
        fight.apply(level: 5)
        #expect(abs(fight.npcMaxHP - NPCTier.colleague.hp * 2 * ExploreRules.monsterHPFactor) < 1e-9)
        #expect(abs(fight.npcDamageFactor - 1.6 * ExploreRules.monsterDamageFactor) < 1e-9)
        var active = ActiveFight(tier: .colleague, hero: hero, heroHP: 120, heroMP: 50, seed: 1)
        active.externalHit(30)
        #expect(active.heroHP == 90)
    }

    @Test func walkLevelRankAndAura() {
        #expect(ExploreRules.walkLevel(xp: 0) == 1 && ExploreRules.walkLevel(xp: 10) == 2 && ExploreRules.walkLevel(xp: 29) == 2 && ExploreRules.walkLevel(xp: 30) == 3)
        #expect(ExploreRules.walkRank(level: 1) == "G" && ExploreRules.walkRank(level: 8) == "S" && ExploreRules.walkRank(level: 20) == "S")
        #expect(ExploreRules.walkAura(level: 2) == 0 && ExploreRules.walkAura(level: 3) == 1 && ExploreRules.walkAura(level: 7) == 3)
    }
}

/// 17.12: залив и пристань у крупных городов.
struct ExploreStage17HarbourTests {
    @Test func bigCitiesGetBayAndPier() {
        let data = ExploreStage15HTests().input()
        let island = IslandGenerator.generate(data, seed: 3)
        let big = island.cities.filter { $0.isCapital || $0.events >= ExploreRules.harbourCityEvents }
        #expect(!big.isEmpty && !island.piers.isEmpty)
        for pier in island.piers {
            #expect(!island.isLand(pier.position))
            #expect(island.isWalkable(pier.landing))
            let city = island.cities[pier.cityId]
            #expect(pier.landing.distance(to: city.center) <= Double(city.radius) + 4)
            // К причалу можно дойти от центра города, а от него доплыть до открытого моря.
            #expect(island.path(from: city.center, to: pier.landing) != nil)
        }
    }
}
