import Foundation
import HealthKit
import Domain
import Application

/// Apple Health, только чтение: Sleep Analysis и шаги (4.7). Данные остаются на устройстве.
struct HealthKitSource: HealthDataSource {
    private let store = HKHealthStore()
    private static let sleepType = HKCategoryType(.sleepAnalysis)
    private static let stepType = HKQuantityType(.stepCount)
    /// Перерыв больше двух часов делит записи на разные ночи.
    private static let sessionGap: TimeInterval = 2 * 3600

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: [Self.sleepType, Self.stepType])
    }

    func sleepNights(from: Date, to: Date, timeZone: TimeZone) async throws -> [HealthSleepNight] {
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: Self.sleepType, predicate: HKQuery.predicateForSamples(withStart: from, end: to))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let intervals = try await descriptor.result(for: store)
            .filter { asleepValues.contains($0.value) }
            .map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
        return Self.nights(from: intervals, timeZone: timeZone)
    }

    /// Объединяет пересечения (часы и телефон пишут одно и то же) и делит на ночи по перерывам.
    static func nights(from intervals: [DateInterval], timeZone: TimeZone) -> [HealthSleepNight] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        var sessions: [[DateInterval]] = []
        for interval in merged {
            if let last = sessions.last?.last, interval.start.timeIntervalSince(last.end) <= sessionGap {
                sessions[sessions.count - 1].append(interval)
            } else {
                sessions.append([interval])
            }
        }
        return sessions.compactMap { parts in
            guard let first = parts.first, let last = parts.last else { return nil }
            let asleep = parts.reduce(0) { $0 + $1.duration }
            return HealthSleepNight(wakeDate: LocalDate(last.end, timeZone: timeZone), asleepMinutes: Int((asleep / 60).rounded()),
                                    startedAt: first.start, endedAt: last.end)
        }
    }

    func stepCounts(from: Date, to: Date, timeZone: TimeZone) async throws -> [LocalDate: Int] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: Self.stepType, predicate: HKQuery.predicateForSamples(withStart: from, end: to)),
            options: .cumulativeSum,
            anchorDate: calendar.startOfDay(for: from),
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        var result: [LocalDate: Int] = [:]
        collection.enumerateStatistics(from: from, to: to) { statistics, _ in
            if let sum = statistics.sumQuantity() {
                result[LocalDate(statistics.startDate, timeZone: timeZone)] = Int(sum.doubleValue(for: .count()))
            }
        }
        return result
    }
}
