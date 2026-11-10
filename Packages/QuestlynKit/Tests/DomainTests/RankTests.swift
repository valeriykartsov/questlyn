import Testing
@testable import Domain

/// 07, раздел 8.
struct RankTests {
    /// «Инженер-программист» (INT, MNT, CHR) + «Атлет» (STR, END, MNT).
    let engineerAthlete: Set<Attribute> = [.intelligence, .mentality, .charisma, .strength, .endurance]

    func levels(_ str: Int, _ end: Int, _ int: Int, _ mnt: Int, _ chr: Int, _ foc: Int, _ dis: Int) -> [Attribute: Int] {
        [.strength: str, .endurance: end, .intelligence: int, .mentality: mnt, .charisma: chr, .focus: foc, .discipline: dis]
    }

    @Test func thresholdsMatchTable() {
        #expect(AdventurerRank.all.map(\.threshold) == [10, 25, 45, 70, 100, 135, 175, 220, 270, 325])
        #expect(AdventurerRank.all.map(\.letter) == ["G", "F", "E", "D", "C", "B", "A", "S", "SS", "SSS"])
    }

    @Test func displayName() {
        #expect(AdventurerRank.all[3].displayName == "Ранг D · Искатель")
    }

    /// Пересчёт симуляции 10.11.2026 (07, раздел 10): очки и ранги по дням.
    @Test("Симуляция v1.1, год при 75%", arguments: [
        (28, [4, 2, 6, 6, 3, 8, 3], 32.0, "F"),
        (91, [9, 6, 14, 14, 8, 18, 7], 76.0, "D"),
        (182, [14, 10, 21, 21, 12, 27, 12], 117.0, "C"),
        (273, [17, 13, 27, 26, 16, 33, 15], 147.0, "B"),
        (364, [21, 15, 31, 31, 19, 39, 18], 174.0, "B"),
    ])
    func simulation(day: Int, values: [Int], points: Double, letter: String) {
        let l = levels(values[0], values[1], values[2], values[3], values[4], values[5], values[6])
        #expect(RankCalculator.points(levels: l, classAttributes: engineerAthlete) == points)
        #expect(RankCalculator.rank(levels: l, classAttributes: engineerAthlete)?.letter == letter)
    }

    @Test func belowGHasNoRank() {
        let l = levels(1, 1, 2, 1, 1, 2, 1)
        let rank = RankCalculator.rank(levels: l, classAttributes: engineerAthlete)
        #expect(rank == nil)
        #expect(AdventurerRank.displayName(for: rank) == "Без ранга")
    }

    @Test func attributesOutsideClassWeighHalf() {
        let programmerOnly: Set<Attribute> = [.intelligence, .mentality, .charisma]
        // STR 4 и END 2 вне класса: (4 + 2) × 0,5 = 3.
        let l = levels(4, 2, 6, 6, 3, 8, 3)
        #expect(RankCalculator.points(levels: l, classAttributes: programmerOnly) == 29)
    }

    @Test func rankSixRequiresEveryClassAttributeAtTwiceRank() {
        // Очков хватает на A (175), но END 11 < 12 — выше ранга 5 нельзя.
        let blocked = levels(40, 11, 40, 40, 40, 20, 20)
        #expect(RankCalculator.rank(levels: blocked, classAttributes: engineerAthlete)?.number == 5)
        let unblocked = levels(40, 12, 40, 40, 40, 20, 20)
        #expect(RankCalculator.rank(levels: unblocked, classAttributes: engineerAthlete)?.number == 6)
    }
}
