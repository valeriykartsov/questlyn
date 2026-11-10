import Foundation
import Testing
@testable import Domain

/// HP и MP — 08, разделы 2, 3 и 3.1.
struct VitalsTests {
    let tz = TimeZone(identifier: "Europe/Moscow")!
    let day1 = LocalDate(year: 2026, month: 11, day: 10)

    func at(_ day: LocalDate, _ hour: Int, _ minute: Int = 0) -> Date {
        VitalsCalculator.date(day, LocalTime(hour: hour, minute: minute)!, timeZone: tz)
    }

    func state(spends: [ManaSpend] = [], sleeps: [SleepSession] = [], steps: [StepDay] = [], grants: [ProgressGrant] = [],
               now: Date, settings: VitalSettings = .default) -> VitalsState {
        VitalsCalculator.state(heroCreatedAt: at(day1, 10), grants: grants, spends: spends, sleeps: sleeps, steps: steps,
                               settings: settings, now: now, timeZone: tz)
    }

    func manual(_ duration: ManualSleepDuration, _ bedtime: ManualBedtime, wake: LocalDate) -> SleepSession {
        SleepSession(wakeDate: wake, durationMinutes: duration.minutes, bedtimeDeviationMinutes: bedtime.deviationMinutes,
                     source: .manual, timezoneId: tz.identifier, createdAt: at(wake, 8))
    }

    @Test func durationTableWithBestIntervalOnBorders() {
        let cases: [(Int, Double)] = [(239, 0.2), (240, 0.4), (300, 0.6), (360, 0.8), (419, 0.8), (420, 1.0), (540, 1.0), (541, 0.9), (600, 0.9), (601, 0.8)]
        for (minutes, d) in cases { #expect(SleepRules.durationFactor(minutes: minutes) == d, "\(minutes) мин") }
    }

    @Test func regimeTable() {
        #expect(SleepRules.regimeFactor(deviationMinutes: nil) == 1.0)
        #expect(SleepRules.regimeFactor(deviationMinutes: 30) == 1.0)
        #expect(SleepRules.regimeFactor(deviationMinutes: -45) == 0.85)
        #expect(SleepRules.regimeFactor(deviationMinutes: 60) == 0.85)
        #expect(SleepRules.regimeFactor(deviationMinutes: 120) == 0.7)
        #expect(SleepRules.regimeFactor(deviationMinutes: 121) == 0.5)
    }

    @Test func manualButtonsMatchAgreedFactors() {
        let d = ManualSleepDuration.allCases.map { SleepRules.durationFactor(minutes: $0.minutes) }
        #expect(d == [0.4, 0.6, 0.8, 1.0, 1.0, 0.9])
        let r = ManualBedtime.allCases.map { SleepRules.regimeFactor(deviationMinutes: $0.deviationMinutes) }
        #expect(r == [1.0, 0.85, 0.5])
    }

    @Test func manaCostTable() {
        let costs = [QuestPriority.low, .medium, .high].flatMap { p in [false, true].map { ManaRules.cost(priority: p, hasSkill: $0) } }
        #expect(costs == [2, 3, 4, 6, 6, 9])
    }

    @Test func maximaFromLevels() {
        #expect(VitalsCalculator.maxHP(levels: [.strength: 21, .endurance: 15]) == 280)
        #expect(VitalsCalculator.maxMP(levels: [.intelligence: 14, .mentality: 10, .charisma: 11]) == 275)
    }

    @Test func startsFullAndQuestsSpendMana() {
        let spends = (0..<3).map { ManaSpend(at: at(day1, 12 + $0), cost: 4) }
        let s = state(spends: spends, now: at(day1, 20))
        #expect(s.hp == 100 && s.mp == 88 && s.maxMP == 100)
        #expect(s.lastNight == nil, "утро до создания героя не считается")
    }

    @Test func manaNeverBelowZero() {
        let spends = (0..<12).map { ManaSpend(at: at(day1, 11) + Double($0 * 60), cost: 9) }
        let s = state(spends: spends, now: at(day1, 20))
        #expect(s.mp == 0 && s.isExhausted)
    }

    @Test func nightWithoutDataIsNeutral() {
        let spends = (0..<10).map { ManaSpend(at: at(day1, 11) + Double($0 * 60), cost: 9) }
        let s = state(spends: spends, now: at(day1.adding(days: 1), 9))
        // MP 10 + 100 · 0,5 = 60.
        #expect(s.mp == 60)
        #expect(s.lastNight?.isAssumed == true && s.lastNight?.quality == 0.5)
    }

    @Test func manualNightUsesTables() {
        let day2 = day1.adding(days: 1)
        let spends = (0..<10).map { ManaSpend(at: at(day1, 11) + Double($0 * 60), cost: 9) }
        let s = state(spends: spends, sleeps: [manual(.h7to8, .hourLate, wake: day2)], now: at(day2, 9))
        // Q = 1,0 · 0,85; MP 10 + 85 = 95.
        #expect(abs(s.mp - 95) < 0.000_1)
        #expect(s.lastNight?.quality == 0.85)
    }

    @Test func longestSessionWins() {
        let day2 = day1.adding(days: 1)
        let spends = (0..<10).map { ManaSpend(at: at(day1, 11) + Double($0 * 60), cost: 9) }
        let nap = manual(.under5, .onTime, wake: day2)
        let night = manual(.h8to9, .onTime, wake: day2)
        let s = state(spends: spends, sleeps: [nap, night], now: at(day2, 9))
        #expect(s.mp == 100)
    }

    @Test func sedentaryDayDamagesAndSleepHeals() {
        let day2 = day1.adding(days: 1)
        let steps = [StepDay(date: day1, steps: 3000, updatedAt: at(day1, 22))]
        let evening = state(steps: steps, now: at(day1, 23, 59))
        #expect(evening.hp == 95)
        let morning = state(steps: steps, now: at(day2, 8))
        // 95 + 0,6 · 100 · 0,5 = 125 → 100.
        #expect(morning.hp == 100)
        let enough = state(steps: [StepDay(date: day1, steps: 6000, updatedAt: at(day1, 22))], now: at(day1, 23, 59))
        #expect(enough.hp == 100)
    }

    @Test func woundedBelowThirtyPercent() {
        #expect(VitalsState(hp: 29.9, maxHP: 100, mp: 1, maxMP: 100).isWounded)
        #expect(!VitalsState(hp: 30, maxHP: 100, mp: 1, maxMP: 100).isWounded)
    }

    @Test func maximumGrowsWithLevels() {
        // Уровень берётся по дате события: STR 1 со второго дня, до утреннего восстановления.
        let day2 = day1.adding(days: 1)
        let grant = ProgressGrant(sourceType: .questCompletion, sourceId: UUID(), ruleVersion: .v1_1, target: .attribute(.strength),
                                  amount: .xp(20), reason: "", createdAt: at(day2, 0, 30), effectiveDate: day2)
        let s = state(grants: [grant], now: at(day2, 6))
        #expect(s.maxHP == 105)
        #expect(s.hp == 100, "растёт только максимум")
    }

    @Test func bedtimeDeviationAcrossMidnight() {
        let day2 = day1.adding(days: 1)
        #expect(SleepRules.bedtimeDeviation(startedAt: at(day1, 23, 40), wakeDate: day2, window: .default, timeZone: tz) == 40)
        #expect(SleepRules.bedtimeDeviation(startedAt: at(day2, 0, 30), wakeDate: day2, window: .default, timeZone: tz) == 90)
        #expect(SleepRules.bedtimeDeviation(startedAt: at(day1, 22, 30), wakeDate: day2, window: .default, timeZone: tz) == 30)
    }
}
