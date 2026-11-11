import WidgetKit
import SwiftUI
import AppIntents
import Domain

// Виджеты Questlyn (этап 12, макет Widgets): только показывают данные из снимка, который пишет приложение.
// Касание открывает приложение. Отметок с виджета нет (02, 11.11.2026).

@main
struct QuestlynWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        HeroWidget()
        SleepWidget()
        MapWidget()
        HabitWidget()
        VitalsLockWidget()
        NextQuestLockWidget()
        SleepLockWidget()
    }
}

// MARK: - Данные

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var habitId: String?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : (WidgetSnapshot.load() ?? .sample)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load() ?? .sample)
        // Приложение обновляет виджеты само после каждого изменения; запасное обновление — раз в 30 минут.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

enum WidgetPalette {
    static let paper = Color(red: 0xF5 / 255, green: 0xF0 / 255, blue: 0xE6 / 255)
    static let sheet = Color(red: 0xFF / 255, green: 0xFC / 255, blue: 0xF6 / 255)
    static let ink = Color(red: 0x1F / 255, green: 0x2A / 255, blue: 0x44 / 255)
    static let inkSecondary = Color(red: 0x4A / 255, green: 0x53 / 255, blue: 0x68 / 255)
    static let hp = Color(red: 0xA8 / 255, green: 0x43 / 255, blue: 0x2F / 255)
    static let mp = Color(red: 0x3E / 255, green: 0x6F / 255, blue: 0xA3 / 255)
    static let forest = Color(red: 0x2F / 255, green: 0x6B / 255, blue: 0x4F / 255)
    static let amber = Color(red: 0xE2 / 255, green: 0xA0 / 255, blue: 0x4A / 255)
    static let night = Color(red: 0x1E / 255, green: 0x27 / 255, blue: 0x42 / 255)
    static let fire = Color(red: 0xF2 / 255, green: 0xB3 / 255, blue: 0x5B / 255)
    static let track = Color(red: 0xE9 / 255, green: 0xE1 / 255, blue: 0xD0 / 255)
}

struct Meter: View {
    let code: String
    let value: Int
    let max: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(code) \(value)/\(max)").font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(WidgetPalette.track)
                    Capsule().fill(color).frame(width: proxy.size.width * CGFloat(value) / CGFloat(Swift.max(max, 1)))
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - «Сегодня»

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuestlynToday", provider: SnapshotProvider()) { entry in
            TodayWidgetView(snapshot: entry.snapshot)
                .containerBackground(WidgetPalette.sheet, for: .widget)
        }
        .configurationDisplayName("Сегодня")
        .description("Ближайшие квесты, призраки просроченных и привычки дня.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TodayWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let limit = family == .systemLarge ? 8 : 3
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Сегодня").font(.system(size: 15, weight: .bold))
                Spacer()
                Text(snapshot.day).font(.system(size: 11)).foregroundStyle(WidgetPalette.inkSecondary)
            }
            if snapshot.quests.isEmpty {
                Text("Квестов на сегодня нет").font(.system(size: 13)).foregroundStyle(WidgetPalette.inkSecondary)
            }
            ForEach(Array(snapshot.quests.prefix(limit).enumerated()), id: \.offset) { _, quest in
                HStack(spacing: 8) {
                    Text(quest.time ?? "—").font(.system(size: 13, weight: .bold)).monospacedDigit().frame(width: 42, alignment: .leading)
                    Text(quest.title).font(.system(size: 13)).lineLimit(1)
                }
            }
            if let ghost = snapshot.ghosts.first {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(WidgetPalette.hp).frame(width: 42, alignment: .leading).accessibilityHidden(true)
                    Text(snapshot.ghosts.count > 1 ? "\(ghost) и ещё \(snapshot.ghosts.count - 1)" : ghost)
                        .font(.system(size: 13)).foregroundStyle(WidgetPalette.hp).lineLimit(1)
                }
                .accessibilityLabel("Просрочено: \(ghost)")
            }
            Spacer(minLength: 0)
            let done = snapshot.habits.filter(\.doneToday).count
            Text("Привычки \(done) из \(snapshot.habits.count) · квестов \(snapshot.quests.count)")
                .font(.system(size: 11)).foregroundStyle(WidgetPalette.inkSecondary)
        }
        .foregroundStyle(WidgetPalette.ink)
    }
}

// MARK: - «Герой»

struct HeroWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuestlynHero", provider: SnapshotProvider()) { entry in
            let s = entry.snapshot
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(s.heroName).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    Spacer()
                    Text(s.rankLetter).font(.system(size: 11, weight: .heavy))
                        .padding(.horizontal, 6).background(WidgetPalette.amber, in: RoundedRectangle(cornerRadius: 6))
                }
                Meter(code: "HP", value: s.hp, max: s.maxHP, color: WidgetPalette.hp)
                Meter(code: "MP", value: s.mp, max: s.maxMP, color: WidgetPalette.mp)
                Spacer(minLength: 0)
                Text(s.mode).font(.system(size: 11)).foregroundStyle(WidgetPalette.inkSecondary)
            }
            .foregroundStyle(WidgetPalette.ink)
            .containerBackground(WidgetPalette.sheet, for: .widget)
        }
        .configurationDisplayName("Состояние героя")
        .description("HP, MP и ранг героя.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - «Сон»

struct SleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuestlynSleep", provider: SnapshotProvider()) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Text("Сон").font(.system(size: 14, weight: .bold)).foregroundStyle(WidgetPalette.fire)
                if let sleep = entry.snapshot.sleep {
                    Text(sleep.duration).font(.system(size: 22, weight: .bold)).minimumScaleFactor(0.7)
                    if let interval = sleep.interval { Text(interval).font(.system(size: 12)).opacity(0.8) }
                    Spacer(minLength: 0)
                    Text("качество \(sleep.quality)% · +\(sleep.hpRestored) HP").font(.system(size: 11))
                } else {
                    Text("Нет данных о сне").font(.system(size: 13))
                    Spacer(minLength: 0)
                    Text("ночь нейтральная").font(.system(size: 11)).opacity(0.8)
                }
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(WidgetPalette.night, for: .widget)
        }
        .configurationDisplayName("Сон")
        .description("Прошлая ночь: интервал, длительность, качество.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - «Мини-карта»

struct MapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuestlynMap", provider: SnapshotProvider()) { entry in
            ZStack(alignment: .bottomLeading) {
                if let url = WidgetSnapshot.directory?.appendingPathComponent(WidgetSnapshot.mapFileName),
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().interpolation(.none).aspectRatio(contentMode: .fill)
                } else {
                    WidgetPalette.paper
                }
                Text("\(entry.snapshot.rankLetter) · \(entry.snapshot.mode)")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(WidgetPalette.ink)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(WidgetPalette.amber, in: RoundedRectangle(cornerRadius: 7))
                    .padding(8)
            }
            .containerBackground(WidgetPalette.paper, for: .widget)
        }
        .configurationDisplayName("Мини-карта")
        .description("Карта дня: дорога, поселения, герой.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - «Привычка» — выбор через «Изменить виджет»

struct HabitEntity: AppEntity {
    let id: String
    let title: String
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Привычка"
    static let defaultQuery = HabitQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct HabitQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [HabitEntity] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [HabitEntity] { all() }
    private func all() -> [HabitEntity] {
        (WidgetSnapshot.load() ?? .sample).habits.map { HabitEntity(id: $0.id, title: $0.title) }
    }
}

struct SelectHabitIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Привычка"
    static let description = IntentDescription("Какую привычку показывать.")
    @Parameter(title: "Привычка") var habit: HabitEntity?
}

struct HabitProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample) }
    func snapshot(for configuration: SelectHabitIntent, in context: Context) async -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load() ?? .sample, habitId: configuration.habit?.id)
    }
    func timeline(for configuration: SelectHabitIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        Timeline(entries: [SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load() ?? .sample, habitId: configuration.habit?.id)],
                 policy: .after(.now.addingTimeInterval(30 * 60)))
    }
}

struct HabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "QuestlynHabit", intent: SelectHabitIntent.self, provider: HabitProvider()) { entry in
            let habit = entry.snapshot.habits.first { $0.id == entry.habitId } ?? entry.snapshot.habits.first
            VStack(alignment: .leading, spacing: 6) {
                if let habit {
                    Text(habit.title).font(.system(size: 14, weight: .bold)).lineLimit(2)
                    Text(habit.isWeekly ? "недельный · \(habit.weekDone) из \(habit.weekPlanned)" : (habit.doneToday ? "сегодня ✓" : "сегодня — не отмечено"))
                        .font(.system(size: 12)).foregroundStyle(WidgetPalette.inkSecondary)
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        ForEach(Array(habit.marks.enumerated()), id: \.offset) { _, done in
                            Circle().fill(done ? WidgetPalette.forest : WidgetPalette.track).frame(width: 13, height: 13)
                        }
                    }
                    .accessibilityLabel("Отмечено на неделе: \(habit.marks.filter { $0 }.count)")
                } else {
                    Text("Привычек на сегодня нет").font(.system(size: 13))
                }
            }
            .foregroundStyle(WidgetPalette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(WidgetPalette.sheet, for: .widget)
        }
        .configurationDisplayName("Привычка")
        .description("Отметки привычки на этой неделе.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Экран блокировки

struct VitalsLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuestlynLockVitals", provider: SnapshotProvider()) { entry in
            let s = entry.snapshot
            Gauge(value: Double(s.hp), in: 0...Double(max(s.maxHP, 1))) {
                Text("HP")
            } currentValueLabel: {
                Text("\(s.hp)")
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("HP")
        .description("Здоровье героя на экране блокировки.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct NextQuestLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuestlynLockQuest", provider: SnapshotProvider()) { entry in
            let s = entry.snapshot
            VStack(alignment: .leading, spacing: 1) {
                if let quest = s.quests.first {
                    Text("\(quest.time ?? "сегодня") · \(quest.title)").font(.headline).lineLimit(1)
                    Text("ближайший квест" + (quest.minutes.map { " · \($0) мин" } ?? "")).font(.caption)
                } else {
                    Text("Квестов нет").font(.headline)
                }
                Text("HP \(s.hp) · MP \(s.mp)").font(.caption)
            }
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Ближайший квест")
        .description("Ближайший квест, HP и MP.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct SleepLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuestlynLockSleep", provider: SnapshotProvider()) { entry in
            Text(entry.snapshot.sleep.map { "Сон \($0.duration) · \($0.quality)%" } ?? "Сон: нет данных")
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Сон")
        .description("Прошлая ночь одной строкой.")
        .supportedFamilies([.accessoryInline])
    }
}
