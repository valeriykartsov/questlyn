import SwiftUI
import Domain
import Application

/// Журнал квестов (макет Journal): фильтры, секции, поиск.
struct JournalView: View {
    let model: AppModel

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Все", quests = "Квесты", daily = "Ежедневные", weekly = "Недельные", epic = "Epic"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var isAdding = false
    @State private var openedQuest: Quest?
    @State private var openedHabit: UUID?
    @State private var openedEpic: UUID?
    @State private var report: CompletionReport?
    @State private var showsCompleted = false

    private func matches(_ text: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || text.localizedCaseInsensitiveContains(query)
    }

    private var daily: [HabitStatus] {
        model.habits.filter { $0.habit.kind == .daily && matches($0.habit.title) }
            .sorted { ($0.isScheduledToday ? 0 : 1, $0.habit.createdAt) < ($1.isScheduledToday ? 0 : 1, $1.habit.createdAt) }
    }
    private var weekly: [HabitStatus] { model.habits.filter { $0.habit.kind == .weekly && matches($0.habit.title) } }
    private var epics: [EpicStatus] {
        model.epics.filter { matches($0.epic.title) }.sorted { (!$0.epic.isCompleted ? 0 : 1) < (!$1.epic.isCompleted ? 0 : 1) }
    }
    private var openQuests: [TodayItem] {
        (model.overview?.journal ?? []).filter { !$0.isCompleted && matches($0.quest.title) }.sorted { lhs, rhs in
            let far = LocalDate(year: 9999, month: 1, day: 1)
            return (lhs.quest.dueDate ?? far, lhs.quest.dueTime?.description ?? "99", lhs.quest.createdAt)
                < (rhs.quest.dueDate ?? far, rhs.quest.dueTime?.description ?? "99", rhs.quest.createdAt)
        }
    }
    private var doneQuests: [TodayItem] {
        (model.overview?.journal ?? []).filter { $0.isCompleted && matches($0.quest.title) }
            .sorted { ($0.completion?.completedAt ?? .distantPast) > ($1.completion?.completedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: QSpacing.l) {
                    filterBar
                    if filter == .all || filter == .daily { dailySection }
                    if filter == .all || filter == .weekly { weeklySection }
                    if filter == .all || filter == .epic { epicSection }
                    if filter == .all || filter == .quests { questSection }
                }
                .padding(.horizontal, QSpacing.screen)
                .padding(.bottom, 96)
            }
            .paperScreen()
            .navigationTitle("Журнал квестов")
            .searchable(text: $search, prompt: "Поиск по названию")
            .overlay(alignment: .bottomTrailing) { AddButton { isAdding = true } }
            .refreshable { await model.reload() }
        }
        .sheet(isPresented: $isAdding) { AddFlowView(model: model) }
        .sheet(item: $openedQuest) { QuestDetailView(model: model, questId: $0.id) { report = $0 } }
        .sheet(item: Binding(get: { openedHabit.map(IdentifiedID.init) }, set: { openedHabit = $0?.id })) {
            HabitDetailView(model: model, habitId: $0.id)
        }
        .sheet(item: Binding(get: { openedEpic.map(IdentifiedID.init) }, set: { openedEpic = $0?.id })) {
            EpicDetailView(model: model, epicId: $0.id)
        }
        .fullScreenCover(item: $report) { RewardView(model: model, report: $0) }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: QSpacing.s) {
                ForEach(Filter.allCases) { item in
                    Button(item.rawValue) { filter = item }
                        .font(QFont.text(14, weight: .semibold))
                        .padding(.horizontal, QSpacing.xl)
                        .frame(height: 34)
                        .foregroundStyle(filter == item ? QColor.sheet : QColor.ink)
                        .background(filter == item ? QColor.ink : QColor.sheet, in: Capsule())
                        .overlay(Capsule().strokeBorder(filter == item ? .clear : QColor.line))
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filter == item ? .isSelected : [])
                }
            }
        }
    }

    private func header(_ title: String, _ trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(QFont.title(18))
            Spacer()
            if let trailing { Text(trailing).font(QFont.text(12, weight: .semibold)).foregroundStyle(QColor.inkSecondary) }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
            .padding(QSpacing.xl).frame(maxWidth: .infinity, alignment: .leading).sheetCard()
    }

    @ViewBuilder
    private var dailySection: some View {
        let today = daily.filter(\.isScheduledToday)
        VStack(alignment: .leading, spacing: QSpacing.m) {
            header("Ежедневные · сегодня", today.isEmpty ? nil : "\(today.filter(\.doneToday).count) из \(today.count)")
            if daily.isEmpty { empty("Ежедневных квестов нет. Добавьте через «+».") } else { habitList(daily) }
        }
    }

    @ViewBuilder
    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            header("Недельные", "до вс")
            if weekly.isEmpty { empty("Недельных квестов нет.") } else { habitList(weekly) }
        }
    }

    private func habitList(_ items: [HabitStatus]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, status in
                if index > 0 { Divider().overlay(QColor.line).padding(.leading, 52) }
                HabitRow(status: status) { toggle(status) } open: { openedHabit = status.id }
                    .opacity(status.isScheduledToday ? 1 : 0.55)
            }
        }
        .sheetCard()
    }

    @ViewBuilder
    private var epicSection: some View {
        let active = epics.filter { !$0.epic.isCompleted }.count
        VStack(alignment: .leading, spacing: QSpacing.m) {
            header("Epic", "\(active) активных")
            if epics.isEmpty {
                empty("Epic — большая цель из шагов. Добавьте через «+».")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(epics.enumerated()), id: \.element.id) { index, status in
                        if index > 0 { Divider().overlay(QColor.line) }
                        Button { openedEpic = status.id } label: { epicRow(status) }.buttonStyle(.plain)
                    }
                }
                .sheetCard()
            }
        }
    }

    private func epicRow(_ status: EpicStatus) -> some View {
        VStack(alignment: .leading, spacing: QSpacing.s) {
            HStack {
                Text(status.epic.title).font(QFont.text(15, weight: .semibold))
                Spacer()
                Text(status.epic.isCompleted ? "веха" : "\(status.doneCount) из \(status.steps.count)")
                    .font(QFont.text(13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(status.epic.isCompleted ? QColor.forest : QColor.ink)
            }
            ProgressBar(fraction: status.steps.isEmpty ? 0 : Double(status.doneCount) / Double(status.steps.count), color: QColor.forest)
            if let next = status.nextStep, !status.epic.isCompleted {
                Text("Следующий шаг: \(next.quest.title) · \(Format.when(next.quest, today: model.today))")
                    .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            } else if status.canComplete {
                Text("Все шаги выполнены — можно завершить").font(QFont.text(12, weight: .semibold)).foregroundStyle(QColor.forest)
            }
        }
        .padding(.horizontal, QSpacing.xl)
        .padding(.vertical, QSpacing.l)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var questSection: some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            header("Квесты", "по дате")
            if openQuests.isEmpty { empty("Открытых квестов нет.") } else { questList(openQuests) }
            if !doneQuests.isEmpty {
                Button(showsCompleted ? "Скрыть выполненные" : "Выполненные · \(doneQuests.count)") {
                    withAnimation { showsCompleted.toggle() }
                }
                .font(QFont.text(14, weight: .semibold))
                .foregroundStyle(QColor.amberDeep)
                if showsCompleted { questList(Array(doneQuests.prefix(50))) }
            }
        }
    }

    private func questList(_ items: [TodayItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().overlay(QColor.line).padding(.leading, 52) }
                QuestRow(item: item, today: model.today, profession: model.profession(id: item.skill?.professionId),
                         epicTitle: model.epic(id: item.quest.epicId)?.epic.title) {
                    Task {
                        if item.isCompleted { await model.undo(questId: item.quest.id) }
                        else { report = await model.complete(questId: item.quest.id) }
                    }
                } open: { openedQuest = item.quest }
            }
        }
        .sheetCard()
    }

    private func toggle(_ status: HabitStatus) {
        Task {
            if status.doneToday { await model.unmarkHabit(status.id, on: status.today) }
            else { await model.markHabit(status.id, on: status.today) }
        }
    }
}

/// Обёртка для `.sheet(item:)` по UUID.
struct IdentifiedID: Identifiable {
    let id: UUID
}

/// Круглая кнопка «+».
struct AddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(QColor.sheet)
                .frame(width: 56, height: 56)
                .background(QColor.amber, in: Circle())
                .shadow(color: QColor.ink.opacity(0.15), radius: 6, y: 3)
        }
        .accessibilityLabel("Добавить")
        .padding(QSpacing.screen)
    }
}
