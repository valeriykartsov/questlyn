import Foundation
import Testing
@testable import Domain

/// 07, разделы 6–7: спад атрибутов, граница, форма навыка; стартовый бонус.
struct ProgressTimelineTests {
    let start = LocalDate(year: 2026, month: 11, day: 1)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func grant(_ attribute: Attribute, _ xp: Int, day: Int, source: GrantSourceType = .questCompletion) -> ProgressGrant {
        ProgressGrant(sourceType: source, sourceId: UUID(), ruleVersion: .current, target: .attribute(attribute),
                      amount: .xp(xp), reason: "", createdAt: now, effectiveDate: start.adding(days: day))
    }

    func skillGrant(_ id: UUID, day: Int) -> ProgressGrant {
        ProgressGrant(sourceType: .questCompletion, sourceId: UUID(), ruleVersion: .current, target: .skill(id),
                      amount: .xp(10), reason: "", createdAt: now, effectiveDate: start.adding(days: day))
    }

    @Test func graceWeekThenMinusTwoPercent() {
        // Перерыв 14 дней: 7 дней льготы и 7 дней по −2% ≈ −13% (пример из 07).
        let state = ProgressTimeline.attributeState(.charisma, grants: [grant(.charisma, 100, day: 0)], today: start.adding(days: 14))
        #expect(state.decay.count == 7)
        #expect(state.decay.first?.date == start.adding(days: 8))
        #expect(state.decay.first?.daysWithoutXP == 8)
        #expect(abs(state.xp.value - 8681) <= 2)
        #expect(state.peak == .xp(100))
    }

    @Test func noDecayWithinGrace() {
        let state = ProgressTimeline.attributeState(.intelligence, grants: [grant(.intelligence, 100, day: 0)], today: start.adding(days: 7))
        #expect(state.xp == .xp(100) && state.decay.isEmpty)
    }

    @Test func floorIsSeventyPercentOfPeak() {
        // Граница достигается примерно через 18 дней спада — через 25 дней бездействия.
        let state = ProgressTimeline.attributeState(.focus, grants: [grant(.focus, 100, day: 0)], today: start.adding(days: 60))
        #expect(state.xp == .xp(70))
        #expect(state.decay.last?.reachedFloor == true)
        let dayOfFloor = state.decay.first { $0.reachedFloor }.map { start.days(until: $0.date) }
        #expect(dayOfFloor.map { (24...27).contains($0) } == true)
    }

    @Test func newXPResetsGrace() {
        let grants = [grant(.strength, 100, day: 0), grant(.strength, 5, day: 7)]
        let state = ProgressTimeline.attributeState(.strength, grants: grants, today: start.adding(days: 14))
        #expect(state.xp == .xp(105) && state.decay.isEmpty)
    }

    @Test func disciplineDoesNotDecay() {
        let state = ProgressTimeline.attributeState(.discipline, grants: [grant(.discipline, 30, day: 0)], today: start.adding(days: 60))
        #expect(state.xp == .xp(30))
    }

    @Test func startBonusDoesNotDecay() {
        let bonus = grant(.intelligence, 20, day: 0, source: .onboardingBonus)
        var state = ProgressTimeline.attributeState(.intelligence, grants: [bonus], today: start.adding(days: 90))
        #expect(state.xp == .xp(20) && state.decay.isEmpty)
        // Заработанное сверху спадает, но не ниже max(70% пика, бонус).
        state = ProgressTimeline.attributeState(.intelligence, grants: [bonus, grant(.intelligence, 5, day: 1)], today: start.adding(days: 90))
        #expect(state.xp == .xp(20))
    }

    @Test func levelDropsWithDecay() {
        let grants = [grant(.mentality, 20, day: 0)]
        let progress = HeroProgress(grants: grants, classAttributes: [.mentality], today: start.adding(days: 9))
        #expect(progress.level(.mentality) == 0) // 20 → 19,6 после первого дня спада
        #expect(HeroProgress(grants: grants, classAttributes: [.mentality]).level(.mentality) == 1)
    }

    @Test func conditionStartsAt100RestoresAndFloorsAt40() {
        let skill = UUID()
        #expect(ProgressTimeline.condition(skillId: skill, grants: [], today: start) == nil)
        let first = [skillGrant(skill, day: 0)]
        #expect(ProgressTimeline.condition(skillId: skill, grants: first, today: start.adding(days: 7)) == 100)
        #expect(ProgressTimeline.condition(skillId: skill, grants: first, today: start.adding(days: 10)) == 91)
        #expect(ProgressTimeline.condition(skillId: skill, grants: first + [skillGrant(skill, day: 11)], today: start.adding(days: 11)) == 100)
        #expect(ProgressTimeline.condition(skillId: skill, grants: first, today: start.adding(days: 200)) == 40)
    }

    @Test func onboardingBonusPerPrimaryAttribute() {
        let heroId = UUID()
        func profession(_ attrs: [Attribute], _ title: String) -> Profession {
            Profession(heroId: heroId, title: title, slot: 1, attributes: attrs, createdAt: now)
        }
        let engineer = profession([.intelligence, .mentality, .charisma], "Инженер-программист")
        let athlete = profession([.strength, .endurance, .mentality], "Атлет")
        let prompt = profession([.intelligence, .mentality, .charisma], "Промпт-инженер")

        let pair = GrantCalculator.onboardingBonusGrants(heroId: heroId, professions: [engineer, athlete], createdAt: now, effectiveDate: start)
        #expect(Dictionary(uniqueKeysWithValues: pair.map { ($0.target, $0.amount) }) == [.attribute(.strength): .xp(20), .attribute(.intelligence): .xp(20)])

        let shared = GrantCalculator.onboardingBonusGrants(heroId: heroId, professions: [engineer, prompt], createdAt: now, effectiveDate: start)
        #expect(shared.count == 1 && shared[0].amount == .xp(45))
        let progress = HeroProgress(grants: shared, classAttributes: [.intelligence, .mentality, .charisma], today: start)
        #expect(progress.level(.intelligence) == 2)
    }
}
