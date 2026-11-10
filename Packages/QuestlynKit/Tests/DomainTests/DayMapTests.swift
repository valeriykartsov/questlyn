import Foundation
import Testing
@testable import Domain

/// Карта дня: поселения, маркеры, «вне карты», свет и сезон (02 «Карта дня»).
struct DayMapTests {
    let tz = TimeZone(identifier: "UTC")!
    let day = LocalDate(year: 2026, month: 11, day: 10)

    func at(_ hour: Int, _ minute: Int = 0) -> Date { VitalsCalculator.date(day, LocalTime(hour: hour, minute: minute)!, timeZone: tz) }

    func event(_ title: String, _ start: Date, _ minutes: Double, allDay: Bool = false, attendees: Int = 0) -> MapEvent {
        MapEvent(id: title, title: title, start: start, end: start + minutes * 60, isAllDay: allDay, attendees: attendees)
    }

    @Test func villagesCitiesAndOverlaps() {
        let events = [
            event("Стендап", at(9), 15, attendees: 2),
            event("Встреча", at(11), 90),
            event("Обед", at(13), 30),
            event("Отчёт", at(15), 60),
            event("Созвон", at(15, 30), 60, attendees: 3),
            event("День рождения", at(0), 1440, allDay: true),
        ]
        let map = DayMapBuilder.build(date: day, events: events, quests: [], moods: [], now: at(14, 20), timeZone: tz)
        #expect(map.settlements.map(\.kind) == [.village, .city, .village, .city])
        #expect(map.settlements[3].density == 2 && map.settlements[3].titles == ["Отчёт", "Созвон"] && map.settlements[3].attendees == 3)
        #expect(map.settlements[3].endHour == 16.5)
        #expect(map.offMap == ["Весь день: День рождения"])
        #expect(map.heroHour == 14 + 20.0 / 60 && map.light == .day)
    }

    @Test func touchingEventsAreNotOverlapping() {
        let map = DayMapBuilder.build(date: day, events: [event("А", at(10), 30), event("Б", at(10, 30), 30)], quests: [], moods: [],
                                      now: nil, timeZone: tz)
        #expect(map.settlements.count == 2 && map.settlements.allSatisfy { $0.kind == .village })
        #expect(map.heroHour == nil && map.light == .day)
    }

    @Test func questsAndMoods() {
        let quests = [MapQuest(title: "Банк", start: at(10, 30), isDone: true), MapQuest(title: "Стоматолог", start: nil, isDone: false)]
        let moods = [MoodEntry(mood: .good, at: at(9), localDate: day, timezoneId: "UTC"),
                     MoodEntry(mood: .bad, at: at(14), localDate: day, timezoneId: "UTC")]
        let map = DayMapBuilder.build(date: day, events: [], quests: quests, moods: moods, now: nil, timeZone: tz)
        #expect(map.questMarkers.map(\.hour) == [10.5])
        #expect(map.offMap == ["Квест: Стоматолог"])
        #expect(map.moodFlags.map(\.mood) == [.good, .bad])
        #expect(map.weather == .rain)
    }

    @Test func lightAndSeason() {
        #expect([5.9, 6, 9.9, 10, 16.9, 17, 21.9, 22].map(DayLight.at(hour:)) == [.night, .morning, .morning, .day, .day, .evening, .evening, .night])
        #expect(Season.of(LocalDate(year: 2026, month: 12, day: 1)) == .winter)
        #expect(Season.of(LocalDate(year: 2026, month: 4, day: 1)) == .spring)
        #expect(Season.of(day) == .autumn)
    }

    @Test func eventCrossingMidnightIsClipped() {
        let late = MapEvent(id: "x", title: "Ночная смена", start: at(23), end: at(23) + 3 * 3600, isAllDay: false, attendees: 0)
        let next = DayMapBuilder.build(date: day.adding(days: 1), events: [late], quests: [], moods: [], now: nil, timeZone: tz)
        #expect(next.settlements.first?.startHour == 0 && next.settlements.first?.endHour == 2)
    }
}
