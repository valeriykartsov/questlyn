import Foundation
import EventKit

/// Событие Apple Calendar для повестки (6.3). Не хранится: событие ≠ выполненное действие (02).
struct AgendaEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarTitle: String
    let attendees: Int
}

/// Apple Calendar, только чтение.
@MainActor
final class CalendarSource {
    private let store = EKEventStore()

    var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func events(from: Date, to: Date) -> [AgendaEvent] {
        guard isAuthorized else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).map { event in
            AgendaEvent(id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                        title: event.title ?? "Без названия", start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                        calendarTitle: event.calendar?.title ?? "", attendees: event.attendees?.count ?? 0)
        }
        .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }
}
