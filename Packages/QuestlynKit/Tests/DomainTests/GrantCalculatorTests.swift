import Foundation
import Testing
@testable import Domain

/// 07, раздел 3: пример «Сдать отчёт».
struct GrantCalculatorTests {
    let heroId = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var engineer: Profession { Profession(heroId: heroId, title: "Инженер-программист", slot: 1, attributes: [.intelligence, .mentality, .charisma], createdAt: now) }
    var athlete: Profession { Profession(heroId: heroId, title: "Атлет", slot: 2, attributes: [.strength, .endurance, .mentality], createdAt: now) }

    func amounts(_ priority: QuestPriority, withSkill: Bool = true) -> [String: Int] {
        let engineer = engineer
        let skill = Skill(professionId: engineer.id, title: "Отчётность", createdAt: now)
        let snapshot = ClassRules.snapshot(skillProfession: engineer, activeProfessions: [engineer, athlete])
        let grants = GrantCalculator.questCompletionGrants(
            completionId: UUID(), priority: priority, skill: withSkill ? skill : nil,
            skillProfessionTitle: engineer.title, snapshot: withSkill ? snapshot : .empty, createdAt: now
        )
        return Dictionary(uniqueKeysWithValues: grants.map { grant in
            switch grant.target {
            case .attribute(let a): (a.code, grant.amount.value)
            case .skill: ("skill", grant.amount.value)
            }
        })
    }

    @Test func snapshotCountsSharedAttribute() {
        let snapshot = ClassRules.snapshot(skillProfession: engineer, activeProfessions: [engineer, athlete])
        #expect(snapshot.entries.map(\.attribute) == [.intelligence, .mentality, .charisma])
        #expect(snapshot.entries.map(\.multiplierInQuarters) == [4, 5, 4])
    }

    @Test func mediumMatchesExampleFrom07() {
        // FOC +5; «Отчётность» +10; INT +5; MNT +3,75; CHR +2.
        #expect(amounts(.medium) == ["FOC": 500, "skill": 1000, "INT": 500, "MNT": 375, "CHR": 200])
    }

    @Test func highIsOneAndHalfWithHalfUpRounding() {
        // MNT: 10 × 1,5 × 30% × 1,25 = 5,625 XP → 563 centiXP.
        #expect(amounts(.high) == ["FOC": 750, "skill": 1500, "INT": 750, "MNT": 563, "CHR": 300])
    }

    @Test func lowIsHalf() {
        // MNT: 1,875 XP → 188 centiXP.
        #expect(amounts(.low) == ["FOC": 250, "skill": 500, "INT": 250, "MNT": 188, "CHR": 100])
    }

    @Test func questWithoutSkillGivesOnlyFocus() {
        #expect(amounts(.medium, withSkill: false) == ["FOC": 500])
        #expect(amounts(.high, withSkill: false) == ["FOC": 750])
    }

    @Test func sharesAndMultipliers() {
        #expect(ClassRules.sharesInPercent(attributeCount: 1) == [100])
        #expect(ClassRules.sharesInPercent(attributeCount: 2) == [70, 30])
        #expect(ClassRules.multiplierInQuarters(professionCount: 3) == 6)
    }

    @Test func reasonExplainsMultiplier() {
        let engineer = engineer
        let grants = GrantCalculator.questCompletionGrants(
            completionId: UUID(), priority: .medium,
            skill: Skill(professionId: engineer.id, title: "Отчётность", createdAt: now),
            skillProfessionTitle: engineer.title,
            snapshot: ClassRules.snapshot(skillProfession: engineer, activeProfessions: [engineer, athlete]),
            createdAt: now
        )
        let mnt = grants.first { $0.target == .attribute(.mentality) }
        #expect(mnt?.reason == "Вторичный атрибут профессии · 30% · ×1,25 за повтор в классе")
    }

    @Test func roundingHalfUp() {
        #expect(CentiXP.roundedHalfUp(numerator: 4500, denominator: 8) == CentiXP(563))
        #expect(CentiXP.roundedHalfUp(numerator: 4499, denominator: 8) == CentiXP(562))
        #expect(CentiXP.roundedHalfUp(numerator: 1000, denominator: 2) == CentiXP(500))
    }

    @Test func progressProjection() {
        let skillId = UUID()
        let grants = [
            ProgressGrant(sourceType: .questCompletion, sourceId: UUID(), ruleVersion: .current, target: .attribute(.focus), amount: .xp(15), reason: "", createdAt: now),
            ProgressGrant(sourceType: .questCompletion, sourceId: UUID(), ruleVersion: .current, target: .attribute(.focus), amount: .xp(10), reason: "", createdAt: now),
            ProgressGrant(sourceType: .questCompletion, sourceId: UUID(), ruleVersion: .current, target: .skill(skillId), amount: .xp(10), reason: "", createdAt: now),
        ]
        let progress = HeroProgress(grants: grants, classAttributes: [.intelligence])
        #expect(progress.level(.focus) == 1)
        #expect(progress.levelProgress(.focus).current == 5)
        #expect(progress.levelProgress(.focus).needed == 25)
        #expect(progress.skillXP[skillId] == .xp(10))
        #expect(progress.rank == nil)
        #expect(progress.nextRank?.letter == "G")
    }
}
