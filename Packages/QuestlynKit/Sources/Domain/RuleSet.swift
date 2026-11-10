/// Версия правил, по которой считаются начисления (`ProgressGrant.ruleVersion`).
public struct RuleVersion: RawRepresentable, Hashable, Codable, Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Rule Set v1.1 — 07_FORMULAS.md, утверждён 10.11.2026.
    public static let v1_1 = RuleVersion(rawValue: "1.1")
    public static let current = v1_1
}
