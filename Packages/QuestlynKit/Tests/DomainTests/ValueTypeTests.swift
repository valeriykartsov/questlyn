import Foundation
import Testing
@testable import Domain

struct ValueTypeTests {
    @Test func priorityMultipliers() {
        #expect(QuestPriority.default == .medium)
        #expect(QuestPriority.allCases.map(\.multiplier) == [0.5, 1, 1.5])
    }

    @Test func professionAttributesInvariant() {
        let make = { (attributes: [Attribute]) in
            Profession(heroId: UUID(), title: "Тест", slot: 1, attributes: attributes, createdAt: .now)
        }
        #expect(make([.intelligence, .mentality, .charisma]).hasValidAttributes)
        #expect(!make([]).hasValidAttributes)
        #expect(!make([.focus]).hasValidAttributes)
        #expect(!make([.intelligence, .intelligence]).hasValidAttributes)
        #expect(!make([.strength, .endurance, .mentality, .charisma]).hasValidAttributes)
        #expect(Attribute.professionSelectable == [.strength, .endurance, .intelligence, .mentality, .charisma])
    }

    @Test func localDateUsesUserTimeZone() throws {
        // 2026-11-10 22:30 UTC — в Москве уже 11 ноября.
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-11-10T22:30:00Z"))
        #expect(LocalDate(instant, timeZone: try #require(TimeZone(identifier: "UTC"))).description == "2026-11-10")
        #expect(LocalDate(instant, timeZone: try #require(TimeZone(identifier: "Europe/Moscow"))).description == "2026-11-11")
    }

    @Test func localDateAndTimeParsing() {
        #expect(LocalDate(string: "2026-11-10") == LocalDate(year: 2026, month: 11, day: 10))
        #expect(LocalDate(string: "2026-13-01") == nil)
        #expect(LocalTime(string: "09:05")?.description == "09:05")
        #expect(LocalTime(string: "24:00") == nil)
    }
}
