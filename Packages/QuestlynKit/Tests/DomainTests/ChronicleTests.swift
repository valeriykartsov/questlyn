import Foundation
import Testing
@testable import Domain

/// Летопись: вехи и свёрнутый спад (08, 4.1).
struct ChronicleTests {
    let tz = TimeZone(identifier: "UTC")!
    let day1 = LocalDate(year: 2026, month: 11, day: 1)

    func grant(_ attribute: Attribute, _ xp: Int, on day: LocalDate, hour: Int = 12) -> ProgressGrant {
        ProgressGrant(sourceType: .questCompletion, sourceId: UUID(), ruleVersion: .v1_1, target: .attribute(attribute),
                      amount: .xp(xp), reason: "", createdAt: VitalsCalculator.date(day, LocalTime(hour: hour, minute: 0)!, timeZone: tz),
                      effectiveDate: day)
    }

    @Test func levelMilestoneAtMomentOfGrant() {
        // 20 XP — уровень 1, ещё 25 — уровень 2.
        let grants = [grant(.intelligence, 20, on: day1, hour: 9), grant(.intelligence, 25, on: day1.adding(days: 2), hour: 18)]
        let result = MilestoneDetector.milestones(grants: grants, classAttributes: [], from: day1, through: day1.adding(days: 3), timeZone: tz)
        #expect(result.map(\.key) == ["level:INT:1", "level:INT:2"])
        #expect(result[1].date == day1.adding(days: 2))
        #expect(result[1].at == grants[1].createdAt)
    }

    @Test func reachingAgainAfterDecayIsNotNewMilestone() {
        // Уровень 1 (20 XP), спад после 7 дней ниже 20, потом снова выше 20.
        let grants = [grant(.charisma, 21, on: day1), grant(.charisma, 3, on: day1.adding(days: 30))]
        let result = MilestoneDetector.milestones(grants: grants, classAttributes: [], from: day1, through: day1.adding(days: 31), timeZone: tz)
        #expect(result.map(\.key) == ["level:CHR:1"])
    }

    @Test func rankMilestoneOnlyForNewHighest() {
        // Ранг G — 10 очков: класс STR выше 10-го уровня одним днём, затем ещё рост — новые ранги без повторов.
        let grants = [grant(.strength, 1000, on: day1), grant(.strength, 2000, on: day1.adding(days: 1))]
        let result = MilestoneDetector.milestones(grants: grants, classAttributes: [.strength], from: day1, through: day1.adding(days: 1), timeZone: tz)
        let ranks = result.filter { $0.kind == .rank }
        #expect(!ranks.isEmpty)
        #expect(Set(ranks.map(\.key)).count == ranks.count)
    }

    @Test func decayDaysCollapse() {
        let events = (0..<5).map { ProgressTimeline.DecayEvent(attribute: .charisma, date: day1.adding(days: $0), amount: CentiXP(-40), daysWithoutXP: 8 + $0, reachedFloor: false) }
            + [ProgressTimeline.DecayEvent(attribute: .charisma, date: day1.adding(days: 9), amount: CentiXP(-30), daysWithoutXP: 17, reachedFloor: true)]
        let runs = DecayRun.runs(events)
        #expect(runs.count == 2)
        #expect(runs[0].days == 5 && runs[0].amount == CentiXP(-200) && runs[0].daysWithoutXPAtEnd == 12)
        #expect(runs[1].reachedFloor)
    }
}
