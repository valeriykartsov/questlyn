import Foundation

// Летопись героя (08, раздел 4 и 4.1). Лента собирается из фактов и начислений;
// отдельно хранятся только вехи — уровни, ранг, завершение Epic.

/// Сохранённая веха с версией правил, по которым она получена.
public struct ChronicleEntry: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case attributeLevel, rank, epicCompleted }

    public var id: UUID
    public var kind: Kind
    /// Ключ вехи: `level:INT:14`, `rank:4`, `epic:<id>`. Один ключ — одна действующая веха.
    public var key: String
    public var title: String
    public var occurredAt: Date
    public var localDate: LocalDate
    public var ruleVersion: RuleVersion
    public var createdAt: Date
    /// Веху сняла отмена факта (или Epic открыт снова) — запись зачёркнута.
    public var cancelledAt: Date?
    /// Веха не подтверждается после смены правил — «пересчитано по правилам vN».
    public var recalculatedBy: RuleVersion?

    public init(id: UUID = UUID(), kind: Kind, key: String, title: String, occurredAt: Date, localDate: LocalDate,
                ruleVersion: RuleVersion, createdAt: Date, cancelledAt: Date? = nil, recalculatedBy: RuleVersion? = nil) {
        self.id = id
        self.kind = kind
        self.key = key
        self.title = title
        self.occurredAt = occurredAt
        self.localDate = localDate
        self.ruleVersion = ruleVersion
        self.createdAt = createdAt
        self.cancelledAt = cancelledAt
        self.recalculatedBy = recalculatedBy
    }

    public var isActive: Bool { cancelledAt == nil && recalculatedBy == nil }
}

/// Веха, выведенная из начислений: впервые достигнутый уровень атрибута или ранг.
public struct Milestone: Hashable, Sendable {
    public var kind: ChronicleEntry.Kind
    public var key: String
    public var title: String
    public var date: LocalDate
    public var at: Date

    public init(kind: ChronicleEntry.Kind, key: String, title: String, date: LocalDate, at: Date) {
        self.kind = kind
        self.key = key
        self.title = title
        self.date = date
        self.at = at
    }
}

public enum MilestoneDetector {
    /// Уровни на конец каждого дня с учётом спада; веха — первое достижение (08, 4.1).
    public static func milestones(grants: [ProgressGrant], classAttributes: Set<Attribute>, from firstDay: LocalDate,
                                  through today: LocalDate, timeZone: TimeZone) -> [Milestone] {
        guard firstDay <= today else { return [] }
        var best: [Attribute: Int] = [:]
        var bestRank = 0
        var result: [Milestone] = []
        let byDay = Dictionary(grouping: grants, by: \.effectiveDate)
        var day = firstDay
        while day <= today {
            let upToDay = grants.filter { $0.effectiveDate <= day }
            var levels: [Attribute: Int] = [:]
            for attribute in Attribute.allCases {
                levels[attribute] = LevelCurve.level(for: ProgressTimeline.attributeState(attribute, grants: upToDay, today: day).xp)
            }
            let endOfDay = VitalsCalculator.date(day, LocalTime(hour: 23, minute: 59)!, timeZone: timeZone)
            func moment(_ attributes: [Attribute]) -> Date {
                let times = (byDay[day] ?? []).filter { grant in
                    grant.amount.value > 0 && attributes.contains { grant.target == .attribute($0) }
                }.map(\.createdAt)
                return times.max() ?? endOfDay
            }
            var raised: [Attribute] = []
            for attribute in Attribute.allCases {
                let level = levels[attribute] ?? 0
                let previous = best[attribute] ?? 0
                guard level > previous else { continue }
                raised.append(attribute)
                for reached in (previous + 1)...level {
                    result.append(Milestone(kind: .attributeLevel, key: "level:\(attribute.code):\(reached)",
                                            title: "\(attribute.code) · уровень \(reached)", date: day, at: moment([attribute])))
                }
                best[attribute] = level
            }
            if let rank = RankCalculator.rank(levels: levels, classAttributes: classAttributes), rank.number > bestRank {
                for number in (bestRank + 1)...rank.number {
                    let reached = AdventurerRank.all[number - 1]
                    result.append(Milestone(kind: .rank, key: "rank:\(number)", title: "Ранг \(reached.letter) · \(reached.title)",
                                            date: day, at: moment(raised)))
                }
                bestRank = rank.number
            }
            day = day.adding(days: 1)
        }
        return result
    }
}

/// Строки спада подряд по одному атрибуту сворачиваются в одну (08, 4.1).
public struct DecayRun: Hashable, Sendable {
    public var attribute: Attribute
    public var firstDate: LocalDate
    public var lastDate: LocalDate
    public var days: Int
    public var amount: CentiXP
    public var daysWithoutXPAtEnd: Int
    public var reachedFloor: Bool

    public static func runs(_ events: [ProgressTimeline.DecayEvent]) -> [DecayRun] {
        var result: [DecayRun] = []
        for event in events.sorted(by: { ($0.attribute.code, $0.date) < ($1.attribute.code, $1.date) }) {
            if var last = result.last, last.attribute == event.attribute, last.lastDate.adding(days: 1) == event.date {
                last.lastDate = event.date
                last.days += 1
                last.amount = CentiXP(last.amount.value + event.amount.value)
                last.daysWithoutXPAtEnd = event.daysWithoutXP
                last.reachedFloor = last.reachedFloor || event.reachedFloor
                result[result.count - 1] = last
            } else {
                result.append(DecayRun(attribute: event.attribute, firstDate: event.date, lastDate: event.date, days: 1,
                                       amount: event.amount, daysWithoutXPAtEnd: event.daysWithoutXP, reachedFloor: event.reachedFloor))
            }
        }
        return result
    }
}
