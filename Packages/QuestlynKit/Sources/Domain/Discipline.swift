import Foundation

/// DIS (07, раздел 5): с 17.11.2026 — по дням (день закрывается в 23:59), раньше — по неделям.
public enum DisciplineCalculator {
    public static let maxDrop = 30.0

    public struct WeekInput: Sendable, Equatable {
        /// Для каждого из 7 дней: (выполнено, запланировано) по ежедневным квестам.
        public var days: [(done: Int, scheduled: Int)]
        /// Для каждого недельного квеста: (выполнено, цель).
        public var weekly: [(done: Int, target: Int)]

        public init(days: [(done: Int, scheduled: Int)], weekly: [(done: Int, target: Int)]) {
            self.days = days
            self.weekly = weekly
        }

        public static func == (lhs: WeekInput, rhs: WeekInput) -> Bool {
            lhs.days.map { [$0.done, $0.scheduled] } == rhs.days.map { [$0.done, $0.scheduled] }
                && lhs.weekly.map { [$0.done, $0.target] } == rhs.weekly.map { [$0.done, $0.target] }
        }
    }

    public struct WeekResult: Sendable, Equatable {
        /// Недельный % p.
        public var percent: Double
        public var v: Double
        /// ΔDIS XP до ограничения «не ниже 0».
        public var delta: Double
    }

    public static func evaluate(_ week: WeekInput) -> WeekResult {
        // День без запланированных привычек — 0%.
        let daily = week.days.map { $0.scheduled == 0 ? 0 : 100 * Double(min($0.done, $0.scheduled)) / Double($0.scheduled) }
        // Недельный квест — доля от цели, не больше 100%.
        let weekly = week.weekly.map { 100 * Double(min($0.done, $0.target)) / Double(max($0.target, 1)) }
        let values = daily + weekly
        let p = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        // v считает только ежедневные отметки (02, 10.11.2026).
        let scheduled = week.days.reduce(0) { $0 + $1.scheduled }
        let v = min(1.5, 0.5 + Double(scheduled) / 14)
        let delta = max(-maxDrop, 0.6 * (p - 50) * v)
        return WeekResult(percent: p, v: v, delta: delta)
    }

    /// ΔDIS в centiXP с учётом «DIS XP не ниже 0»; округление — половина вверх.
    public static func grantAmount(delta: Double, currentDIS: CentiXP) -> CentiXP {
        let centi = Int((delta * 100 + 0.5).rounded(.down))
        return CentiXP(max(centi, -currentDIS.value))
    }

    /// Первая неделя, за которую считается DIS: неделя создания героя не считается (02).
    public static func firstCountedWeek(heroCreatedOn date: LocalDate) -> LocalDate {
        date.weekday == .monday ? date : date.weekStart.adding(days: 7)
    }

    /// Детерминированный sourceId недели: одна неделя — одно начисление.
    public static func sourceId(weekStart: LocalDate) -> UUID {
        let digits = String(format: "%04d%02d%02d", weekStart.year, weekStart.month, weekStart.day)
        return UUID(uuidString: "D15C0000-0000-4000-8000-0000\(digits)")!
    }

    // MARK: По дням (15G.1, 17.11.2026)

    public struct DayResult: Sendable, Equatable {
        public var percent: Double
        public var v: Double
        public var delta: Double
    }

    /// ΔDIS за день = max(−30/7; 0,6 · (p_дня − 50) · v / 7), v = min(1,5; 0,5 + запланировано за день · 7 / 14).
    /// В воскресенье в p входят и недельные квесты — долей `min(выполнено; цель) / цель`.
    public static func evaluateDay(done: Int, scheduled: Int, weekly: [(done: Int, target: Int)] = []) -> DayResult {
        let day = scheduled == 0 ? 0 : 100 * Double(min(done, scheduled)) / Double(scheduled)
        let values = [day] + weekly.map { 100 * Double(min($0.done, $0.target)) / Double(max($0.target, 1)) }
        let p = values.reduce(0, +) / Double(values.count)
        let v = min(1.5, 0.5 + Double(scheduled) * 7 / 14)
        let delta = max(-maxDrop / 7, 0.6 * (p - 50) * v / 7)
        return DayResult(percent: p, v: v, delta: delta)
    }

    /// Первый день, за который считается DIS: первый полный день после создания героя.
    public static func firstCountedDay(heroCreatedOn date: LocalDate) -> LocalDate { date.adding(days: 1) }

    /// Детерминированный sourceId дня: один день — одно начисление.
    public static func sourceId(day: LocalDate) -> UUID {
        let digits = String(format: "%04d%02d%02d", day.year, day.month, day.day)
        return UUID(uuidString: "D15D0000-0000-4000-8000-0000\(digits)")!
    }

    public static func isDaily(_ sourceId: UUID) -> Bool { sourceId.uuidString.hasPrefix("D15D") }
}
