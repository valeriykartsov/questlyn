import Foundation
import Domain

/// Что отмечено в листе «Как вы?»: настроение и блок «Здоровье» (макет 3.4).
public struct CheckInDraft: Sendable, Equatable {
    public var mood: Mood?
    public var note: String
    public var isDaySummary: Bool
    /// Счётчики: курение, фастфуд, кофеин после 16:00.
    public var counts: [HarmKind: Int]
    /// Счётчики своих привычек по id.
    public var customCounts: [UUID: Int]
    public var alcohol: AlcoholDegree?
    /// Полезные действия (08, раздел 2.3) и название своего.
    public var benefits: [BenefitKind: Int]
    public var customBenefitTitle: String

    public init(mood: Mood? = nil, note: String = "", isDaySummary: Bool = false, counts: [HarmKind: Int] = [:],
                customCounts: [UUID: Int] = [:], alcohol: AlcoholDegree? = nil, benefits: [BenefitKind: Int] = [:],
                customBenefitTitle: String = "") {
        self.benefits = benefits
        self.customBenefitTitle = customBenefitTitle
        self.mood = mood
        self.note = note
        self.isDaySummary = isDaySummary
        self.counts = counts
        self.customCounts = customCounts
        self.alcohol = alcohol
    }

    public var isEmpty: Bool {
        mood == nil && alcohol == nil && counts.values.allSatisfy { $0 <= 0 } && customCounts.values.allSatisfy { $0 <= 0 }
            && benefits.values.allSatisfy { $0 <= 0 }
    }
}

public struct CheckInReport: Sendable {
    public var mood: MoodEntry?
    public var harms: [HarmEntry]
    public var benefits: [BenefitEntry] = []
}

/// Настроение и вредные привычки (6.1, 6.7, 6.8). Настроение не меняет прогресс.
public struct WellbeingService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    public static let maxCount = 20

    @discardableResult
    public func checkIn(_ draft: CheckInDraft, now: Date, timeZone: TimeZone) async throws -> CheckInReport {
        guard !draft.isEmpty else { throw QuestlynError.emptyCheckIn }
        let date = LocalDate(now, timeZone: timeZone)
        let tz = timeZone.identifier
        var mood: MoodEntry?
        if let value = draft.mood {
            let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
            mood = MoodEntry(mood: value, note: note.isEmpty ? nil : note, isDaySummary: draft.isDaySummary,
                             at: now, localDate: date, timezoneId: tz)
        }
        var harms: [HarmEntry] = []
        for kind in [HarmKind.smoking, .fastFood, .lateCaffeine] {
            let count = min(draft.counts[kind] ?? 0, Self.maxCount)
            guard count > 0, let percent = kind.damagePercent else { continue }
            // Отметки одного сохранения различаются на миллисекунды — порядок в ленте сохраняется.
            harms += (0..<count).map { HarmEntry(kind: kind, title: kind.title, damagePercent: percent, at: now + Double(harms.count + $0) / 1000,
                                                 localDate: date, timezoneId: tz) }
        }
        let custom = try await store.customHarmHabits()
        for habit in custom where habit.isActive {
            let count = min(draft.customCounts[habit.id] ?? 0, Self.maxCount)
            guard count > 0 else { continue }
            harms += (0..<count).map { HarmEntry(kind: .custom, customHabitId: habit.id, title: habit.title, damagePercent: habit.damagePercent,
                                                 at: now + Double(harms.count + $0) / 1000, localDate: date, timezoneId: tz) }
        }
        if let degree = draft.alcohol {
            harms.append(HarmEntry(kind: .alcohol, title: "Алкоголь — \(degree.title.lowercased())", damagePercent: 0, alcohol: degree,
                                   at: now, localDate: date, timezoneId: tz))
        }
        var benefits: [BenefitEntry] = []
        for kind in BenefitKind.allCases {
            let count = min(draft.benefits[kind] ?? 0, Self.maxCount)
            guard count > 0 else { continue }
            let custom = draft.customBenefitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if kind == .custom, custom.isEmpty { throw QuestlynError.emptyName }
            let title = kind == .custom ? custom : kind.title
            benefits += (0..<count).map { BenefitEntry(kind: kind, title: title, at: now + Double(harms.count + benefits.count + $0) / 1000,
                                                       localDate: date, timezoneId: tz) }
        }
        if let mood { try await store.record(mood) }
        if !harms.isEmpty { try await store.record(harms) }
        if !benefits.isEmpty { try await store.record(benefits) }
        return CheckInReport(mood: mood, harms: harms, benefits: benefits)
    }

    public func deleteBenefit(id: UUID, now: Date) async throws { try await store.deleteBenefit(id: id, at: now) }

    public func deleteHarm(id: UUID, now: Date) async throws { try await store.deleteHarm(id: id, at: now) }
    public func deleteMood(id: UUID, now: Date) async throws { try await store.deleteMood(id: id, at: now) }

    @discardableResult
    public func createHabit(title: String, damagePercent: Int, now: Date) async throws -> CustomHarmHabit {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw QuestlynError.emptyName }
        guard CustomHarmHabit.allowedPercents.contains(damagePercent) else { throw QuestlynError.invalidHarmStrength }
        let habit = CustomHarmHabit(title: name, damagePercent: damagePercent, createdAt: now)
        try await store.save(habit)
        return habit
    }

    /// Удалённая привычка пропадает из листа, но её отметки остаются в Летописи.
    public func archiveHabit(id: UUID) async throws {
        guard var habit = try await store.customHarmHabits().first(where: { $0.id == id }) else { return }
        habit.isActive = false
        try await store.save(habit)
    }
}

/// Запись настроения в Apple Health State of Mind. Реализация — в приложении.
public protocol MoodHealthSink: Sendable {
    func write(_ mood: MoodEntry) async throws
}
