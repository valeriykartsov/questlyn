import Foundation
import Domain

/// Фильтры Летописи (08, 4.1). «Все» — отсутствие фильтра.
public enum ChronicleCategory: String, CaseIterable, Sendable {
    case quests, habits, health, progress

    public var title: String {
        switch self {
        case .quests: "Квесты"
        case .habits: "Привычки"
        case .health: "Здоровье"
        case .progress: "Прогресс"
        }
    }
}

/// Изменение в строке ленты: XP с целью, HP или MP.
public enum ChronicleChange: Hashable, Sendable {
    case xp(label: String, amount: CentiXP)
    case hp(Double)
    case mp(Double)
}

public struct ChronicleItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var at: Date
    public var category: ChronicleCategory
    public var title: String
    public var detail: String?
    public var changes: [ChronicleChange]
    /// Отменённая запись или снятая веха — зачёркнута.
    public var isCancelled: Bool
    public var note: String?
    /// Веха — выделяется в ленте.
    public var isMilestone: Bool
    /// Короткая пометка рядом с заголовком, например «исправлено» у ночи (8.1).
    public var badge: String? = nil
}

public struct ChronicleDay: Identifiable, Hashable, Sendable {
    public var date: LocalDate
    public var items: [ChronicleItem]
    public var id: LocalDate { date }

    public init(date: LocalDate, items: [ChronicleItem]) {
        self.date = date
        self.items = items
    }
}

public struct ChronicleService: Sendable {
    private let store: any QuestlynStore
    public init(store: any QuestlynStore) { self.store = store }

    public static let cancelledNote = "Отменено · начисления сняты"

    // MARK: Вехи

    /// Сверяет сохранённые вехи с выведенными из начислений: новые — записать, неподтверждённые — зачеркнуть.
    public func syncMilestones(now: Date, timeZone: TimeZone) async throws {
        guard let hero = try await store.currentHero() else { return }
        let professions = try await store.professions(heroId: hero.id)
        let today = LocalDate(now, timeZone: timeZone)
        var derived = MilestoneDetector.milestones(
            grants: try await store.allGrants(), classAttributes: ClassRules.classAttributes(of: professions),
            from: LocalDate(hero.createdAt, timeZone: timeZone), through: today, timeZone: timeZone
        )
        for epic in try await store.epics() {
            guard let done = epic.completedAt else { continue }
            derived.append(Milestone(kind: .epicCompleted, key: "epic:\(epic.id.uuidString.lowercased())",
                                     title: "Epic завершён · «\(epic.title)»", date: LocalDate(done, timeZone: timeZone), at: done))
        }
        let stored = try await store.chronicleEntries()
        let activeKeys = Set(stored.filter(\.isActive).map(\.key))
        let derivedKeys = Set(derived.map(\.key))
        var changes: [ChronicleEntry] = derived.filter { !activeKeys.contains($0.key) }.map { milestone in
            ChronicleEntry(kind: milestone.kind, key: milestone.key, title: milestone.title, occurredAt: milestone.at,
                           localDate: milestone.date, ruleVersion: .current, createdAt: now)
        }
        for var entry in stored where entry.isActive && !derivedKeys.contains(entry.key) {
            if entry.ruleVersion != .current { entry.recalculatedBy = .current } else { entry.cancelledAt = now }
            changes.append(entry)
        }
        if !changes.isEmpty { try await store.save(changes) }
    }

    // MARK: Лента

    public func feed(now: Date, timeZone: TimeZone) async throws -> [ChronicleDay] {
        guard let hero = try await store.currentHero() else { return [] }
        let professions = try await store.professions(heroId: hero.id)
        let skills = Dictionary(try await store.skills().map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let grants = try await store.allGrants()
        let bySource = Dictionary(grouping: grants, by: \.sourceId)
        let quests = Dictionary(try await store.allQuestsIncludingDeleted().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let completions = try await store.allCompletions()
        let epics = Dictionary(try await store.epics().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let habits = Dictionary(try await store.habits().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func changes(_ sourceId: UUID) -> [ChronicleChange] {
            (bySource[sourceId] ?? []).map { grant in
                switch grant.target {
                case let .attribute(attribute): .xp(label: attribute.code, amount: grant.amount)
                case let .skill(id): .xp(label: skills[id] ?? "Навык", amount: grant.amount)
                }
            }
        }

        var items: [ChronicleItem] = []

        // Квесты и шаги Epic.
        for completion in completions {
            guard let quest = quests[completion.questId] else { continue }
            var detail: String?
            if let epicId = quest.epicId, let epic = epics[epicId] {
                let steps = quests.values.filter { $0.epicId == epicId }.sorted { ($0.dueDate ?? .distant, $0.createdAt) < ($1.dueDate ?? .distant, $1.createdAt) }
                let index = (steps.firstIndex { $0.id == quest.id } ?? 0) + 1
                detail = "Шаг \(index) из \(steps.count) · \(epic.title)"
            }
            var rowChanges: [ChronicleChange] = []
            if completion.isActive {
                rowChanges = changes(completion.id)
                rowChanges.append(.mp(-ManaRules.cost(priority: quest.priority, hasSkill: quest.skillId != nil)))
            }
            items.append(ChronicleItem(id: "quest:\(completion.id)", at: completion.completedAt, category: .quests, title: quest.title,
                                       detail: detail, changes: rowChanges, isCancelled: !completion.isActive,
                                       note: completion.isActive ? nil : Self.cancelledNote, isMilestone: false))
        }

        // Привычки и Activity.
        for occurrence in try await store.allOccurrences() {
            let habit = habits[occurrence.habitId]
            items.append(ChronicleItem(id: "habit:\(occurrence.id)", at: occurrence.completedAt, category: .habits,
                                       title: habit?.title ?? "Привычка", detail: habit.map { $0.kind == .daily ? "Ежедневный квест" : "Недельный квест" },
                                       changes: occurrence.isActive ? changes(occurrence.id) : [], isCancelled: !occurrence.isActive,
                                       note: occurrence.isActive ? nil : Self.cancelledNote, isMilestone: false))
        }
        for activity in try await store.allActivities() {
            let template = ActivityTemplate.all.first { $0.id == activity.templateId }
            let active = activity.deletedAt == nil
            var detail = activity.skillId.flatMap { skills[$0] }.map { "Навык «\($0)»" }
            if active, activity.creditedMinutes < activity.durationMinutes {
                detail = [detail, "в XP \(activity.creditedMinutes) мин — предел 3 ч в день"].compactMap { $0 }.joined(separator: " · ")
            }
            items.append(ChronicleItem(id: "activity:\(activity.id)", at: activity.startedAt, category: .habits,
                                       title: "\(template?.title ?? "Активность") · \(activity.durationMinutes) мин", detail: detail,
                                       changes: active ? changes(activity.id) : [], isCancelled: !active,
                                       note: active ? nil : Self.cancelledNote, isMilestone: false))
        }

        // Здоровье: ночи и сидячие дни из проекции HP и MP.
        let settings = try await store.vitalSettings()
        let spends = completions.filter(\.isActive).compactMap { completion in
            quests[completion.questId].map { ManaSpend(at: completion.completedAt, cost: ManaRules.cost(priority: $0.priority, hasSkill: $0.skillId != nil)) }
        }
        let vitals = VitalsCalculator.state(heroCreatedAt: hero.createdAt, grants: grants, spends: spends, sleeps: try await store.sleepSessions(),
                                            steps: try await store.stepDays(), settings: settings, now: now, timeZone: timeZone,
                                            harms: try await store.harmEntries(), benefits: try await store.benefitEntries())
        for (index, entry) in vitals.log.enumerated() {
            switch entry.kind {
            case let .night(night):
                let title: String
                if let session = night.session {
                    let regime = (night.regimeFactor ?? 1) >= 1 ? "режим соблюдён" : "отбой позже режима"
                    title = "Сон \(Self.duration(session.durationMinutes)) · \(regime)"
                } else {
                    title = "Сон: нет данных · ночь нейтральная"
                }
                let source: String? = night.session.map { session in
                    guard session.source == .corrected else { return Self.sourceTitle(session.source) }
                    return night.replaced.map { "было \(Self.duration($0.durationMinutes)), \(Self.sourceTitle($0.source))" } ?? "было: нет данных"
                }
                // Нулевые изменения не показываем: HP и MP уже были полными.
                let restored = [ChronicleChange.hp(night.hpAfter - night.hpBefore), .mp(night.mpAfter - night.mpBefore)].filter { change in
                    switch change {
                    case let .hp(value), let .mp(value): abs(value) >= 0.5
                    case .xp: true
                    }
                }
                let full = restored.isEmpty ? "HP и MP уже полные" : nil
                items.append(ChronicleItem(id: "night:\(index)", at: entry.at, category: .health, title: title,
                                           detail: [source, "качество \(Int((night.quality * 100).rounded()))%", full].compactMap { $0 }.joined(separator: " · "),
                                           changes: restored, isCancelled: false, note: nil, isMilestone: false,
                                           badge: night.session?.source == .corrected ? "исправлено" : nil))
            case let .harm(harm, hpDamage, mpBurned):
                if harm.kind == .alcohol {
                    var rowChanges: [ChronicleChange] = []
                    if mpBurned >= 0.5 { rowChanges.append(.mp(-mpBurned)) }
                    items.append(ChronicleItem(id: "harm:\(harm.id)", at: entry.at, category: .health, title: harm.title,
                                               detail: "похмелье на 24 ч · INT и MaxMP ниже, XP не меняется", changes: rowChanges,
                                               isCancelled: false, note: nil, isMilestone: false))
                } else {
                    items.append(ChronicleItem(id: "harm:\(harm.id)", at: entry.at, category: .health, title: harm.title,
                                               detail: "−\(harm.damagePercent)% HP за отметку", changes: [.hp(-hpDamage)],
                                               isCancelled: false, note: nil, isMilestone: false))
                }
            case let .benefit(benefit, restored):
                items.append(ChronicleItem(id: "benefit:\(benefit.id)", at: entry.at, category: .health, title: "Полезное: \(benefit.title)",
                                           detail: restored >= 0.5 ? "+3% HP за отметку" : "дневной предел +10% HP набран или HP полное",
                                           changes: restored >= 0.5 ? [.hp(restored)] : [], isCancelled: false, note: nil, isMilestone: false))
            case let .sedentary(_, steps, goal, damage):
                items.append(ChronicleItem(id: "sedentary:\(index)", at: entry.at, category: .health, title: "Сидячий день",
                                           detail: "\(steps) из \(goal) шагов", changes: [.hp(-damage)],
                                           isCancelled: false, note: nil, isMilestone: false))
            }
        }

        // Удалённые отметки здоровья — зачёркнуты; настроение — в «Здоровье» рядом с самочувствием.
        for harm in try await store.harmEntries() where !harm.isActive {
            items.append(ChronicleItem(id: "harm:\(harm.id)", at: harm.at, category: .health, title: harm.title, detail: nil, changes: [],
                                       isCancelled: true, note: "Удалено · урон возвращён", isMilestone: false))
        }
        for benefit in try await store.benefitEntries() where !benefit.isActive {
            items.append(ChronicleItem(id: "benefit:\(benefit.id)", at: benefit.at, category: .health, title: "Полезное: \(benefit.title)",
                                       detail: nil, changes: [], isCancelled: true, note: "Удалено", isMilestone: false))
        }
        for mood in try await store.moodEntries() {
            let weather = Weather.from(mood.mood, on: mood.localDate)
            let detail = [mood.isDaySummary ? "итог дня" : nil, "погода: \(weather.title.lowercased())", mood.note].compactMap { $0 }.joined(separator: " · ")
            items.append(ChronicleItem(id: "mood:\(mood.id)", at: mood.at, category: .health, title: "Настроение: \(mood.mood.title.lowercased())",
                                       detail: detail, changes: [], isCancelled: mood.deletedAt != nil,
                                       note: mood.deletedAt != nil ? "Удалено" : nil, isMilestone: false))
        }

        // Прогресс: стартовый бонус, DIS, спад, вехи.
        let bonus = grants.filter { $0.sourceType == .onboardingBonus }
        if let first = bonus.first {
            items.append(ChronicleItem(id: "bonus", at: first.createdAt, category: .progress, title: "Стартовый бонус профессий",
                                       detail: "+1 уровень основному атрибуту каждой профессии", changes: changes(first.sourceId),
                                       isCancelled: false, note: nil, isMilestone: false))
        }
        for grant in grants where grant.sourceType == .weeklyDiscipline {
            items.append(ChronicleItem(id: "dis:\(grant.id)", at: grant.createdAt, category: .progress, title: "DIS за неделю",
                                       detail: grant.reason.isEmpty ? nil : grant.reason, changes: [.xp(label: "DIS", amount: grant.amount)],
                                       isCancelled: false, note: nil, isMilestone: false))
        }
        let today = LocalDate(now, timeZone: timeZone)
        let progress = HeroProgress(grants: grants, classAttributes: ClassRules.classAttributes(of: professions), today: today)
        let decay = DecayRun.runs(progress.attributeStates.values.flatMap(\.decay))
        for run in decay {
            let title = run.days > 1 ? "Спад \(run.attribute.code) −2% в день · \(run.days) дн." : "Спад \(run.attribute.code) −2%"
            var detail = "\(run.daysWithoutXPAtEnd) дн. без практики"
            if run.reachedFloor { detail += " · граница 70% пика" }
            items.append(ChronicleItem(id: "decay:\(run.attribute.code):\(run.firstDate)",
                                       at: VitalsCalculator.date(run.lastDate, LocalTime(hour: 0, minute: 0)!, timeZone: timeZone),
                                       category: .progress, title: title, detail: detail,
                                       changes: [.xp(label: run.attribute.code, amount: run.amount)], isCancelled: false, note: nil, isMilestone: false))
        }
        for entry in try await store.chronicleEntries() {
            var note: String?
            if entry.cancelledAt != nil { note = "Снято отменой" }
            if let version = entry.recalculatedBy { note = "Пересчитано по правилам v\(version.rawValue)" }
            items.append(ChronicleItem(id: "milestone:\(entry.id)", at: entry.occurredAt,
                                       category: entry.kind == .epicCompleted ? .quests : .progress, title: entry.title,
                                       detail: entry.kind == .epicCompleted ? "веха" : nil, changes: [],
                                       isCancelled: !entry.isActive, note: note, isMilestone: true))
        }

        let byDay = Dictionary(grouping: items.filter { $0.at <= now }) { LocalDate($0.at, timeZone: timeZone) }
        return byDay.keys.sorted(by: >).map { date in
            ChronicleDay(date: date, items: byDay[date]!.sorted { ($0.at, $0.isMilestone ? 1 : 0) > ($1.at, $1.isMilestone ? 1 : 0) })
        }
    }

    static func sourceTitle(_ source: SleepSource) -> String {
        switch source {
        case .health: "Apple Health"
        case .manual: "вручную"
        case .corrected: "исправлено"
        }
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) мин" }
        return rest == 0 ? "\(hours) ч" : "\(hours) ч \(rest) мин"
    }
}

private extension LocalDate {
    static let distant = LocalDate(year: 9999, month: 1, day: 1)
}
