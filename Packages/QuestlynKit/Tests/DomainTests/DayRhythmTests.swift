import Foundation
import Testing
@testable import Domain

/// Этап 9: длительность, лагеря монстров, призраки, вид движения.
struct DayRhythmTests {
    let utc = TimeZone(identifier: "UTC")!
    let day = LocalDate(year: 2026, month: 11, day: 11)

    func quest(time: LocalTime?, duration: Int? = nil, date: LocalDate? = nil) -> Quest {
        Quest(title: "К", dueDate: date ?? day, dueTime: time, timezoneId: "UTC", createdAt: .now, durationMinutes: duration)
    }

    @Test func durationAndMonsters() {
        #expect(QuestTiming.effectiveDuration(quest(time: LocalTime(hour: 15, minute: 0))) == 30)
        #expect(QuestTiming.effectiveDuration(quest(time: LocalTime(hour: 15, minute: 0), duration: 120)) == 120)
        #expect(QuestTiming.effectiveDuration(quest(time: nil, duration: 60)) == nil)
        #expect([15, 30, 60, 90, 120, 180].map(QuestTiming.monsters(minutes:)) == [1, 1, 2, 2, 3, 3])
    }

    @Test func ghostAppearsAfterDueMoment() {
        let timed = quest(time: LocalTime(hour: 18, minute: 0))
        let due = VitalsCalculator.date(day, LocalTime(hour: 18, minute: 0)!, timeZone: utc)
        #expect(QuestTiming.ghostSince(timed, isCompleted: false, now: due - 60, timeZone: utc) == nil)
        #expect(QuestTiming.ghostSince(timed, isCompleted: false, now: due + 60, timeZone: utc) == due)
        #expect(QuestTiming.ghostSince(timed, isCompleted: true, now: due + 60, timeZone: utc) == nil)
        // Без времени — с конца дня срока.
        let untimed = quest(time: nil)
        let midnight = VitalsCalculator.date(day.adding(days: 1), LocalTime(hour: 0, minute: 0)!, timeZone: utc)
        #expect(QuestTiming.ghostSince(untimed, isCompleted: false, now: midnight + 1, timeZone: utc) == midnight)
    }

    @Test func movementModes() {
        let window = SleepWindow(start: LocalTime(hour: 23, minute: 0)!, end: LocalTime(hour: 7, minute: 0)!)
        let work = WorkSchedule(isEnabled: true)
        func at(_ h: Int) -> Date { VitalsCalculator.date(day, LocalTime(hour: h, minute: 0)!, timeZone: utc) }
        #expect(MovementMode.at(at(10), sleepWindow: window, work: work, timeZone: utc) == .farm)
        #expect(MovementMode.at(at(20), sleepWindow: window, work: work, timeZone: utc) == .adventure)
        #expect(MovementMode.at(at(2), sleepWindow: window, work: work, timeZone: utc) == .rest)
        #expect(MovementMode.at(at(10), sleepWindow: window, work: WorkSchedule(), timeZone: utc) == .adventure)
        // Суббота — не рабочий день.
        let saturday = VitalsCalculator.date(LocalDate(year: 2026, month: 11, day: 14), LocalTime(hour: 10, minute: 0)!, timeZone: utc)
        #expect(MovementMode.at(saturday, sleepWindow: window, work: work, timeZone: utc) == .adventure)
    }
}
