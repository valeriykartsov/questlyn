import Foundation

/// Проекция прогресса героя из начислений (03: уровни и ранг не хранятся).
public struct HeroProgress: Equatable, Sendable {
    public var attributeXP: [Attribute: CentiXP]
    public var skillXP: [UUID: CentiXP]
    public var classAttributes: Set<Attribute>

    public init(grants: [ProgressGrant], classAttributes: Set<Attribute>) {
        var attributes: [Attribute: CentiXP] = [:]
        var skills: [UUID: CentiXP] = [:]
        for grant in grants {
            switch grant.target {
            case .attribute(let attribute): attributes[attribute, default: .zero] += grant.amount
            case .skill(let id): skills[id, default: .zero] += grant.amount
            }
        }
        attributeXP = attributes
        skillXP = skills
        self.classAttributes = classAttributes
    }

    public func xp(_ attribute: Attribute) -> CentiXP { attributeXP[attribute] ?? .zero }

    public func level(_ attribute: Attribute) -> Int { LevelCurve.level(for: xp(attribute)) }

    public var levels: [Attribute: Int] {
        Dictionary(uniqueKeysWithValues: Attribute.allCases.map { ($0, level($0)) })
    }

    public var rank: AdventurerRank? { RankCalculator.rank(levels: levels, classAttributes: classAttributes) }

    public var rankPoints: Double { RankCalculator.points(levels: levels, classAttributes: classAttributes) }

    /// Следующий ранг (или G, если ранга ещё нет).
    public var nextRank: AdventurerRank? {
        let number = (rank?.number ?? 0) + 1
        return AdventurerRank.all.first { $0.number == number }
    }

    /// Прогресс внутри текущего уровня атрибута: (накоплено, нужно), в XP.
    public func levelProgress(_ attribute: Attribute) -> (current: Double, needed: Int) {
        let level = level(attribute)
        let base = LevelCurve.totalXP(forLevel: level)
        return (xp(attribute).xp - Double(base), LevelCurve.cost(fromLevel: level))
    }
}
