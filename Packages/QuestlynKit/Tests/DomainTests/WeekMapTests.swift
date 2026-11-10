import Foundation
import Testing
@testable import Domain

/// Карта недели: привалы сна и час недели (02 от 11.11.2026).
struct WeekMapTests {
    let tz = TimeZone(identifier: "UTC")!
    let monday = LocalDate(year: 2026, month: 11, day: 9)

    func at(_ day: LocalDate, _ h: Int, _ m: Int = 0) -> Date { VitalsCalculator.date(day, LocalTime(hour: h, minute: m)!, timeZone: tz) }

    func night(_ wake: LocalDate, session: SleepSession?) -> VitalsLogEntry {
        let summary = NightSummary(wakeDate: wake, session: session, durationFactor: nil, regimeFactor: nil, quality: 0.5,
                                   hpBefore: 0, hpAfter: 0, mpBefore: 0, mpAfter: 0, maxHP: 100, maxMP: 100)
        return VitalsLogEntry(at: at(wake, 7), kind: .night(summary))
    }

    @Test func campsFromHealthManualAndMissing() {
        let tue = monday.adding(days: 1), wed = monday.adding(days: 2), thu = monday.adding(days: 3)
        let health = SleepSession(wakeDate: tue, durationMinutes: 450, bedtimeDeviationMinutes: 40, startedAt: at(monday, 23, 40),
                                  endedAt: at(tue, 7, 10), source: .health, timezoneId: "UTC", createdAt: at(tue, 8))
        let manual = SleepSession(wakeDate: wed, durationMinutes: 390, bedtimeDeviationMinutes: 0, source: .manual, timezoneId: "UTC", createdAt: at(wed, 8))
        let camps = SleepCampBuilder.camps(from: [night(tue, session: health), night(wed, session: manual), night(thu, session: nil)],
                                           window: .default, timeZone: tz)
        #expect(camps.count == 3)
        #expect(camps[0].start == at(monday, 23, 40) && camps[0].minutes == 450 && camps[0].source == .health)
        #expect(camps[1].end == at(wed, 7) && camps[1].start == at(wed, 0, 30) && camps[1].source == .manual)
        #expect(camps[2].start == at(wed, 23) && camps[2].end == at(thu, 7) && camps[2].minutes == 480 && camps[2].source == nil)
    }

    @Test func weekHourAndHero() {
        #expect(WeekMap.hour(of: at(monday.adding(days: 2), 14, 30), weekStart: monday, timeZone: tz) == 62.5)
        let week = WeekMap.build(weekStart: monday, days: [], camps: [], now: at(monday.adding(days: 2), 14, 30), timeZone: tz)
        #expect(week.heroHour == 62.5)
        let past = WeekMap.build(weekStart: monday.adding(days: -7), days: [], camps: [], now: at(monday, 1), timeZone: tz)
        #expect(past.heroHour == nil)
    }
}
