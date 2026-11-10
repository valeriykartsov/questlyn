import Foundation
import Testing
@testable import Domain

/// 07, раздел 2: Activity — 10 XP в час, предел 3 ч одного типа в день.
struct ActivityTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day = LocalDate(year: 2026, month: 11, day: 10)

    @Test func templatesMatchApprovedList() {
        #expect(ActivityTemplate.all.count == 9)
        #expect(ActivityTemplate.template(id: "team-sport")?.attributes == [.endurance, .strength, .charisma])
        #expect(ActivityTemplate.all.allSatisfy { $0.attributes.allSatisfy(\.isSelectableForProfession) })
    }

    @Test func withoutSkillSplitsEquallyOnTemplate() {
        let strength = ActivityTemplate.template(id: "strength")!
        let grants = GrantCalculator.activityGrants(activityId: UUID(), template: strength, creditedMinutes: 60, skill: nil,
                                                    skillProfessionTitle: nil, snapshot: .empty, createdAt: now, effectiveDate: day)
        #expect(grants.map(\.amount.value) == [500, 500])
        #expect(!grants.contains { $0.target == .attribute(.focus) })
    }

    @Test func withSkillUsesProfessionSharesAndMultiplier() {
        // Мокап 8.1: 40 мин бега, навык «Бег» Атлета, MNT ×1,25 → навык 6,67, STR 3,33, END 2, MNT 1,67.
        let heroId = UUID()
        let engineer = Profession(heroId: heroId, title: "Инженер-программист", slot: 1, attributes: [.intelligence, .mentality, .charisma], createdAt: now)
        let athlete = Profession(heroId: heroId, title: "Атлет", slot: 2, attributes: [.strength, .endurance, .mentality], createdAt: now)
        let skill = Skill(professionId: athlete.id, title: "Бег", createdAt: now)
        let grants = GrantCalculator.activityGrants(
            activityId: UUID(), template: ActivityTemplate.template(id: "cardio")!, creditedMinutes: 40, skill: skill,
            skillProfessionTitle: "Атлет", snapshot: ClassRules.snapshot(skillProfession: athlete, activeProfessions: [engineer, athlete]),
            createdAt: now, effectiveDate: day
        )
        #expect(grants.map(\.amount.value) == [667, 333, 200, 167])
    }

    @Test func dailyCapIsThreeHours() {
        #expect(ActivityRules.creditedMinutes(duration: 480, alreadyCreditedToday: 0) == 180)
        #expect(ActivityRules.creditedMinutes(duration: 60, alreadyCreditedToday: 150) == 30)
        #expect(ActivityRules.creditedMinutes(duration: 60, alreadyCreditedToday: 180) == 0)
        #expect(GrantCalculator.activityGrants(activityId: UUID(), template: ActivityTemplate.all[0], creditedMinutes: 0, skill: nil,
                                               skillProfessionTitle: nil, snapshot: .empty, createdAt: now, effectiveDate: day).isEmpty)
    }
}
