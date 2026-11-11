import Foundation
import Testing
@testable import Domain

/// Этап 8: выбор записи ночи, окно исправления, снятие недельных отметок.
struct Stage8RulesTests {
    let day = LocalDate(year: 2026, month: 11, day: 11)
    let at = Date(timeIntervalSince1970: 1_794_000_000)

    func session(_ minutes: Int, _ source: SleepSource, createdAt offset: TimeInterval = 0) -> SleepSession {
        SleepSession(wakeDate: day, durationMinutes: minutes, bedtimeDeviationMinutes: nil, source: source, timezoneId: "UTC", createdAt: at + offset)
    }

    @Test func correctedNightWinsEvenIfShorter() {
        let nights = SleepRules.nights([session(480, .health), session(300, .corrected), session(510, .manual)])
        #expect(nights[day]?.source == .corrected && nights[day]?.durationMinutes == 300)
        #expect(SleepRules.replacedNights([session(480, .health), session(300, .corrected), session(510, .manual)])[day]?.durationMinutes == 510)
    }

    @Test func latestCorrectionWinsAndLongestOtherwise() {
        #expect(SleepRules.nights([session(300, .corrected, createdAt: 60), session(420, .corrected)])[day]?.durationMinutes == 300)
        #expect(SleepRules.nights([session(300, .health), session(420, .manual)])[day]?.durationMinutes == 420)
        #expect(SleepRules.replacedNights([session(300, .health)]).isEmpty)
    }

    @Test func correctionWindowIsSevenNights() {
        let dates = SleepRules.correctableWakeDates(today: day)
        #expect(dates.count == 7 && dates.first == day.adding(days: -6) && dates.last == day)
    }

    @Test func weeklyUnmarkInsideCurrentWeekOnly() {
        // 11.11.2026 — среда; неделя с понедельника 9.11.
        #expect(HabitMarkingRules.canUnmarkWeekly(LocalDate(year: 2026, month: 11, day: 9), today: day))
        #expect(!HabitMarkingRules.canUnmarkWeekly(LocalDate(year: 2026, month: 11, day: 8), today: day))
        #expect(!HabitMarkingRules.canUnmarkWeekly(day.adding(days: 1), today: day))
    }
}
