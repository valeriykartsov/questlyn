import Foundation
import Testing
@testable import Domain

/// Режим игры «Активный · джойстик» (16.11.2026): бой в реальном времени на карте.
struct ExploreActiveTests {
    func hero(level: Int = 1) -> ExploreHero {
        var levels: [Attribute: Int] = [:]
        for attribute in Attribute.allCases { levels[attribute] = level }
        let max = 100 + 5 * Double(level * 5)
        return ExploreHero(levels: levels, hp: max, maxHP: max, mp: max, maxMP: max, rankLetter: "G", skills: [])
    }

    func skill(_ ability: ExploreAbility) -> ExploreSkill { ExploreSkill(id: UUID(), title: ability.title, ability: ability, skillXP: 0) }

    /// Идеальная игра: стоять рядом и бить, как только удар готов.
    func simulate(tier: NPCTier, level: Int, runs: Int = 1000) -> (winRate: Double, seconds: Double, hpLost: Double) {
        var wins = 0, seconds = 0.0, lost = 0.0
        for seed in 0..<runs {
            let h = hero(level: level)
            var fight = ActiveFight(tier: tier, hero: h, heroHP: h.hp, heroMP: h.mp, seed: UInt64(seed))
            var time = 0.0
            while fight.outcome == nil && time < 120 {
                fight.strike(distance: 1)
                fight.tick(0.1, distance: 1)
                time += 0.1
            }
            if fight.outcome == .won { wins += 1 }
            seconds += time
            lost += (h.hp - fight.heroHP) / h.maxHP
        }
        return (Double(wins) / Double(runs), seconds / Double(runs), lost / Double(runs))
    }

    @Test func balanceMatchesTurnBasedGoals() {
        var report = ["Активный бой (по 1000 боёв, только «Удар»): уровень · тип · победы · секунд · потеря HP"]
        for level in [1, 5, 10] { for tier in NPCTier.allCases {
            let s = simulate(tier: tier, level: level)
            report.append("L\(level) · \(tier.title) · \(Int((s.winRate * 100).rounded()))% · \(String(format: "%.1f", s.seconds)) · \(Int((s.hpLost * 100).rounded()))%")
        } }
        print(report.joined(separator: "\n"))
        // Цели 09, раздел 8 — те же, что для пошагового: «Знакомый» побеждается всегда за 2–3 удара, потеря HP ≤ 20%.
        let acquaintance = simulate(tier: .acquaintance, level: 1)
        #expect(acquaintance.winRate == 1)
        #expect(acquaintance.seconds <= 3 * ExploreRules.activeTurnSeconds + 0.2)
        #expect(acquaintance.hpLost <= 0.20)
        // «Постоянный» — долгий бой (6+ ходов).
        #expect(simulate(tier: .regular, level: 1).seconds >= 6 * ExploreRules.activeTurnSeconds - 0.2)
    }

    @Test func rangeCooldownAndEscape() {
        let h = hero()
        var fight = ActiveFight(tier: .colleague, hero: h, heroHP: h.hp, heroMP: h.mp, seed: 1)
        let far = fight.strike(distance: 2), first = fight.strike(distance: 1), early = fight.strike(distance: 1)
        #expect(!far && first && !early)
        fight.tick(ExploreRules.activeTurnSeconds, distance: 3)
        #expect(fight.heroHP == h.hp)
        let again = fight.strike(distance: 1)
        #expect(again)
        fight.escape()
        #expect(fight.outcome == .fled)
        #expect(fight.escapeDistance == NPCTier.colleague.chaseRadius)
        let tower = ActiveFight(tier: .regular, hero: h, heroHP: h.hp, heroMP: h.mp, seed: 1, guardian: .init(title: "Сайт", hp: 70))
        #expect(tower.escapeDistance == ExploreRules.guardianLeash && tower.npcMaxHP == 70)
    }

    @Test func abilitiesWorkInSeconds() {
        let h = hero(level: 3)
        // Концентрация: урон вдвое меньше 2,4 с.
        var guarded = ActiveFight(tier: .regular, hero: h, heroHP: h.hp, heroMP: h.mp, seed: 4)
        var plain = ActiveFight(tier: .regular, hero: h, heroHP: h.hp, heroMP: h.mp, seed: 4)
        let focused = guarded.use(skill(.focus), distance: 1)
        #expect(focused)
        guarded.tick(ExploreRules.activeTurnSeconds, distance: 1)
        plain.tick(ExploreRules.activeTurnSeconds, distance: 1)
        #expect(abs((h.hp - guarded.heroHP) - (h.hp - plain.heroHP) * 0.5) <= 1)
        #expect(abs((guarded.cooldowns[.focus] ?? 0) - (guarded.abilityCooldown - ExploreRules.activeTurnSeconds)) < 0.001)
        let twice = guarded.use(skill(.focus), distance: 1)
        #expect(!twice)
        // Отвлечь: NPC не бьёт 2,4 с.
        var distracted = ActiveFight(tier: .regular, hero: h, heroHP: h.hp, heroMP: h.mp, seed: 4)
        distracted.use(skill(.distract), distance: 1)
        distracted.tick(2.3, distance: 1)
        #expect(distracted.heroHP == h.hp)
        // Мощный удар — только в радиусе.
        var strong = ActiveFight(tier: .regular, hero: h, heroHP: h.hp, heroMP: h.mp, seed: 4)
        let missed = strong.use(skill(.powerStrike), distance: 3), landed = strong.use(skill(.powerStrike), distance: 1)
        #expect(!missed && landed && strong.npcHP < NPCTier.regular.hp)
        #expect(strong.heroMP == h.mp - strong.cost(.powerStrike))
    }

    @Test func companionStrikesWithHeroLessOften() {
        let h = hero()
        var fight = ActiveFight(tier: .regular, hero: h, heroHP: h.hp, heroMP: h.mp, seed: 2, companion: .colleague)
        // Сам по себе спутник не бьёт.
        fight.tick(5, distance: 5)
        #expect(fight.npcHP == NPCTier.regular.hp)
        // Удар героя — и спутник вместе с ним.
        fight.strike(distance: 1)
        let first = fight.drainEvents()
        #expect(first.contains(.companionHit(Int(ExploreRules.companionStrike(.colleague)))))
        // Следующий удар героя через 1,2 с — спутник ещё не готов; через 3,6 с — снова вместе.
        fight.tick(ExploreRules.activeTurnSeconds, distance: 1)
        fight.strike(distance: 1)
        #expect(!fight.drainEvents().contains { if case .companionHit = $0 { true } else { false } })
        fight.tick(ExploreRules.activeCompanionInterval, distance: 1)
        fight.strike(distance: 1)
        #expect(fight.drainEvents().contains { if case .companionHit = $0 { true } else { false } })
        #expect(ExploreMode.allCases.map(\.title) == ["Пошаговый · касание", "Активный · джойстик"])
    }
}
