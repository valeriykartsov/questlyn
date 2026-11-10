/// XP в целых сотых, чтобы доли от множителей не терялись (07, раздел 1).
public struct CentiXP: Hashable, Comparable, Codable, Sendable, AdditiveArithmetic {
    public var value: Int

    public init(_ value: Int) { self.value = value }

    /// Целое число XP → сотые.
    public static func xp(_ wholeXP: Int) -> CentiXP { CentiXP(wholeXP * 100) }

    public static let zero = CentiXP(0)

    public static func + (lhs: CentiXP, rhs: CentiXP) -> CentiXP { CentiXP(lhs.value + rhs.value) }
    public static func - (lhs: CentiXP, rhs: CentiXP) -> CentiXP { CentiXP(lhs.value - rhs.value) }
    public static func < (lhs: CentiXP, rhs: CentiXP) -> Bool { lhs.value < rhs.value }
}
