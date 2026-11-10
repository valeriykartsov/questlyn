import Foundation

/// Спад атрибутов и форма навыка — проекция начислений по дням (07, разделы 6–7). Ничего не хранится.
public enum ProgressTimeline {
    public static let graceDays = 7
    /// −2% текущего XP в день, в сотых долях: xp · 98 / 100.
    public static let decayKeepPercent = 98
    /// Граница — 70% пика.
    public static let floorPercent = 70

    public static let conditionStart = 100
    public static let conditionRestore = 20
    public static let conditionDecay = 3
    public static let conditionFloor = 40

    /// Событие спада для объяснимости: «−2% CHR — 9 дней без практики».
    public struct DecayEvent: Hashable, Sendable {
        public var attribute: Attribute
        public var date: LocalDate
        public var amount: CentiXP
        public var daysWithoutXP: Int
        public var reachedFloor: Bool
    }

    public struct AttributeState: Hashable, Sendable {
        public var xp: CentiXP
        public var peak: CentiXP
        /// Нижняя граница спада: max(70% пика, стартовый бонус).
        public var floor: CentiXP
        public var lastGainDate: LocalDate?
        public var decay: [DecayEvent]
    }

    /// - Parameter today: до какой даты считать спад; `nil` — без спада (только сумма).
    public static func attributeState(_ attribute: Attribute, grants: [ProgressGrant], today: LocalDate?) -> AttributeState {
        let own = grants.filter { $0.target == .attribute(attribute) }
        let bonus = own.filter { $0.sourceType == .onboardingBonus }.reduce(CentiXP.zero) { $0 + $1.amount }
        guard let today, attribute != .discipline, let first = own.map(\.effectiveDate).min(), first <= today else {
            let total = own.reduce(CentiXP.zero) { $0 + $1.amount }
            return AttributeState(xp: total, peak: total, floor: bonus, lastGainDate: own.filter { $0.amount.value > 0 }.map(\.effectiveDate).max(), decay: [])
        }
        let byDay = Dictionary(grouping: own, by: \.effectiveDate)
        var xp = 0, peak = 0
        var last: LocalDate?
        var events: [DecayEvent] = []
        var day = first
        while day <= today {
            if let todays = byDay[day] {
                xp += todays.reduce(0) { $0 + $1.amount.value }
                if todays.contains(where: { $0.amount.value > 0 }) { last = day }
                peak = max(peak, xp)
            }
            if let last, last.days(until: day) > graceDays {
                let floor = max((peak * floorPercent + 50) / 100, bonus.value)
                let decayed = max(floor, (xp * decayKeepPercent + 50) / 100)
                if decayed < xp {
                    events.append(DecayEvent(attribute: attribute, date: day, amount: CentiXP(decayed - xp),
                                             daysWithoutXP: last.days(until: day), reachedFloor: decayed == floor))
                    xp = decayed
                }
            }
            day = day.adding(days: 1)
        }
        // Начисления «из будущего» (часовые пояса) просто добавляются.
        xp += own.filter { $0.effectiveDate > today }.reduce(0) { $0 + $1.amount.value }
        let floor = max((peak * floorPercent + 50) / 100, bonus.value)
        return AttributeState(xp: CentiXP(xp), peak: CentiXP(max(peak, xp)), floor: CentiXP(floor), lastGainDate: last, decay: events)
    }

    /// Форма навыка 40–100% или `nil` до первой практики.
    public static func condition(skillId: UUID, grants: [ProgressGrant], today: LocalDate?) -> Int? {
        let practiceDays = Set(grants.filter { $0.target == .skill(skillId) && $0.amount.value > 0 }.map(\.effectiveDate))
        guard let first = practiceDays.min() else { return nil }
        guard let today else { return conditionStart }
        var condition = conditionStart
        var last = first
        var day = first.adding(days: 1)
        while day <= today {
            if practiceDays.contains(day) {
                condition = min(conditionStart, condition + conditionRestore)
                last = day
            } else if last.days(until: day) > graceDays {
                condition = max(conditionFloor, condition - conditionDecay)
            }
            day = day.adding(days: 1)
        }
        return condition
    }
}
