import Foundation
import Testing
@testable import Domain

/// Погода, похмелье и урон от отметок (02 «Карта дня», 08 2.1–2.2).
struct WellbeingTests {
    let tz = TimeZone(identifier: "UTC")!
    let day = LocalDate(year: 2026, month: 11, day: 10)

    func at(_ hour: Int, _ minute: Int = 0, on date: LocalDate? = nil) -> Date {
        VitalsCalculator.date(date ?? day, LocalTime(hour: hour, minute: minute)!, timeZone: tz)
    }

    func harm(_ kind: HarmKind, percent: Int = 0, alcohol: AlcoholDegree? = nil, at date: Date) -> HarmEntry {
        HarmEntry(kind: kind, title: kind.title, damagePercent: percent, alcohol: alcohol, at: date, localDate: LocalDate(date, timeZone: tz), timezoneId: "UTC")
    }

    @Test func weatherFromMood() {
        #expect(Weather.from(nil, on: day) == .clear)
        #expect(Weather.from(.good, on: day) == .clear)
        #expect(Weather.from(.neutral, on: day) == .cloudy)
        #expect(Weather.from(.bad, on: day) == .rain)
        #expect(Weather.from(.bad, on: LocalDate(year: 2026, month: 12, day: 1)) == .snow)
        #expect(Weather.from(.bad, on: LocalDate(year: 2027, month: 2, day: 28)) == .snow)
    }

    @Test func alcoholRemovesLevels() {
        #expect(AlcoholDegree.little.removedLevels(of: 14) == 1)
        #expect(AlcoholDegree.lots.removedLevels(of: 14) == 3)
        #expect(AlcoholDegree.little.removedLevels(of: 5) == 1)
        #expect(AlcoholDegree.lots.removedLevels(of: 5) == 2)
        #expect(AlcoholDegree.lots.removedLevels(of: 1) == 1)
        #expect(AlcoholDegree.little.removedLevels(of: 0) == 0)
    }

    @Test func repeatTakesStrongerAndRestarts() {
        let entries = [harm(.alcohol, alcohol: .lots, at: at(20)), harm(.alcohol, alcohol: .little, at: at(23))]
        let timeline = Hangover.timeline(entries)
        #expect(timeline.count == 1)
        #expect(timeline[0].degree == .lots && timeline[0].until == at(23) + 24 * 3600)
        #expect(Hangover.active(at: at(22, 59, on: day.adding(days: 1)), in: timeline) != nil)
        #expect(Hangover.active(at: at(23, 1, on: day.adding(days: 1)), in: timeline) == nil)
    }

    @Test func smokingDamagesShareOfMaxHP() {
        let start = at(9)
        let harms = [harm(.smoking, percent: 3, at: at(10)), harm(.smoking, percent: 3, at: at(11))]
        let state = VitalsCalculator.state(heroCreatedAt: start, grants: [], spends: [], sleeps: [], steps: [], settings: .default,
                                           now: at(12), timeZone: tz, harms: harms)
        #expect(state.hp == 94)
        var deleted = harms
        deleted[1].deletedAt = at(11, 30)
        let back = VitalsCalculator.state(heroCreatedAt: start, grants: [], spends: [], sleeps: [], steps: [], settings: .default,
                                          now: at(12), timeZone: tz, harms: deleted)
        #expect(back.hp == 97)
    }

    @Test func hangoverLowersMaxManaAndBurnsExcess() {
        let start = at(9)
        // INT 2 (20 + 25 XP) → MaxMP 110; «немного» снимает 1 уровень → 105.
        let grant = ProgressGrant(sourceType: .questCompletion, sourceId: UUID(), ruleVersion: .v1_1, target: .attribute(.intelligence),
                                  amount: .xp(45), reason: "", createdAt: start, effectiveDate: day)
        let harms = [harm(.alcohol, alcohol: .little, at: at(20))]
        let during = VitalsCalculator.state(heroCreatedAt: start, grants: [grant], spends: [], sleeps: [], steps: [], settings: .default,
                                            now: at(21), timeZone: tz, harms: harms)
        #expect(during.maxMP == 105 && during.mp == 105)
        #expect(during.intelligenceLevel == 2 && during.effectiveIntelligence == 1)
        let after = VitalsCalculator.state(heroCreatedAt: start, grants: [grant], spends: [], sleeps: [], steps: [], settings: .default,
                                           now: at(21, on: day.adding(days: 1)), timeZone: tz, harms: harms)
        #expect(after.maxMP == 110 && after.hangover == nil)
    }

    // MARK: Этап 12D: интоксикация, Perfect, курение −1%

    func checkIn(lots: Bool, smoking: Int, at moment: Date) -> [HarmEntry] {
        (0..<smoking).map { harm(.smoking, percent: 1, at: moment + Double($0) / 1000) } + [harm(.alcohol, alcohol: lots ? .lots : .little, at: moment)]
    }

    @Test func intoxicationNeedsLotsAndMoreThanTenSmokingInOneCheckIn() {
        #expect(HarmKind.smoking.damagePercent == 1)
        #expect(Intoxication.timeline(checkIn(lots: true, smoking: 11, at: at(20))).count == 1)
        #expect(Intoxication.timeline(checkIn(lots: true, smoking: 10, at: at(20))).isEmpty)
        #expect(Intoxication.timeline(checkIn(lots: false, smoking: 15, at: at(20))).isEmpty)
        // Разные отметки не складываются.
        let apart = (0..<11).map { harm(.smoking, percent: 1, at: at(18) + Double($0) / 1000) } + [harm(.alcohol, alcohol: .lots, at: at(20))]
        #expect(Intoxication.timeline(apart).isEmpty)
        let timeline = Intoxication.timeline(checkIn(lots: true, smoking: 11, at: at(20)))
        #expect(Intoxication.active(at: at(7, 59, on: day.adding(days: 1)), in: timeline) != nil)
        #expect(Intoxication.active(at: at(8, 1, on: day.adding(days: 1)), in: timeline) == nil)
    }

    @Test func intoxicationLowersMaxHPAndBlocksPerfect() {
        let start = at(9)
        // STR 1 и END 1 (по 20 XP) → MaxHP 110; интоксикация снимает по уровню → 100.
        let grants = [Attribute.strength, .endurance].map {
            ProgressGrant(sourceType: .questCompletion, sourceId: UUID(), ruleVersion: .v1_1, target: .attribute($0),
                          amount: .xp(20), reason: "", createdAt: start, effectiveDate: day)
        }
        let calm = VitalsCalculator.state(heroCreatedAt: start, grants: grants, spends: [], sleeps: [], steps: [], settings: .default,
                                          now: at(19), timeZone: tz, harms: [])
        #expect(calm.maxHP == 110 && calm.isPerfect && calm.nominalMaxHP == 110)
        let harms = checkIn(lots: true, smoking: 11, at: at(20))
        let during = VitalsCalculator.state(heroCreatedAt: start, grants: grants, spends: [], sleeps: [], steps: [], settings: .default,
                                            now: at(21), timeZone: tz, harms: harms)
        #expect(during.intoxication != nil && during.strengthRemoved == 1 && during.enduranceRemoved == 1)
        #expect(during.maxHP == 100 && during.nominalMaxHP == 110)
        #expect(!during.isPerfect)
        let after = VitalsCalculator.state(heroCreatedAt: start, grants: grants, spends: [], sleeps: [], steps: [], settings: .default,
                                           now: at(9, on: day.adding(days: 1)), timeZone: tz, harms: harms)
        #expect(after.intoxication == nil && after.maxHP == 110)
    }
}
