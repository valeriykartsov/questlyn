import Foundation
import Observation
import Domain
import Application

/// Состояние приложения для Presentation. Все изменения идут через use cases Application.
@Observable
final class AppModel {
    private(set) var overview: TodayOverview?
    private(set) var isLoaded = false
    var errorMessage: String?

    private let store: any QuestlynStore
    private var timeZone: TimeZone { .current }

    init(store: any QuestlynStore) {
        self.store = store
    }

    var hero: Hero? { overview?.hero }
    var progress: HeroProgress { overview?.progress ?? HeroProgress(grants: [], classAttributes: []) }
    var activeProfessions: [Profession] { overview?.professions.filter(\.isActive) ?? [] }
    var skills: [Skill] { overview?.skills ?? [] }

    func skill(id: UUID?) -> Skill? { skills.first { $0.id == id } }
    func profession(id: UUID?) -> Profession? { overview?.professions.first { $0.id == id } }

    // MARK: Настроение и календарь — этап 6

    var weather: Weather { overview?.weather ?? .clear }
    var todayHarms: [HarmEntry] { overview?.todayHarms ?? [] }
    var lastMood: MoodEntry? { overview?.lastMood }

    private let moodSink = StateOfMindSink()
    private static let stateOfMindKey = "stateOfMindWrite"
    /// Писать отметки настроения в Apple Health.
    var writesStateOfMind: Bool {
        get { access(keyPath: \.writesStateOfMind); return UserDefaults.standard.bool(forKey: Self.stateOfMindKey) }
        set { withMutation(keyPath: \.writesStateOfMind) { UserDefaults.standard.set(newValue, forKey: Self.stateOfMindKey) } }
    }

    func enableStateOfMind() async {
        await run { [self] in
            try await moodSink.requestAuthorization()
            writesStateOfMind = true
        }
    }

    func checkIn(_ draft: CheckInDraft) async -> Bool {
        await run { [self] in
            let report = try await WellbeingService(store: store).checkIn(draft, now: .now, timeZone: timeZone)
            if writesStateOfMind, let mood = report.mood {
                // Сбой записи в Apple Health не отменяет отметку в приложении.
                try? await moodSink.write(mood)
            }
            await reload()
        }
    }

    func deleteHarm(_ id: UUID) async {
        await run { [self] in
            try await WellbeingService(store: store).deleteHarm(id: id, now: .now)
            await reload()
        }
    }

    func createHarmHabit(title: String, percent: Int) async -> Bool {
        await run { [self] in
            try await WellbeingService(store: store).createHabit(title: title, damagePercent: percent, now: .now)
            await reload()
        }
    }

    func archiveHarmHabit(_ id: UUID) async {
        await run { [self] in
            try await WellbeingService(store: store).archiveHabit(id: id)
            await reload()
        }
    }

    let calendar = CalendarSource()
    private(set) var agendaEvents: [AgendaEvent] = []
    private(set) var isCalendarAuthorized = false

    /// Повестка: 7 дней назад и 14 вперёд (02 от 11.11.2026).
    static let agendaDaysBack = 7
    static let agendaDaysForward = 14

    func loadAgenda() {
        isCalendarAuthorized = calendar.isAuthorized
        let start = VitalsCalculator.date(today.adding(days: -Self.agendaDaysBack), LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
        let end = VitalsCalculator.date(today.adding(days: Self.agendaDaysForward + 1), LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
        agendaEvents = calendar.events(from: start, to: end)
    }

    func connectCalendar() async {
        await run { [self] in
            _ = try await calendar.requestAccess()
            loadAgenda()
        }
    }

    // MARK: Карта дня — этап 6B

    /// День на карте: события календаря, квесты с датой, отметки настроения; герой — только сегодня.
    func dayMap(for date: LocalDate) -> DayMap {
        let start = VitalsCalculator.date(date, LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
        let end = VitalsCalculator.date(date.adding(days: 1), LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
        var events = calendar.events(from: start, to: end).map {
            MapEvent(id: $0.id, title: $0.title, start: $0.start, end: $0.end, isAllDay: $0.isAllDay, attendees: $0.attendees)
        }
        #if DEBUG
        // `-QuestlynSampleEvents YES` — события как в макете 3.5, чтобы проверить карту в симуляторе без календаря.
        if UserDefaults.standard.bool(forKey: "QuestlynSampleEvents") {
            func at(_ h: Int, _ m: Int) -> Date { VitalsCalculator.date(date, LocalTime(hour: h, minute: m)!, timeZone: timeZone) }
            events += [
                MapEvent(id: "s1", title: "Стендап", start: at(9, 0), end: at(9, 15), isAllDay: false, attendees: 2),
                MapEvent(id: "s2", title: "Встреча", start: at(11, 0), end: at(12, 30), isAllDay: false, attendees: 2),
                MapEvent(id: "s3", title: "Обед", start: at(13, 0), end: at(13, 30), isAllDay: false, attendees: 1),
                MapEvent(id: "s4", title: "Отчёт", start: at(15, 0), end: at(16, 0), isAllDay: false, attendees: 0),
                MapEvent(id: "s5", title: "Созвон", start: at(15, 30), end: at(16, 30), isAllDay: false, attendees: 3),
                MapEvent(id: "s6", title: "Тренировка", start: at(19, 0), end: at(20, 0), isAllDay: false, attendees: 0),
                MapEvent(id: "s7", title: "День рождения Пети", start: at(0, 0), end: at(23, 59), isAllDay: true, attendees: 0),
            ]
        }
        #endif
        let quests = (overview?.journal ?? []).filter { $0.quest.dueDate == date }.map { item in
            MapQuest(title: item.quest.title, start: item.quest.dueTime.map { VitalsCalculator.date(date, $0, timeZone: timeZone) },
                     isDone: item.isCompleted)
        }
        return DayMapBuilder.build(date: date, events: events, quests: quests, moods: overview?.moods ?? [], now: .now, timeZone: timeZone)
    }

    // MARK: Летопись — этап 5

    private(set) var chronicle: [ChronicleDay] = []

    func loadChronicle() async {
        await run { [self] in
            chronicle = try await ChronicleService(store: store).feed(now: .now, timeZone: timeZone)
        }
    }

    // MARK: Состояние героя — этап 4

    var vitals: VitalsState? { overview?.vitals }
    var vitalSettings: VitalSettings { overview?.vitalSettings ?? .default }

    private let health = HealthKitSource()
    private static let healthConnectedKey = "healthConnected"
    /// Пользователь подключал Apple Health — синхронизируем при каждом обновлении.
    var isHealthConnected: Bool {
        get { access(keyPath: \.isHealthConnected); return UserDefaults.standard.bool(forKey: Self.healthConnectedKey) }
        set { withMutation(keyPath: \.isHealthConnected) { UserDefaults.standard.set(newValue, forKey: Self.healthConnectedKey) } }
    }
    var isHealthAvailable: Bool { health.isAvailable }

    /// Пора спросить «Как спали?»: окно сна закончилось, ночь не внесена.
    var needsSleepAnswer: Bool {
        guard hero != nil, let overview, !overview.hasSleepToday else { return false }
        return Date.now >= VitalsCalculator.date(overview.date, overview.vitalSettings.sleepWindow.end, timeZone: timeZone)
    }

    func connectHealth() async {
        await run { [self] in
            try await health.requestAuthorization()
            isHealthConnected = true
            try await HealthSyncService(store: store, source: health).sync(now: .now, timeZone: timeZone)
            await reload()
        }
    }

    func recordSleep(duration: ManualSleepDuration, bedtime: ManualBedtime) async -> Bool {
        await run { [self] in
            try await SleepService(store: store).recordManual(duration: duration, bedtime: bedtime, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    func updateVitalSettings(_ settings: VitalSettings) async -> Bool {
        await run { [self] in
            try await VitalsService(store: store).updateSettings(settings)
            await reload()
        }
    }

    func reload() async {
        await run { [self] in
            if isHealthConnected, hero != nil || overview == nil {
                // Ошибка Apple Health не мешает открыть приложение: данные просто не обновятся.
                try? await HealthSyncService(store: store, source: health).sync(now: .now, timeZone: timeZone)
            }
            overview = try await TodayService(store: store).overview(now: .now, timeZone: timeZone)
            // Вехи фиксируются при каждом обновлении — в момент, когда они случились.
            try await ChronicleService(store: store).syncMilestones(now: .now, timeZone: timeZone)
            if !chronicle.isEmpty { chronicle = try await ChronicleService(store: store).feed(now: .now, timeZone: timeZone) }
        }
        isLoaded = true
    }

    func startAdventure(name: String, appearance: HeroAppearance, professions: [ProfessionChoice], classTitle: String) async -> Bool {
        await run { [self] in
            try await OnboardingService(store: store).start(heroName: name, appearance: appearance, professions: professions,
                                                            classTitle: classTitle, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    /// Цвет акцента одежды героя — по основной профессии (слот 1).
    var heroAccent: UInt32 { HeroAccent.hex(catalogItemId: activeProfessions.min { $0.slot < $1.slot }?.catalogItemId) }

    func updateAppearance(_ appearance: HeroAppearance) async -> Bool {
        await run { [self] in
            try await HeroService(store: store).updateAppearance(appearance)
            await reload()
        }
    }

    func updateProfessions(_ professions: [ProfessionChoice], classTitle: String) async -> Bool {
        await run { [self] in
            try await ProfessionService(store: store).update(professions: professions, classTitle: classTitle, now: .now)
            await reload()
        }
    }

    func createSkill(title: String, professionId: UUID, mastery: Int? = nil) async -> Skill? {
        var created: Skill?
        await run { [self] in
            created = try await SkillService(store: store).create(title: title, professionId: professionId, mastery: mastery, now: .now)
            await reload()
        }
        return created
    }

    func assessMastery(skillId: UUID, value: Int) async {
        await run { [self] in
            try await SkillService(store: store).assess(skillId: skillId, mastery: value, now: .now)
            await reload()
        }
    }

    func mastery(skillId: UUID) -> Int? { overview?.masteries[skillId] }

    func createQuest(_ draft: QuestDraft) async -> Bool {
        await run { [self] in
            try await QuestService(store: store).create(draft, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    func complete(questId: UUID) async -> CompletionReport? {
        var report: CompletionReport?
        await run { [self] in
            report = try await CompletionService(store: store).complete(questId: questId, now: .now, timeZone: timeZone)
            await reload()
        }
        return report
    }

    func updateQuest(_ questId: UUID, with draft: QuestDraft) async -> Bool {
        await run { [self] in
            try await QuestService(store: store).update(questId: questId, with: draft)
            await reload()
        }
    }

    // MARK: Привычки

    var today: LocalDate { overview?.date ?? LocalDate(.now, timeZone: timeZone) }
    var habits: [HabitStatus] { overview?.habits ?? [] }
    func habit(id: UUID) -> HabitStatus? { habits.first { $0.id == id } }

    func createHabit(_ draft: HabitDraft) async -> Bool {
        await run { [self] in
            try await HabitService(store: store).create(draft, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    func updateHabit(_ habitId: UUID, with draft: HabitDraft) async -> Bool {
        await run { [self] in
            try await HabitService(store: store).update(habitId: habitId, with: draft)
            await reload()
        }
    }

    func markHabit(_ habitId: UUID, on date: LocalDate) async {
        await run { [self] in
            try await HabitMarkService(store: store).mark(habitId: habitId, on: date, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    func unmarkHabit(_ habitId: UUID, on date: LocalDate) async {
        await run { [self] in
            try await HabitMarkService(store: store).unmark(habitId: habitId, on: date, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    // MARK: Activity

    var activities: [Activity] { overview?.activities ?? [] }

    func recordActivity(_ draft: ActivityDraft) async -> ActivityReport? {
        var report: ActivityReport?
        await run { [self] in
            report = try await ActivityService(store: store).record(draft, now: .now, timeZone: timeZone)
            await reload()
        }
        return report
    }

    func deleteActivity(_ id: UUID) async {
        await run { [self] in
            try await ActivityService(store: store).delete(activityId: id, now: .now)
            await reload()
        }
    }

    func complete(questId: UUID, with draft: ActivityDraft) async -> CompletionReport? {
        var report: CompletionReport?
        await run { [self] in
            report = try await CompletionService(store: store).complete(questId: questId, with: draft, now: .now, timeZone: timeZone)
            await reload()
        }
        return report
    }

    /// Предпросмотр начислений Activity по тем же правилам, с учётом предела дня (только для сегодняшних записей).
    func previewActivity(_ draft: ActivityDraft) -> (credited: Int, grants: [ProgressGrant]) {
        guard let template = ActivityTemplate.template(id: draft.templateId) else { return (0, []) }
        let date = LocalDate(draft.startedAt, timeZone: timeZone)
        let already = date == today ? activities.filter { $0.templateId == template.id }.reduce(0) { $0 + $1.creditedMinutes } : 0
        let credited = ActivityRules.creditedMinutes(duration: draft.durationMinutes, alreadyCreditedToday: already)
        let skill = skill(id: draft.skillId)
        let profession = profession(id: skill?.professionId)
        let snapshot = profession.map { ClassRules.snapshot(skillProfession: $0, activeProfessions: activeProfessions) } ?? .empty
        let grants = GrantCalculator.activityGrants(activityId: UUID(), template: template, creditedMinutes: credited, skill: skill,
                                                    skillProfessionTitle: profession?.title, snapshot: snapshot, createdAt: .now, effectiveDate: date)
        return (credited, grants)
    }

    /// «Бег +6,67 · STR +3,33 · …»
    func grantSummary(_ grants: [ProgressGrant]) -> String {
        grants.map { grant in
            switch grant.target {
            case .attribute(let a): "\(a.code) \(Format.signedXP(grant.amount))"
            case .skill(let id): "«\(skill(id: id)?.title ?? "Навык")» \(Format.signedXP(grant.amount))"
            }
        }
        .joined(separator: " · ")
    }

    // MARK: Сброс

    /// Удалить всё и вернуться к онбордингу.
    func resetEverything(confirmation: String) async -> Bool {
        await run { [self] in
            try await ResetService(store: store).resetEverything(confirmation: confirmation)
            await reload()
        }
    }

    // MARK: Epic

    var epics: [EpicStatus] { overview?.epics ?? [] }
    func epic(id: UUID?) -> EpicStatus? { epics.first { $0.id == id } }

    func createEpic(title: String, details: String, deadline: LocalDate?, steps: [QuestDraft]) async -> Bool {
        await run { [self] in
            try await EpicService(store: store).create(title: title, details: details, deadline: deadline, steps: steps, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    func completeEpic(_ epicId: UUID) async {
        await run { [self] in
            try await EpicService(store: store).complete(epicId: epicId, now: .now)
            await reload()
        }
    }

    func reopenEpic(_ epicId: UUID) async {
        await run { [self] in
            try await EpicService(store: store).reopen(epicId: epicId)
            await reload()
        }
    }

    /// Квест из журнала (любой, не только на сегодня).
    func questItem(id: UUID) -> TodayItem? { overview?.journal.first { $0.quest.id == id } }

    func undo(questId: UUID) async {
        await run { [self] in
            try await CompletionService(store: store).undo(questId: questId, now: .now)
            await reload()
        }
    }

    @discardableResult
    private func run(_ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            return true
        } catch let error as QuestlynError {
            errorMessage = error.description
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }
}
