import Foundation
import Testing
@testable import Domain

/// Уведомления (12D, 13.11.2026): что ставится и что пропускается.
struct NotificationPlannerTests {
    let tz = TimeZone(identifier: "UTC")!
    let today = LocalDate(year: 2026, month: 11, day: 13)
    func at(_ hour: Int, _ minute: Int = 0, plus days: Int = 0) -> Date {
        VitalsCalculator.date(today.adding(days: days), LocalTime(hour: hour, minute: minute)!, timeZone: tz)
    }

    func habit(_ title: String, time: LocalTime?) -> HabitDefinition {
        HabitDefinition(kind: .daily, title: title, weekdays: Set(Weekday.allCases), time: time, timezoneId: "UTC",
                        startDate: today.adding(days: -10), createdAt: at(8, plus: -10))
    }

    func plan(_ settings: NotificationSettings, now: Date, quests: [NotificationPlanner.QuestInput] = [],
              habits: [NotificationPlanner.HabitInput] = [], sleepEntered: Bool = false, summary: Bool = false) -> [PlannedNotification] {
        NotificationPlanner.plan(settings: settings, now: now, timeZone: tz, quests: quests, habits: habits,
                                 wakeTime: LocalTime(hour: 7, minute: 0)!, sleepEnteredToday: sleepEntered, daySummaryToday: summary)
    }

    @Test func nothingWhenAllOff() {
        #expect(plan(NotificationSettings(), now: at(6), quests: [.init(id: UUID(), title: "Отчёт", date: today, time: LocalTime(hour: 18, minute: 0)!, isDone: false)]).isEmpty)
    }

    @Test func questFifteenMinutesBeforeStartUnlessDone() {
        var settings = NotificationSettings()
        settings.quests = true
        let open = NotificationPlanner.QuestInput(id: UUID(), title: "Отчёт", date: today, time: LocalTime(hour: 18, minute: 0)!, isDone: false)
        let done = NotificationPlanner.QuestInput(id: UUID(), title: "Ревью", date: today, time: LocalTime(hour: 19, minute: 0)!, isDone: true)
        let result = plan(settings, now: at(12), quests: [open, done])
        #expect(result.count == 1 && result[0].fireDate == at(17, 45) && result[0].title == "Отчёт")
        #expect(plan(settings, now: at(17, 50), quests: [open]).isEmpty)
    }

    @Test func habitsOwnTimeAndReminderSkipDoneToday() {
        var settings = NotificationSettings()
        settings.habitsOwnTime = true
        settings.habitsReminder = true
        let timed = habit("Зарядка", time: LocalTime(hour: 7, minute: 30)!)
        let untimed = habit("Чтение", time: nil)
        let result = plan(settings, now: at(7), habits: [.init(habit: timed, doneToday: true), .init(habit: untimed, doneToday: false)])
        // Сегодня: Зарядка уже отмечена — без её уведомления; общее напоминание — только про Чтение.
        #expect(!result.contains { $0.id == "habit-\(timed.id)-\(today)" })
        #expect(result.first { $0.id == "habits-\(today)" }?.body == "Чтение")
        // Завтра — оба: своё время у Зарядки и общее напоминание.
        #expect(result.contains { $0.id == "habit-\(timed.id)-\(today.adding(days: 1))" && $0.fireDate == at(7, 30, plus: 1) })
        #expect(!result.contains { $0.id.hasPrefix("habit-\(untimed.id)") })
    }

    @Test func sleepAndMoodSkipWhenAlreadyEntered() {
        var settings = NotificationSettings()
        settings.sleep = true
        settings.mood = true
        let fresh = plan(settings, now: at(6))
        #expect(fresh.contains { $0.id == "sleep-\(today)" && $0.fireDate == at(7, 30) })
        #expect(fresh.contains { $0.id == "mood-\(today)" && $0.fireDate == at(21) })
        let entered = plan(settings, now: at(6), sleepEntered: true, summary: true)
        #expect(!entered.contains { $0.id == "sleep-\(today)" || $0.id == "mood-\(today)" })
        #expect(entered.contains { $0.id == "sleep-\(today.adding(days: 1))" })
        #expect(fresh.count <= NotificationPlanner.limit)
    }
}
