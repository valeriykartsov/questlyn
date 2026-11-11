import Foundation
import Domain

/// HP и MP героя — проекция из фактов (08). Ничего не хранится, кроме самих фактов.
public struct VitalsService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    func state(hero: Hero, journal: [TodayItem], sleeps: [SleepSession], settings: VitalSettings,
               grants: [ProgressGrant], now: Date, timeZone: TimeZone) async throws -> VitalsState {
        // Мана тратится и на шаги удалённых Epic: факт выполнения остаётся.
        let quests = Dictionary(try await store.allQuestsIncludingDeleted().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let spends = try await store.allCompletions().filter(\.isActive).compactMap { completion in
            quests[completion.questId].map { ManaSpend(at: completion.completedAt, cost: ManaRules.cost(priority: $0.priority, hasSkill: $0.skillId != nil)) }
        }
        return VitalsCalculator.state(heroCreatedAt: hero.createdAt, grants: grants, spends: spends, sleeps: sleeps,
                                      steps: try await store.stepDays(), settings: settings, now: now, timeZone: timeZone,
                                      harms: try await store.harmEntries())
    }

    public func updateSettings(_ settings: VitalSettings) async throws {
        guard VitalSettings.stepGoalRange.contains(settings.stepGoal) else { throw QuestlynError.invalidStepGoal }
        try await store.save(settings)
    }
}

/// Ручной ввод сна утром — «Как спали?» (4.2, макет 3.3).
public struct SleepService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    @discardableResult
    public func recordManual(duration: ManualSleepDuration, bedtime: ManualBedtime, now: Date, timeZone: TimeZone) async throws -> SleepSession {
        let session = SleepSession(wakeDate: LocalDate(now, timeZone: timeZone), durationMinutes: duration.minutes,
                                   bedtimeDeviationMinutes: bedtime.deviationMinutes, source: .manual,
                                   timezoneId: timeZone.identifier, createdAt: now)
        try await store.saveManualSleep(session)
        return session
    }

    /// Исправление одной из последних 7 ночей точным интервалом (8.1). Побеждает HealthKit и ручной ввод той ночи.
    @discardableResult
    public func correct(wakeDate: LocalDate, startedAt: Date, endedAt: Date, now: Date, timeZone: TimeZone) async throws -> SleepSession {
        let today = LocalDate(now, timeZone: timeZone)
        guard SleepRules.correctableWakeDates(today: today).contains(wakeDate) else { throw QuestlynError.cannotCorrectNight }
        let settings = try await store.vitalSettings()
        guard let session = SleepRules.correction(wakeDate: wakeDate, startedAt: startedAt, endedAt: endedAt,
                                                  window: settings.sleepWindow, timeZone: timeZone, now: now) else {
            throw QuestlynError.invalidSleepInterval
        }
        try await store.saveCorrectedSleep(session)
        return session
    }
}

/// Источник данных Apple Health (только чтение). Реализация — в приложении, чтобы пакет не зависел от HealthKit.
public protocol HealthDataSource: Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    /// Ночной сон по дням пробуждения: длительность сна, начало и конец.
    func sleepNights(from: Date, to: Date, timeZone: TimeZone) async throws -> [HealthSleepNight]
    /// Шаги по дням.
    func stepCounts(from: Date, to: Date, timeZone: TimeZone) async throws -> [LocalDate: Int]
}

public struct HealthSleepNight: Sendable, Hashable {
    public var wakeDate: LocalDate
    public var asleepMinutes: Int
    public var startedAt: Date
    public var endedAt: Date

    public init(wakeDate: LocalDate, asleepMinutes: Int, startedAt: Date, endedAt: Date) {
        self.wakeDate = wakeDate
        self.asleepMinutes = asleepMinutes
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

/// Перенос сна и шагов из Apple Health в факты (4.7). Сегодняшние шаги тоже пишутся: урон считается только после 23:59.
public struct HealthSyncService: Sendable {
    private let store: any QuestlynStore
    private let source: any HealthDataSource
    public static let lookbackDays = 14

    public init(store: any QuestlynStore, source: any HealthDataSource) {
        self.store = store
        self.source = source
    }

    public func sync(now: Date, timeZone: TimeZone) async throws {
        guard source.isAvailable, let hero = try await store.currentHero() else { return }
        let today = LocalDate(now, timeZone: timeZone)
        var first = today.adding(days: -Self.lookbackDays)
        let created = LocalDate(hero.createdAt, timeZone: timeZone)
        if created > first { first = created }
        let from = VitalsCalculator.date(first.adding(days: -1), LocalTime(hour: 12, minute: 0)!, timeZone: timeZone)
        let settings = try await store.vitalSettings()

        let nights = try await source.sleepNights(from: from, to: now, timeZone: timeZone).filter { $0.wakeDate >= first && $0.asleepMinutes > 0 }
        let sessions = nights.map { night in
            SleepSession(wakeDate: night.wakeDate, durationMinutes: min(night.asleepMinutes, 1440),
                         bedtimeDeviationMinutes: SleepRules.bedtimeDeviation(startedAt: night.startedAt, wakeDate: night.wakeDate,
                                                                              window: settings.sleepWindow, timeZone: timeZone),
                         startedAt: night.startedAt, endedAt: night.endedAt, source: .health, timezoneId: timeZone.identifier, createdAt: now)
        }
        var dates: [LocalDate] = []
        var day = first
        while day <= today { dates.append(day); day = day.adding(days: 1) }
        try await store.replaceHealthSleep(sessions, wakeDates: dates)

        let steps = try await source.stepCounts(from: VitalsCalculator.date(first, LocalTime(hour: 0, minute: 0)!, timeZone: timeZone),
                                                to: now, timeZone: timeZone)
        try await store.save(steps.filter { $0.key >= first }.map { StepDay(date: $0.key, steps: $0.value, updatedAt: now) })
    }
}
