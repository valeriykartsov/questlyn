import Foundation
import EventKit
import Domain

/// Событие Apple Calendar для повестки и карты. Не хранится: событие ≠ выполненное действие (02).
struct AgendaEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarId: String
    let calendarTitle: String
    let attendees: Int
}

/// Календарь устройства — для настроек (8.15).
struct DeviceCalendar: Identifiable, Hashable {
    let id: String
    let title: String
    let color: UInt32
}

/// Привязка календаря к профессии или навыку: только цвет и подпись, XP не даёт (02 от 11.11.2026).
struct CalendarLink: Codable, Hashable {
    var professionId: UUID?
    var skillId: UUID?
}

/// Настройки календарей на этом устройстве: календари свои у каждого iPhone, поэтому — UserDefaults.
struct CalendarPreferences: Codable, Equatable {
    var hidden: Set<String> = []
    var links: [String: CalendarLink] = [:]
    var sendQuests = false
    /// Квест → событие в календаре «Questlyn».
    var questEvents: [UUID: String] = [:]

    private static let key = "calendarPreferences"

    static func load() -> CalendarPreferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(CalendarPreferences.self, from: data) else { return CalendarPreferences() }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// Apple Calendar: чтение событий и запись квестов в отдельный календарь «Questlyn».
@MainActor
final class CalendarSource {
    private let store = EKEventStore()
    static let questlynTitle = "Questlyn"
    private static let questlynIdKey = "questlynCalendarId"

    var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    /// Календарь «Questlyn», если уже создан.
    var questlynCalendarId: String? {
        guard let id = UserDefaults.standard.string(forKey: Self.questlynIdKey), store.calendar(withIdentifier: id) != nil else { return nil }
        return id
    }

    func calendars() -> [DeviceCalendar] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .event)
            .filter { $0.calendarIdentifier != questlynCalendarId }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
            .map { DeviceCalendar(id: $0.calendarIdentifier, title: $0.title, color: Self.hex($0.cgColor)) }
    }

    /// События периода без скрытых календарей и без календаря «Questlyn» — квесты и так видны как квесты.
    func events(from: Date, to: Date, hidden: Set<String> = []) -> [AgendaEvent] {
        guard isAuthorized else { return [] }
        let skip = hidden.union([questlynCalendarId].compactMap { $0 })
        let calendars = store.calendars(for: .event).filter { !skip.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
        return store.events(matching: predicate).map { event in
            AgendaEvent(id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                        title: event.title ?? "Без названия", start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                        calendarId: event.calendar?.calendarIdentifier ?? "", calendarTitle: event.calendar?.title ?? "",
                        attendees: event.attendees?.count ?? 0)
        }
        .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    // MARK: Отправка квестов (8.15)

    private func questlynCalendar() throws -> EKCalendar {
        if let id = questlynCalendarId, let calendar = store.calendar(withIdentifier: id) { return calendar }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.questlynTitle
        calendar.cgColor = CGColor(red: 0xB8 / 255, green: 0x65 / 255, blue: 0x1B / 255, alpha: 1)
        // Источник — тот же, что у календаря по умолчанию (iCloud или «На iPhone»).
        calendar.source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .local }
            ?? store.sources.first
        try store.saveCalendar(calendar, commit: true)
        UserDefaults.standard.set(calendar.calendarIdentifier, forKey: Self.questlynIdKey)
        return calendar
    }

    struct QuestEvent {
        let id: UUID
        let title: String
        let date: LocalDate
        let time: LocalTime?
        let isDone: Bool
    }

    /// Квест с датой — событие на весь день, с датой и временем — на 30 минут; выполненный — «✓» в названии.
    /// Квесты без даты и удалённые — событие удаляется. Возвращает новую карту «квест → событие».
    func sync(quests: [QuestEvent], mapping: [UUID: String], timeZone: TimeZone) throws -> [UUID: String] {
        guard isAuthorized else { return mapping }
        let calendar = try questlynCalendar()
        var result: [UUID: String] = [:]
        let wanted = Set(quests.map(\.id))
        for quest in quests {
            let event = mapping[quest.id].flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = (quest.isDone ? "✓ " : "") + quest.title
            if let time = quest.time {
                event.isAllDay = false
                event.startDate = VitalsCalculator.date(quest.date, time, timeZone: timeZone)
                event.endDate = event.startDate.addingTimeInterval(30 * 60)
            } else {
                event.isAllDay = true
                event.startDate = VitalsCalculator.date(quest.date, LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
                event.endDate = event.startDate.addingTimeInterval(24 * 3600 - 1)
            }
            try store.save(event, span: .thisEvent, commit: false)
            result[quest.id] = event.eventIdentifier
        }
        for (questId, eventId) in mapping where !wanted.contains(questId) {
            if let event = store.event(withIdentifier: eventId) { try store.remove(event, span: .thisEvent, commit: false) }
        }
        try store.commit()
        return result
    }

    /// Выключили отправку — убрать все события квестов.
    func removeAll(mapping: [UUID: String]) throws {
        guard isAuthorized else { return }
        for eventId in mapping.values {
            if let event = store.event(withIdentifier: eventId) { try store.remove(event, span: .thisEvent, commit: false) }
        }
        try store.commit()
    }

    private static func hex(_ color: CGColor?) -> UInt32 {
        guard let rgb = color?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let c = rgb.components, c.count >= 3 else { return 0x8E8576 }
        return (UInt32(c[0] * 255) << 16) | (UInt32(c[1] * 255) << 8) | UInt32(c[2] * 255)
    }
}
