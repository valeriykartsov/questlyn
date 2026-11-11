import Foundation
import Observation
import Domain

/// Состояние прогулки (8B): общее для сцены SpriteKit и экранов SwiftUI. Ничего не сохраняется (песочница).
@Observable
final class ExploreSession {
    let input: ExploreInput
    let island: Island
    let hero: ExploreHero
    let seed: UInt64
    let accent: UInt32
    let appearance: HeroAppearance?
    /// Время года текстур суши и осадки — выбор игрока (02, 12.11.2026).
    let season: Season
    let precipitation: Bool

    var hp: Double
    var mp: Double
    var heroTile: TilePoint
    var visitedCities: Set<Int> = []
    var openedChests: Set<Int> = []
    var litCampfires: Set<Int> = []
    /// Последний посещённый город — сюда герой возвращается после поражения.
    var lastCity: TilePoint
    var wins = 0
    var persuaded = 0
    var escapes = 0
    var defeats = 0
    var steps = 0
    let startedAt = Date.now

    /// Текущая встреча (сцена на паузе, пока она открыта).
    var encounter: Encounter?
    var encounterNPC: Int?
    /// Способности на карте: перезарядка до момента.
    var mapCooldownUntil: [ExploreAbility: Date] = [:]
    var dashUntil: Date?
    var scoutUntil: Date?
    /// Короткое сообщение поверх карты: «Сундук: …», «Костёр: +HP».
    var toast: String?

    init(input: ExploreInput, hero: ExploreHero, attempt: Int, appearance: HeroAppearance?, accent: UInt32,
         season: Season, precipitation: Bool) {
        self.season = season
        self.precipitation = precipitation
        self.input = input
        self.hero = hero
        self.seed = input.seed(attempt: attempt)
        self.island = IslandGenerator.generate(input, seed: seed)
        self.appearance = appearance
        self.accent = accent
        hp = hero.hp
        mp = hero.mp
        heroTile = island.start
        lastCity = island.start
    }

    static let mapCooldown: TimeInterval = 10

    func canUseOnMap(_ skill: ExploreSkill) -> Bool {
        guard skill.ability == .dash || skill.ability == .scout, encounter == nil else { return false }
        if let until = mapCooldownUntil[skill.ability], until > .now { return false }
        return mp >= (skill.ability.mpShare * hero.maxMP).rounded()
    }

    /// Рывок — ускорение ×2 на 3·m с; Разведка — обзор 15 клеток на 10 с (09, раздел 6).
    func useOnMap(_ skill: ExploreSkill) {
        guard canUseOnMap(skill) else { return }
        mp -= (skill.ability.mpShare * hero.maxMP).rounded()
        mapCooldownUntil[skill.ability] = .now + Self.mapCooldown
        switch skill.ability {
        case .dash: dashUntil = .now + 3 * skill.power
        case .scout: scoutUntil = .now + 10
        default: break
        }
    }

    var speed: Double { hero.walkSpeed * ((dashUntil ?? .distantPast) > .now ? 2 : 1) }
    var vision: Double { (scoutUntil ?? .distantPast) > .now ? 15 : hero.vision }

    func startEncounter(npc: IslandNPC) {
        encounterNPC = npc.id
        encounter = Encounter(tier: npc.tier, hero: hero, heroHP: hp, heroMP: mp, seed: seed &+ UInt64(steps * 31 + npc.id))
    }

    /// Итог встречи переносит HP и MP на карту; поражение — в последний город с половиной HP.
    func finishEncounter() -> EncounterOutcome? {
        guard let encounter else { return nil }
        let outcome = encounter.outcome
        hp = encounter.heroHP
        mp = encounter.heroMP
        switch outcome {
        case .won: wins += 1
        case .persuaded: persuaded += 1
        case .fled: escapes += 1
        case .lost:
            defeats += 1
            hp = (hero.maxHP * ExploreRules.defeatHPShare).rounded()
        case nil: break
        }
        self.encounter = nil
        return outcome
    }
}
