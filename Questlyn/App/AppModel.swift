import Foundation
import UIKit
import WidgetKit
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
    private let backups: BackupManager?
    private var timeZone: TimeZone { .current }

    init(store: any QuestlynStore, backups: BackupManager? = nil) {
        self.store = store
        self.backups = backups
    }

    // MARK: Резервная копия и экспорт — этап 7

    private(set) var backupFiles: [BackupFile] = []
    private(set) var backupLocation: BackupLocation?
    private(set) var isBackingUp = false

    /// Автокопия раз в сутки и список копий — в фоне, iCloud может отвечать медленно.
    func refreshBackups(createIfNeeded: Bool) async {
        guard let backups else { return }
        let result = await Task.detached(priority: .utility) { () -> ([BackupFile], BackupLocation?) in
            if createIfNeeded { backups.backupIfNeeded(now: .now) }
            guard let (folder, location) = BackupManager.folder() else { return ([], nil) }
            return (BackupManager.list(in: folder), location)
        }.value
        backupFiles = result.0
        backupLocation = result.1
    }

    func backupNow() async {
        guard let backups else { return }
        isBackingUp = true
        defer { isBackingUp = false }
        await run { [self] in
            try await Task.detached(priority: .userInitiated) { _ = try backups.backup(now: .now) }.value
            await refreshBackups(createIfNeeded: false)
        }
    }

    func restore(_ file: BackupFile) async -> Bool {
        guard let backups else { return false }
        return await run { [self] in
            try await Task.detached(priority: .userInitiated) { try backups.restore(file) }.value
            chronicle = []
            await reload()
        }
    }

    /// Файл экспорта во временной папке — для системного меню «Поделиться».
    func exportFile() async -> URL? {
        var url: URL?
        await run { [self] in
            let data = try await ExportService(store: store).json(now: .now)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let file = FileManager.default.temporaryDirectory.appending(path: "questlyn-export-\(formatter.string(from: .now)).json")
            try data.write(to: file, options: .atomic)
            url = file
        }
        return url
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
    var todayBenefits: [BenefitEntry] { overview?.todayBenefits ?? [] }

    func deleteBenefit(_ id: UUID) async {
        await run { [self] in
            try await WellbeingService(store: store).deleteBenefit(id: id, now: .now)
            await reload()
        }
    }
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
    private(set) var deviceCalendars: [DeviceCalendar] = []
    private(set) var calendarPreferences = CalendarPreferences.load()

    /// Повестка недели или месяца (8.13–8.14): события периода без скрытых календарей.
    func loadAgenda(from first: LocalDate, through last: LocalDate) {
        isCalendarAuthorized = calendar.isAuthorized
        deviceCalendars = calendar.calendars()
        let start = VitalsCalculator.date(first, LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
        let end = VitalsCalculator.date(last.adding(days: 1), LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
        agendaEvents = calendar.events(from: start, to: end, hidden: calendarPreferences.hidden)
        #if DEBUG
        // `-QuestlynSampleEvents YES` — события каждого дня для «Пути» в симуляторе.
        if UserDefaults.standard.bool(forKey: "QuestlynSampleEvents") {
            var day = first
            while day <= last {
                func at(_ h: Int, _ m: Int) -> Date { VitalsCalculator.date(day, LocalTime(hour: h, minute: m)!, timeZone: timeZone) }
                agendaEvents += [
                    AgendaEvent(id: "s1\(day)", title: "Стендап", start: at(9, 0), end: at(9, 15), isAllDay: false, calendarId: "", calendarTitle: "", attendees: 2),
                    AgendaEvent(id: "s2\(day)", title: "Встреча", start: at(11, 0), end: at(12, 30), isAllDay: false, calendarId: "", calendarTitle: "", attendees: 2),
                    AgendaEvent(id: "s3\(day)", title: "Созвон", start: at(15, 30), end: at(16, 30), isAllDay: false, calendarId: "", calendarTitle: "", attendees: 3),
                ]
                day = day.adding(days: 1)
            }
        }
        #endif
    }

    func connectCalendar() async {
        await run { [self] in
            _ = try await calendar.requestAccess()
            deviceCalendars = calendar.calendars()
            isCalendarAuthorized = calendar.isAuthorized
        }
    }

    func updateCalendarPreferences(_ change: (inout CalendarPreferences) -> Void) {
        let wasSending = calendarPreferences.sendQuests
        change(&calendarPreferences)
        if wasSending, !calendarPreferences.sendQuests {
            try? calendar.removeAll(mapping: calendarPreferences.questEvents)
            calendarPreferences.questEvents = [:]
        }
        calendarPreferences.save()
        if calendarPreferences.sendQuests { syncQuestEvents() }
    }

    /// Цвет и подпись события по привязке календаря (только оформление, XP не даёт).
    func calendarLink(for event: AgendaEvent) -> (color: UInt32, label: String)? {
        guard let link = calendarPreferences.links[event.calendarId] else { return nil }
        let skill = link.skillId.flatMap { skill(id: $0) }
        let profession = profession(id: skill?.professionId ?? link.professionId)
        guard let profession else { return nil }
        let label = skill.map { "\(profession.title) · навык «\($0.title)»" } ?? profession.title
        return (HeroAccent.hex(catalogItemId: profession.catalogItemId), label)
    }

    func calendarColor(_ id: String) -> UInt32 { deviceCalendars.first { $0.id == id }?.color ?? 0x8E8576 }

    /// Квесты с датой → календарь «Questlyn» (8.15). Ошибка доступа не мешает работе приложения.
    func syncQuestEvents() {
        guard calendarPreferences.sendQuests, calendar.isAuthorized else { return }
        let quests = (overview?.journal ?? []).compactMap { item -> CalendarSource.QuestEvent? in
            guard let date = item.quest.dueDate else { return nil }
            return .init(id: item.quest.id, title: item.quest.title, date: date, time: item.quest.dueTime, isDone: item.isCompleted,
                         minutes: item.quest.durationMinutes ?? QuestTiming.defaultDuration)
        }
        if let mapping = try? calendar.sync(quests: quests, mapping: calendarPreferences.questEvents, timeZone: timeZone) {
            calendarPreferences.questEvents = mapping
            calendarPreferences.save()
        }
    }

    // MARK: Карта дня — этап 6B

    /// День на карте: события календаря, квесты с датой, отметки настроения; герой — только сегодня.
    func dayMap(for date: LocalDate) -> DayMap {
        let start = VitalsCalculator.date(date, LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
        let end = VitalsCalculator.date(date.adding(days: 1), LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
        var events = calendar.events(from: start, to: end, hidden: calendarPreferences.hidden).map {
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
                     isDone: item.isCompleted, durationMinutes: QuestTiming.effectiveDuration(item.quest),
                     isOverdue: QuestTiming.ghostSince(item.quest, isCompleted: item.isCompleted, now: .now, timeZone: timeZone) != nil)
        }
        return DayMapBuilder.build(date: date, events: events, quests: quests, moods: overview?.moods ?? [], now: .now, timeZone: timeZone)
    }

    /// Неделя на карте (02 от 11.11.2026): семь дней с понедельника и привалы сна.
    func weekMap(start: LocalDate) -> WeekMap {
        let days = (0..<7).map { dayMap(for: start.adding(days: $0)) }
        let camps = SleepCampBuilder.camps(from: vitals?.log ?? [], window: vitalSettings.sleepWindow, timeZone: timeZone)
        return WeekMap.build(weekStart: start, days: days, camps: camps, now: .now, timeZone: timeZone)
    }

    // MARK: Виджеты — этап 12

    /// Снимок для виджетов в App Group: виджеты только читают его (02, 12.11.2026).
    func writeWidgetSnapshot() {
        guard let hero, let overview, let vitals else { return }
        let day = today
        let ghostItems = ghosts
        let quests = overview.items.filter { $0.section == .today && !$0.isCompleted }
            .sorted { ($0.quest.dueTime?.description ?? "99") < ($1.quest.dueTime?.description ?? "99") }
            .map { WidgetSnapshot.Quest(title: $0.quest.title, time: $0.quest.dueTime?.description,
                                        minutes: QuestTiming.effectiveDuration($0.quest), isGhost: false) }
        let habits = self.habits.filter(\.isScheduledToday).map { status in
            WidgetSnapshot.Habit(id: status.id.uuidString, title: status.habit.title, isWeekly: status.habit.kind == .weekly,
                                 doneToday: status.doneToday, weekDone: status.weekDone, weekPlanned: status.weekPlanned,
                                 marks: day.weekDays.map { status.marks(on: $0) > 0 })
        }
        var sleep: WidgetSnapshot.Sleep?
        if let night = vitals.lastNight, let session = night.session {
            let camp = SleepCampBuilder.camps(from: vitals.log, window: vitalSettings.sleepWindow, timeZone: timeZone).last { $0.wakeDate == day }
            let interval = camp.map { "\($0.start.formatted(date: .omitted, time: .shortened))–\($0.end.formatted(date: .omitted, time: .shortened))" }
            sleep = .init(interval: interval, duration: WeekMapRenderer.duration(session.durationMinutes),
                          quality: Int((night.quality * 100).rounded()), hpRestored: Int((night.hpAfter - night.hpBefore).rounded()))
        }
        let snapshot = WidgetSnapshot(
            generatedAt: .now, day: Format.shortDay(day), heroName: hero.name, rankLetter: progress.rank?.letter ?? "—",
            hp: Int(vitals.hp.rounded()), maxHP: Int(vitals.maxHP.rounded()), mp: Int(vitals.mp.rounded()), maxMP: Int(vitals.maxMP.rounded()),
            mode: movementMode(at: .now).title, quests: quests, ghosts: ghostItems.map(\.title), habits: habits, sleep: sleep)
        let map = PixelMapRenderer.strip(dayMap(for: day), appearance: hero.appearance, accent: heroAccent,
                                         farm: farmHours(on: day), aura: auraTier).flatMap { UIImage(cgImage: $0).pngData() }
        try? snapshot.save(map: map)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Ритм дня — этап 9

    private static let workScheduleKey = "workSchedule"
    /// «Фарм» — рабочее время на этом устройстве (9.3); только отображение.
    var workSchedule: WorkSchedule = {
        #if DEBUG
        // `-QuestlynWorkDemo YES` — «Фарм» 9–18 по будням для проверки в симуляторе.
        if UserDefaults.standard.bool(forKey: "QuestlynWorkDemo") { return WorkSchedule(isEnabled: true) }
        #endif
        guard let data = UserDefaults.standard.data(forKey: "workSchedule"),
              let value = try? JSONDecoder().decode(WorkSchedule.self, from: data) else { return .default }
        return value
    }() {
        didSet { if let data = try? JSONEncoder().encode(workSchedule) { UserDefaults.standard.set(data, forKey: Self.workScheduleKey) } }
    }

    /// «Фарм» дня в часах от полуночи — для дороги на картах.
    func farmHours(on day: LocalDate) -> ClosedRange<Double>? {
        guard let interval = workSchedule.interval(on: day, timeZone: timeZone) else { return nil }
        let start = VitalsCalculator.date(day, LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
        return interval.start.timeIntervalSince(start) / 3600...interval.end.timeIntervalSince(start) / 3600
    }

    /// Призраки просроченных задач (9.6): один квест — один призрак, с момента просрочки.
    var ghosts: [(id: UUID, title: String, since: Date)] {
        (overview?.journal ?? []).compactMap { item in
            QuestTiming.ghostSince(item.quest, isCompleted: item.isCompleted, now: .now, timeZone: timeZone).map { (item.quest.id, item.quest.title, $0) }
        }
        .sorted { $0.since < $1.since }
    }

    /// Вид движения героя в момент.
    func movementMode(at moment: Date) -> MovementMode {
        MovementMode.at(moment, sleepWindow: vitalSettings.sleepWindow, work: workSchedule, timeZone: timeZone)
    }

    // MARK: Побродить — этап 8B

    /// Данные острова за диапазон прошлых дат: события, квесты, ночи, настроение недель.
    func exploreInput(first: LocalDate, last: LocalDate) -> ExploreInput {
        let from = VitalsCalculator.date(first, LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
        let to = VitalsCalculator.date(last.adding(days: 1), LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
        var events = calendar.exploreEvents(from: from, to: to, hidden: calendarPreferences.hidden)
        #if DEBUG
        // `-QuestlynSampleEvents YES` — повторяющиеся события с участниками, чтобы проверить остров в симуляторе.
        if UserDefaults.standard.bool(forKey: "QuestlynSampleEvents") {
            let titles = ["Стендап", "Планёрка", "Тренировка", "Созвон с командой", "Обед", "Ретро", "Кино", "Встреча с Петей"]
            var day = first
            var index = 0
            while day <= last {
                for slot in 0..<3 {
                    let title = titles[(index + slot * 3) % titles.count] + (index % 11 == 0 ? " \(index)" : "")
                    let keys = (0..<((index + slot) % 4)).map { "p\(($0 * 7 + index) % 24)" }
                    events.append(ExploreEvent(title: title, start: VitalsCalculator.date(day, LocalTime(hour: 9 + slot * 3, minute: 0)!, timeZone: timeZone),
                                               minutes: 45, attendeeKeys: keys))
                }
                index += 1
                day = day.adding(days: 1)
            }
        }
        #endif
        let quests = (overview?.journal ?? []).filter { item in
            let date = item.completion?.localDate ?? item.quest.dueDate
            return date.map { $0 >= first && $0 <= last } ?? false
        }.map { (title: $0.quest.title, priority: $0.quest.priority) }
        var nights: [LocalDate: Double] = [:]
        for entry in vitals?.log ?? [] {
            if case let .night(night) = entry.kind, night.wakeDate >= first, night.wakeDate <= last { nights[night.wakeDate] = night.quality }
        }
        var weekMoods: [LocalDate: Mood] = [:]
        for mood in (overview?.moods ?? []).sorted(by: { $0.at < $1.at }) where mood.localDate >= first && mood.localDate <= last {
            weekMoods[mood.localDate.weekStart] = mood.mood
        }
        return ExploreInput(first: first, last: last, events: events, quests: quests, nights: nights, weekMoods: weekMoods,
                            hasCalendar: calendar.isAuthorized || !events.isEmpty)
    }

    /// Навыки, которые можно взять в дорогу: способность по виду активности или атрибуту профессии, сила — по XP.
    var exploreSkills: [ExploreSkill] {
        skills.filter(\.isActive).compactMap { skill in
            let main = profession(id: skill.professionId)?.attributes.first
            guard let ability = ExploreAbility.of(activityTemplateId: skill.activityTemplateId, professionMain: main) else { return nil }
            let xp = Double((progress.skillXP[skill.id] ?? .zero).value) / 100
            return ExploreSkill(id: skill.id, title: skill.title, ability: ability, skillXP: xp)
        }
    }

    func exploreHero(skills chosen: [ExploreSkill]) -> ExploreHero {
        let state = vitals
        return ExploreHero(levels: progress.levels, hp: state?.hp ?? 100, maxHP: state?.maxHP ?? 100, mp: state?.mp ?? 100,
                           maxMP: state?.maxMP ?? 100, rankLetter: progress.rank?.letter ?? "—", skills: chosen)
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

    /// Исправление одной из последних 7 ночей точным интервалом (8.1).
    func correctSleep(wakeDate: LocalDate, startedAt: Date, endedAt: Date) async -> Bool {
        await run { [self] in
            try await SleepService(store: store).correct(wakeDate: wakeDate, startedAt: startedAt, endedAt: endedAt, now: .now, timeZone: timeZone)
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
            syncQuestEvents()
            // Вехи фиксируются при каждом обновлении — в момент, когда они случились.
            try await ChronicleService(store: store).syncMilestones(now: .now, timeZone: timeZone)
            if !chronicle.isEmpty { chronicle = try await ChronicleService(store: store).feed(now: .now, timeZone: timeZone) }
        }
        isLoaded = true
        writeWidgetSnapshot()
    }

    func startAdventure(name: String, appearance: HeroAppearance, professions: [ProfessionChoice], classTitle: String) async -> Bool {
        await run { [self] in
            try await OnboardingService(store: store).start(heroName: name, appearance: appearance, professions: professions,
                                                            classTitle: classTitle, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    /// Цвет акцента одежды героя — по основной профессии (слот 1).
    /// Цвет основной профессии — акцент по умолчанию.
    var professionAccent: UInt32 { HeroAccent.hex(catalogItemId: activeProfessions.min { $0.slot < $1.slot }?.catalogItemId) }
    /// Акцент героя: свой выбор (10.2) или цвет основной профессии.
    var heroAccent: UInt32 { hero?.appearance.accent ?? professionAccent }
    /// Ступень ауры по текущему рангу (10.3).
    var auraTier: Int {
        #if DEBUG
        if let value = UserDefaults.standard.object(forKey: "QuestlynAura") as? String, let tier = Int(value) { return tier }
        #endif
        return AuraTier.of(progress.rank)
    }

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

    func renameSkill(_ skillId: UUID, title: String) async -> Bool {
        await run { [self] in
            try await SkillService(store: store).rename(skillId: skillId, title: title)
            await reload()
        }
    }

    func deleteSkill(_ skillId: UUID) async -> Bool {
        await run { [self] in
            try await SkillService(store: store).delete(skillId: skillId, now: .now)
            await reload()
        }
    }

    /// Привязка навыка к виду активности, один к одному (8.6). nil — убрать.
    func linkActivity(templateId: String?, skillId: UUID) async {
        await run { [self] in
            try await SkillService(store: store).linkActivity(templateId: templateId, skillId: skillId)
            await reload()
        }
    }

    /// Навык, привязанный к виду активности.
    func linkedSkill(templateId: String) -> Skill? { skills.first { $0.activityTemplateId == templateId && $0.isActive } }

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

    /// Снять конкретную отметку недельного квеста текущей недели (8.5).
    func unmarkWeekly(occurrenceId: UUID) async {
        await run { [self] in
            try await HabitMarkService(store: store).unmarkWeekly(occurrenceId: occurrenceId, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    /// Отметки недельного квеста за текущую неделю — для списка «Отметки недели».
    func weekOccurrences(habitId: UUID) async -> [HabitOccurrence] {
        let today = LocalDate(.now, timeZone: timeZone)
        let all = (try? await store.occurrences(from: today.weekStart, through: today)) ?? []
        return all.filter { $0.habitId == habitId }.sorted { $0.completedAt < $1.completedAt }
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

    func createEpic(title: String, details: String, deadline: LocalDate?, steps: [QuestDraft], professionId: UUID?) async -> Bool {
        await run { [self] in
            try await EpicService(store: store).create(title: title, details: details, deadline: deadline, steps: steps,
                                                       professionId: professionId, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    func updateEpic(_ epicId: UUID, title: String, details: String, deadline: LocalDate?, steps: [EpicService.StepEdit],
                    professionId: UUID?) async -> Bool {
        await run { [self] in
            try await EpicService(store: store).update(epicId: epicId, title: title, details: details, deadline: deadline,
                                                       steps: steps, professionId: professionId, now: .now, timeZone: timeZone)
            await reload()
        }
    }

    func deleteEpic(_ epicId: UUID) async -> Bool {
        await run { [self] in
            try await EpicService(store: store).delete(epicId: epicId, now: .now)
            await reload()
        }
    }

    func archiveHabit(_ habitId: UUID) async -> Bool {
        await run { [self] in
            try await HabitService(store: store).archive(habitId: habitId, now: .now, timeZone: timeZone)
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
