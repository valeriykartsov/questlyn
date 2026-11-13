import SwiftUI
import Domain
import Application

/// «Дневник» (макет 12D.4): отметки настроения блоками, последняя сверху. Слева — погода, затем настроение и заметка,
/// справа — значки полезного и вредного, внесённого в этом же чек-ине.
struct DiarySheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                DiaryView(model: model)
                    .padding(.horizontal, QSpacing.screen)
                    .padding(.vertical, QSpacing.l)
            }
            .paperScreen()
            .navigationTitle("Дневник")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .tint(QColor.amber)
    }
}

struct DiaryView: View {
    let model: AppModel

    /// Значок отметки — факт внесения, без количества.
    struct Mark: Hashable {
        let symbol: String
        let title: String
        let isGood: Bool
    }

    struct Entry: Identifiable {
        let mood: MoodEntry
        let marks: [Mark]
        var id: UUID { mood.id }
    }

    /// Отметки одного сохранения различаются на миллисекунды — так они находят свою запись настроения.
    private var entries: [Entry] {
        #if DEBUG
        // `-QuestlynSampleDiary YES` — пример записей для проверки вида в симуляторе.
        if UserDefaults.standard.bool(forKey: "QuestlynSampleDiary") {
            let today = model.today
            func mood(_ value: Mood, _ note: String?, hoursAgo: Double, summary: Bool = false) -> MoodEntry {
                let at = Date.now - hoursAgo * 3600
                return MoodEntry(mood: value, note: note, isDaySummary: summary, at: at, localDate: LocalDate(at, timeZone: .current), timezoneId: "UTC")
            }
            _ = today
            return [
                Entry(mood: mood(.good, "Сдал отчёт, вечером прогулка с Петей — день получился.", hoursAgo: 0.5, summary: true),
                      marks: [Mark(symbol: "figure.walk", title: "Прогулка", isGood: true), Mark(symbol: "smoke", title: "Курение", isGood: false)]),
                Entry(mood: mood(.neutral, nil, hoursAgo: 6), marks: []),
                Entry(mood: mood(.bad, "Не выспался, созвоны до вечера.", hoursAgo: 26, summary: true),
                      marks: [Mark(symbol: "wineglass", title: "Алкоголь", isGood: false), Mark(symbol: "smoke", title: "Курение", isGood: false),
                              Mark(symbol: "takeoutbag.and.cup.and.straw", title: "Фастфуд", isGood: false), Mark(symbol: "drop", title: "Вода", isGood: true)])
            ]
        }
        #endif
        let log = model.vitals?.log ?? []
        let moods = (model.overview?.moods ?? []).sorted { $0.at > $1.at }
        return moods.map { mood in
            var marks: [Mark] = []
            for item in log where abs(item.at.timeIntervalSince(mood.at)) < 1 {
                let mark: Mark? = switch item.kind {
                case let .harm(entry, _, _): Mark(symbol: Self.symbol(entry.kind), title: entry.kind == .custom ? entry.title : entry.kind.title, isGood: false)
                case let .benefit(entry, _): Mark(symbol: Self.symbol(entry.kind), title: entry.kind == .custom ? entry.title : entry.kind.title, isGood: true)
                default: nil
                }
                if let mark, !marks.contains(mark) { marks.append(mark) }
            }
            return Entry(mood: mood, marks: marks.sorted { ($0.isGood ? 0 : 1) < ($1.isGood ? 0 : 1) })
        }
    }

    var body: some View {
        let grouped = Dictionary(grouping: entries) { $0.mood.localDate }
        VStack(alignment: .leading, spacing: QSpacing.l) {
            if entries.isEmpty {
                Text("Здесь будут отметки настроения с заметками. Отметить — кнопка «Как вы?» на «Сегодня».")
                    .font(QFont.text(14)).foregroundStyle(QColor.inkSecondary)
                    .padding(QSpacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sheetCard()
            }
            ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
                VStack(alignment: .leading, spacing: QSpacing.s) {
                    CapsHeader(title: dayTitle(day))
                    ForEach(grouped[day] ?? []) { entry in block(entry) }
                }
            }
        }
    }

    private func dayTitle(_ day: LocalDate) -> String {
        let date = Format.shortDay(day)
        if day == model.today { return "Сегодня · \(date)" }
        if day == model.today.adding(days: -1) { return "Вчера · \(date)" }
        return date
    }

    private func block(_ entry: Entry) -> some View {
        let weather = Weather.from(entry.mood.mood, on: entry.mood.localDate)
        return HStack(alignment: .top, spacing: QSpacing.m) {
            Image(systemName: WeatherStyle.symbol(weather))
                .font(.system(size: 18))
                .foregroundStyle(QColor.ink)
                .frame(width: 36, height: 36)
                .background(QColor.paper, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(weather.title)
            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                HStack(spacing: QSpacing.s) {
                    Text(entry.mood.mood.title).font(QFont.text(15, weight: .bold))
                    Text(entry.mood.at.formatted(date: .omitted, time: .shortened))
                        .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary).monospacedDigit()
                    if entry.mood.isDaySummary {
                        Text("Итог дня").font(QFont.text(10, weight: .bold)).textCase(.uppercase).tracking(0.6).foregroundStyle(QColor.amberDeep)
                    }
                }
                if let note = entry.mood.note {
                    Text(note).font(QFont.text(14)).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("без заметки").font(QFont.text(14)).italic().foregroundStyle(QColor.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !entry.marks.isEmpty {
                // Значки по 3 в ряд, справа.
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 4), count: min(3, entry.marks.count)), spacing: 4) {
                    ForEach(entry.marks, id: \.self) { mark in
                        Image(systemName: mark.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(mark.isGood ? QColor.forest : QColor.hp)
                            .frame(width: 22, height: 22)
                            .background((mark.isGood ? QColor.forest : QColor.hp).opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                            .accessibilityLabel(mark.title)
                    }
                }
                .fixedSize()
            }
        }
        .padding(QSpacing.l)
        .sheetCard()
        .accessibilityElement(children: .combine)
    }

    static func symbol(_ kind: HarmKind) -> String {
        switch kind {
        case .smoking: "smoke"
        case .fastFood: "takeoutbag.and.cup.and.straw"
        case .lateCaffeine: "cup.and.saucer"
        case .alcohol: "wineglass"
        case .custom: "exclamationmark.circle"
        }
    }

    static func symbol(_ kind: BenefitKind) -> String {
        switch kind {
        case .water: "drop"
        case .vegetables: "carrot"
        case .outdoorWalk: "figure.walk"
        case .stretching: "figure.flexibility"
        case .nap: "bed.double"
        case .custom: "leaf"
        }
    }
}
