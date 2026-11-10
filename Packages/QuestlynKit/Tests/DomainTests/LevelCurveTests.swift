import Testing
@testable import Domain

/// 07, раздел 3: переход L → L+1 стоит 20 + 5·L XP.
struct LevelCurveTests {
    @Test("Таблица «всего XP» из 07", arguments: [
        (1, 20), (2, 45), (3, 75), (5, 150), (10, 425), (15, 825), (20, 1350), (30, 2775),
    ])
    func totalXP(level: Int, total: Int) {
        #expect(LevelCurve.totalXP(forLevel: level) == total)
    }

    @Test func levelBoundaries() {
        #expect(LevelCurve.level(for: .zero) == 0)
        #expect(LevelCurve.level(for: CentiXP(1999)) == 0)
        #expect(LevelCurve.level(for: .xp(20)) == 1)
        #expect(LevelCurve.level(for: CentiXP(4499)) == 1)
        #expect(LevelCurve.level(for: .xp(45)) == 2)
        #expect(LevelCurve.level(for: .xp(2775)) == 30)
        #expect(LevelCurve.level(for: CentiXP(-500)) == 0)
    }

    @Test func costGrowsByFive() {
        #expect(LevelCurve.cost(fromLevel: 0) == 20)
        #expect(LevelCurve.cost(fromLevel: 1) == 25)
        #expect(LevelCurve.cost(fromLevel: 10) == 70)
    }
}
