/// XP в целых сотых, чтобы доли от множителей не терялись (07, раздел 1).
public struct CentiXP: Hashable, Comparable, Codable, Sendable, AdditiveArithmetic {
    public var value: Int

    public init(_ value: Int) { self.value = value }

    /// Целое число XP → сотые.
    public static func xp(_ wholeXP: Int) -> CentiXP { CentiXP(wholeXP * 100) }

    public static let zero = CentiXP(0)

    /// Точная дробь numerator / denominator, округлённая до целого centiXP, половина — вверх (07, раздел 1).
    public static func roundedHalfUp(numerator: Int, denominator: Int) -> CentiXP {
        precondition(denominator > 0)
        let doubled = 2 * numerator + denominator
        let floorDiv = doubled >= 0 ? doubled / (2 * denominator) : -((-doubled + 2 * denominator - 1) / (2 * denominator))
        return CentiXP(floorDiv)
    }

    /// XP как число — для отображения.
    public var xp: Double { Double(value) / 100 }

    public static func + (lhs: CentiXP, rhs: CentiXP) -> CentiXP { CentiXP(lhs.value + rhs.value) }
    public static func - (lhs: CentiXP, rhs: CentiXP) -> CentiXP { CentiXP(lhs.value - rhs.value) }
    public static func < (lhs: CentiXP, rhs: CentiXP) -> Bool { lhs.value < rhs.value }
}
