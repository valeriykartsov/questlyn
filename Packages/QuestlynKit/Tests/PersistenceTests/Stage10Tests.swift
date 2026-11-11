import Foundation
import Testing
import Domain
import Application
@testable import Persistence

/// Этап 10: детали героя и аура.
struct Stage10Tests {
    @Test func partsAndAccentRoundTrip() async throws {
        let store = GRDBStore(try AppDatabase.inMemory())
        let utc = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-11-10T18:00:00Z")!
        try await OnboardingService(store: store).start(heroName: "Арин", catalogItemIds: ["athlete"], classTitle: "К", now: now, timeZone: utc)
        var look = HeroAppearance(hair: .red, skin: .tan, outfit: .warrior)
        #expect(look.resolvedParts == .preset(.warrior))
        look.parts = HeroAppearance.Parts(hair: .archer, hat: .mage, top: .warrior, bottom: .plateSkirt, shoes: .assassin, item: .sage)
        look.accent = 0x3E5C8A
        try await HeroService(store: store).updateAppearance(look)
        let stored = try #require(try await store.currentHero()).appearance
        #expect(stored == look)
        #expect(stored.resolvedParts.bottom == .plateSkirt)
        #expect(HeroAppearance.Bottom(rawValue: "mage") == .outfit(.mage) && HeroAppearance.Bottom(rawValue: "x") == nil)
    }

    @Test func auraTiersFollowRank() {
        let tiers = AdventurerRank.all.map { AuraTier.of($0) }
        #expect(tiers == [0, 1, 1, 2, 2, 3, 3, 4, 4, 5])
        #expect(AuraTier.of(nil) == 0)
    }
}
