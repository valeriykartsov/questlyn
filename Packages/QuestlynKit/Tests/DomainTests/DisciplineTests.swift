import Foundation
import Testing
@testable import Domain

/// 07, раздел 5 и уточнения 02 от 10.11.2026.
struct DisciplineTests {
    func days(_ done: [Int], _ scheduled: [Int]) -> [(done: Int, scheduled: Int)] {
        zip(done, scheduled).map { ($0, $1) }
    }

    @Test func halfIsNeutral() {
        let r = DisciplineCalculator.evaluate(.init(days: days([1, 1, 1, 1, 1, 1, 1], [2, 2, 2, 2, 2, 2, 2]), weekly: []))
        #expect(r.percent == 50)
        #expect(r.delta == 0)
    }

    @Test func emptyWeekDropsAtMostThirty() {
        let r = DisciplineCalculator.evaluate(.init(days: days([0, 0, 0, 0, 0, 0, 0], [3, 3, 3, 3, 3, 2, 2]), weekly: [(0, 3)]))
        #expect(r.percent == 0)
        #expect(r.delta == -30)
    }

    @Test func fullWeekGivesMaxGrowth() {
        let r = DisciplineCalculator.evaluate(.init(days: days([3, 3, 3, 3, 3, 2, 2], [3, 3, 3, 3, 3, 2, 2]), weekly: []))
        #expect(r.v == 1.5)
        #expect(r.delta == 45)
    }

    @Test func dayWithoutHabitsIsZero() {
        // Только понедельник запланирован и выполнен: (100 + 6 × 0) / 7.
        let r = DisciplineCalculator.evaluate(.init(days: days([1, 0, 0, 0, 0, 0, 0], [1, 0, 0, 0, 0, 0, 0]), weekly: []))
        #expect(abs(r.percent - 100.0 / 7) < 1e-9)
        #expect(r.v == 0.5 + 1.0 / 14)
    }

    @Test func weeklyShareIsCappedAndExcludedFromV() {
        let r = DisciplineCalculator.evaluate(.init(days: days([1, 1, 1, 1, 1, 1, 1], [1, 1, 1, 1, 1, 1, 1]), weekly: [(5, 3)]))
        #expect(r.percent == 100)
        #expect(r.v == 1.0) // 0,5 + 7/14; недельная цель в v не входит
        #expect(r.delta == 30)
    }

    @Test func grantNeverPushesBelowZeroAndRoundsHalfUp() {
        #expect(DisciplineCalculator.grantAmount(delta: -30, currentDIS: CentiXP(1200)) == CentiXP(-1200))
        #expect(DisciplineCalculator.grantAmount(delta: -30, currentDIS: CentiXP(5000)) == CentiXP(-3000))
        #expect(DisciplineCalculator.grantAmount(delta: 29.705, currentDIS: .zero) == CentiXP(2971))
    }

    @Test func firstCountedWeekSkipsCreationWeek() {
        let wednesday = LocalDate(year: 2026, month: 11, day: 11)
        #expect(DisciplineCalculator.firstCountedWeek(heroCreatedOn: wednesday) == LocalDate(year: 2026, month: 11, day: 16))
        let monday = LocalDate(year: 2026, month: 11, day: 9)
        #expect(DisciplineCalculator.firstCountedWeek(heroCreatedOn: monday) == monday)
    }

    @Test func sourceIdIsStablePerWeek() {
        let week = LocalDate(year: 2026, month: 11, day: 9)
        #expect(DisciplineCalculator.sourceId(weekStart: week) == DisciplineCalculator.sourceId(weekStart: week))
        #expect(DisciplineCalculator.sourceId(weekStart: week) != DisciplineCalculator.sourceId(weekStart: week.adding(days: 7)))
    }

    @Test func weekMath() {
        let tuesday = LocalDate(year: 2026, month: 11, day: 10)
        #expect(tuesday.weekday == .tuesday)
        #expect(tuesday.weekStart == LocalDate(year: 2026, month: 11, day: 9))
        #expect(LocalDate(year: 2026, month: 11, day: 15).weekday == .sunday)
        #expect(LocalDate(year: 2026, month: 12, day: 31).adding(days: 1) == LocalDate(year: 2027, month: 1, day: 1))
        #expect(tuesday.weekDays.count == 7 && tuesday.weekDays.last?.weekday == .sunday)
    }

    @Test func markingWindowIsTodayAndYesterday() {
        let today = LocalDate(year: 2026, month: 11, day: 10)
        #expect(HabitMarkingRules.canMark(today, today: today))
        #expect(HabitMarkingRules.canMark(today.adding(days: -1), today: today))
        #expect(!HabitMarkingRules.canMark(today.adding(days: -2), today: today))
        #expect(!HabitMarkingRules.canMark(today.adding(days: 1), today: today))
    }

    @Test func habitGrantsWithSkillOnly() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let heroId = UUID()
        let engineer = Profession(heroId: heroId, title: "Инженер-программист", slot: 1, attributes: [.intelligence, .mentality, .charisma], createdAt: now)
        let athlete = Profession(heroId: heroId, title: "Атлет", slot: 2, attributes: [.strength, .endurance, .mentality], createdAt: now)
        let skill = Skill(professionId: athlete.id, title: "ОФП", createdAt: now)
        let snapshot = ClassRules.snapshot(skillProfession: athlete, activeProfessions: [engineer, athlete])
        let grants = GrantCalculator.habitOccurrenceGrants(occurrenceId: UUID(), skill: skill, skillProfessionTitle: "Атлет", snapshot: snapshot, createdAt: now)
        // Навык +5; STR 2,5; END 1,5; MNT 5 × 20% × 1,25 = 1,25. FOC нет.
        #expect(grants.map(\.amount.value) == [500, 250, 150, 125])
        #expect(!grants.contains { $0.target == .attribute(.focus) })
        #expect(GrantCalculator.habitOccurrenceGrants(occurrenceId: UUID(), skill: nil, skillProfessionTitle: nil, snapshot: .empty, createdAt: now).isEmpty)
    }

    @Test func scheduleRespectsStartDateAndWeekdays() {
        let start = LocalDate(year: 2026, month: 11, day: 10)
        let habit = HabitDefinition(kind: .daily, title: "Чтение", weekdays: Weekday.workdays, timezoneId: "UTC", startDate: start, createdAt: .now)
        #expect(habit.isScheduled(on: start))
        #expect(!habit.isScheduled(on: start.adding(days: -1)))
        #expect(!habit.isScheduled(on: LocalDate(year: 2026, month: 11, day: 14)))
        let weekly = HabitDefinition(kind: .weekly, title: "Бег", targetPerWeek: 3, timezoneId: "UTC", startDate: start, createdAt: .now)
        #expect(!weekly.countsForWeek(starting: start.weekStart))
        #expect(weekly.countsForWeek(starting: start.weekStart.adding(days: 7)))
    }
}
