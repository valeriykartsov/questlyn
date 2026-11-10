import Foundation

/// Проекция прогресса героя из начислений (03: уровни и ранг не хранятся).
/// С датой `today` учитываются спад атрибутов и форма навыков (07, разделы 6–7).
public struct HeroProgress: Equatable, Sendable {
    public var attributeXP: [Attribute: CentiXP]
    public var attributeStates: [Attribute: ProgressTimeline.AttributeState]
    public var skillXP: [UUID: CentiXP]
    public var skillCondition: [UUID: Int]
    public var classAttributes: Set<Attribute>
    /// Начисления, из которых собрана проекция, — для «Подробнее».
    public var grants: [ProgressGrant]

    public init(grants: [ProgressGrant], classAttributes: Set<Attribute>, today: LocalDate? = nil) {
        var states: [Attribute: ProgressTimeline.AttributeState] = [:]
        for attribute in Attribute.allCases {
            states[attribute] = ProgressTimeline.attributeState(attribute, grants: grants, today: today)
        }
        attributeStates = states
        attributeXP = states.mapValues(\.xp)
        var skills: [UUID: CentiXP] = [:]
        for grant in grants {
            if case .skill(let id) = grant.target { skills[id, default: .zero] += grant.amount }
        }
        skillXP = skills
        skillCondition = Dictionary(uniqueKeysWithValues: skills.keys.compactMap { id in
            ProgressTimeline.condition(skillId: id, grants: grants, today: today).map { (id, $0) }
        })
        self.classAttributes = classAttributes
        self.grants = grants
    }

    public func xp(_ attribute: Attribute) -> CentiXP { attributeXP[attribute] ?? .zero }

    public func peak(_ attribute: Attribute) -> CentiXP { attributeStates[attribute]?.peak ?? .zero }

    public func decayEvents(_ attribute: Attribute) -> [ProgressTimeline.DecayEvent] { attributeStates[attribute]?.decay ?? [] }

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

    /// Начисления атрибута, новые сверху.
    public func grants(for attribute: Attribute) -> [ProgressGrant] {
        grants.filter { $0.target == .attribute(attribute) }.sorted { ($0.effectiveDate, $0.createdAt) > ($1.effectiveDate, $1.createdAt) }
    }

    public static func == (lhs: HeroProgress, rhs: HeroProgress) -> Bool {
        lhs.attributeXP == rhs.attributeXP && lhs.skillXP == rhs.skillXP && lhs.skillCondition == rhs.skillCondition
            && lhs.classAttributes == rhs.classAttributes && lhs.attributeStates == rhs.attributeStates
    }
}
