import SwiftUI
import Domain
import Application

/// Журнал (макеты Journal, 8.12): общая шапка, фильтры, сворачиваемые разделы. Летопись — кнопкой в шапке.
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
    /// Свёрнутые разделы журнала запоминаются.
    @AppStorage("journal.daily.expanded") private var dailyExpanded = true
    @AppStorage("journal.weekly.expanded") private var weeklyExpanded = true
    @AppStorage("journal.epic.expanded") private var epicExpanded = true
    @AppStorage("journal.quests.expanded") private var questsExpanded = true

    private func matches(_ text: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || text.localizedCaseInsensitiveContains(query)
    }

    private var daily: [HabitStatus] {
        model.habits.filter { $0.habit.kind == .daily && matches($0.habit.title) }
            .sorted { ($0.isScheduledToday ? 0 : 1, $0.habit.time == nil ? 1 : 0, $0.habit.time?.description ?? "", $0.habit.createdAt)
                < ($1.isScheduledToday ? 0 : 1, $1.habit.time == nil ? 1 : 0, $1.habit.time?.description ?? "", $1.habit.createdAt) }
    }
    private var weekly: [HabitStatus] { model.habits.filter { $0.habit.kind == .weekly && matches($0.habit.title) } }
    private var epics: [EpicStatus] {
        model.epics.filter { matches($0.epic.title) }.sorted { (!$0.epic.isCompleted ? 0 : 1) < (!$1.epic.isCompleted ? 0 : 1) }
    }
    private var openQuests: [TodayItem] {
        // Шаги Epic — только под своим Epic (8C.7).
        (model.overview?.journal ?? []).filter { !$0.isCompleted && $0.quest.epicId == nil && matches($0.quest.title) }.sorted { lhs, rhs in
            let far = LocalDate(year: 9999, month: 1, day: 1)
            return (lhs.quest.dueDate ?? far, lhs.quest.dueTime?.description ?? "99", lhs.quest.createdAt)
                < (rhs.quest.dueDate ?? far, rhs.quest.dueTime?.description ?? "99", rhs.quest.createdAt)
        }
    }
    private var doneQuests: [TodayItem] {
        (model.overview?.journal ?? []).filter { $0.isCompleted && $0.quest.epicId == nil && matches($0.quest.title) }
            .sorted { ($0.completion?.completedAt ?? .distantPast) > ($1.completion?.completedAt ?? .distantPast) }
    }


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.m) {
                ScreenHeader(model: model, subtitle: "Квесты, привычки и Epic", title: "Журнал")
                filterBar
                if filter == .all || filter == .daily { dailySection }
                if filter == .all || filter == .weekly { weeklySection }
                if filter == .all || filter == .epic { epicSection }
                if filter == .all || filter == .quests { questSection }
            }
            .padding(.horizontal, QSpacing.screen)
            .padding(.top, QSpacing.l)
            .padding(.bottom, 96)
        }
        .paperScreen()
        .keyboardDismissal()
        .overlay(alignment: .bottomTrailing) { AddButton { isAdding = true } }
        .refreshable { await model.reload() }
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
            HStack(spacing: QSpacing.m) {
                ForEach(Filter.allCases) { item in
                    let isOn = filter == item
                    Button(item.rawValue) { filter = item }
                        .font(QFont.text(14, weight: isOn ? .semibold : .medium))
                        .padding(.horizontal, QSpacing.xl)
                        .frame(height: 34)
                        .foregroundStyle(isOn ? QColor.sheet : QColor.ink)
                        .background(isOn ? QColor.ink : .clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(isOn ? .clear : QColor.lineStrong))
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, QSpacing.screen)
        }
        .padding(.horizontal, -QSpacing.screen)
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
            .padding(.horizontal, QSpacing.l).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
    }

    // MARK: Ежедневные — одна карточка, справа точки недели

    @ViewBuilder
    private var dailySection: some View {
        let today = daily.filter(\.isScheduledToday)
        CapsHeader(title: "Ежедневные · сегодня", trailing: today.isEmpty ? nil : "\(today.filter(\.doneToday).count) из \(today.count)",
                   isExpanded: $dailyExpanded)
        if !dailyExpanded {
            EmptyView()
        } else if daily.isEmpty {
            empty("Ежедневных квестов нет. Добавьте через «+».")
        } else {
            VStack(spacing: 0) {
                ForEach(daily) { status in dailyRow(status) }
            }
            .padding(.vertical, QSpacing.xxs)
            .sheetCard()
        }
    }

    private func dailyRow(_ status: HabitStatus) -> some View {
        HStack(spacing: QSpacing.l) {
            Button { toggle(status) } label: { QCheckbox(isOn: status.doneToday, size: 22) }
                .buttonStyle(.plain)
                .frame(width: 32, height: 44)
                .disabled(!status.isScheduledToday)
                .accessibilityLabel(status.doneToday ? "Снять отметку" : "Отметить")
            Button { openedHabit = status.id } label: {
                HStack(spacing: QSpacing.l) {
                    Text(status.habit.title)
                        .font(QFont.text(15))
                        .strikethrough(status.doneToday, color: QColor.inkSecondary)
                        .foregroundStyle(status.doneToday || !status.isScheduledToday ? QColor.inkSecondary : QColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    WeekDots(status: status)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, QSpacing.l)
    }

    // MARK: Недельные — отдельные карточки с полосой

    @ViewBuilder
    private var weeklySection: some View {
        CapsHeader(title: "Недельные", trailing: "до вс", isExpanded: $weeklyExpanded)
        if !weeklyExpanded {
            EmptyView()
        } else if weekly.isEmpty {
            empty("Недельных квестов нет.")
        } else {
            ForEach(weekly) { status in
                Button { openedHabit = status.id } label: {
                    HStack(spacing: QSpacing.l) {
                        Text(status.habit.title).font(QFont.text(15)).frame(maxWidth: .infinity, alignment: .leading)
                        ProgressBar(fraction: Double(status.weekDone) / Double(max(status.weekPlanned, 1)), color: QColor.forest)
                            .frame(width: 72)
                        Text("\(status.weekDone)/\(status.weekPlanned)")
                            .font(QFont.text(13, weight: .semibold)).monospacedDigit()
                            .frame(width: 30, alignment: .trailing)
                    }
                    .padding(.horizontal, QSpacing.l)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                    .sheetCard()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(status.habit.title), \(status.weekDone) из \(status.weekPlanned) за неделю")
            }
        }
    }

    // MARK: Epic — с профессией в акценте и выше остальных (8.4, макет 8.21)

    @ViewBuilder
    private var epicSection: some View {
        let active = epics.filter { !$0.epic.isCompleted }
        CapsHeader(title: "Epic", trailing: "\(active.count) активных", isExpanded: $epicExpanded)
        if !epicExpanded {
            EmptyView()
        } else if epics.isEmpty {
            empty("Epic — большая цель из шагов. Добавьте через «+».")
        } else {
            ForEach(epics) { status in
                let expanded = isExpanded(status)
                VStack(spacing: QSpacing.s) {
                    Button { openedEpic = status.id } label: { epicCard(status) }
                        .buttonStyle(.plain)
                    // Раскрытие шагов — под карточкой Epic, карточка во всю ширину (8C.7).
                    if !status.steps.isEmpty {
                        Button { withAnimation { toggleEpic(status.id) } } label: {
                            HStack(spacing: QSpacing.s) {
                                Text(expanded ? "Скрыть шаги" : "Шаги · \(status.steps.count)")
                                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .semibold))
                            }
                            .font(QFont.text(13, weight: .semibold))
                            .foregroundStyle(QColor.amberDeep)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, -QSpacing.xs)
                    }
                    if expanded {
                        ForEach(status.steps) { journalQuestRow($0, showsEpic: false).padding(.leading, QSpacing.xl) }
                    }
                }
            }
        }
    }

    /// Шаги активного Epic по умолчанию раскрыты, завершённого — свёрнуты; касание меняет (8C.7).
    @AppStorage("journal.epic.toggled") private var toggledEpics = ""

    private func isExpanded(_ status: EpicStatus) -> Bool {
        let toggled = toggledEpics.split(separator: ",").contains { $0 == status.id.uuidString }
        return status.epic.isCompleted ? toggled : !toggled
    }

    private func toggleEpic(_ id: UUID) {
        var ids = Set(toggledEpics.split(separator: ",").map(String.init))
        if ids.contains(id.uuidString) { ids.remove(id.uuidString) } else { ids.insert(id.uuidString) }
        toggledEpics = ids.sorted().joined(separator: ",")
    }

    /// Профессия Epic, если она задана и активна.
    private func epicProfession(_ status: EpicStatus) -> Profession? {
        model.profession(id: status.epic.professionId).flatMap { $0.isActive ? $0 : nil }
    }

    private func epicCard(_ status: EpicStatus) -> some View {
        let profession = epicProfession(status)
        let accent = profession != nil
        let share = status.steps.isEmpty ? 0 : Double(status.doneCount) / Double(status.steps.count)
        return HStack(spacing: QSpacing.l) {
            Image(systemName: status.epic.isCompleted ? "flag.checkered" : "flag")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent ? QColor.amber : QColor.ink)
                .frame(width: 40, height: 40)
                .background(accent ? QColor.warmFill : QColor.coolFill, in: RoundedRectangle(cornerRadius: QRadius.control))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: QSpacing.xs) {
                Text(profession.map { "Epic · \($0.title)" } ?? "Epic")
                    .font(QFont.text(11, weight: .bold)).textCase(.uppercase).tracking(0.6)
                    .foregroundStyle(accent ? QColor.amberDeep : QColor.inkSecondary)
                Text(status.epic.title).font(QFont.text(16, weight: .semibold)).foregroundStyle(QColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: QSpacing.m) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(QColor.track)
                            Capsule().fill(accent ? QColor.amber : QColor.ink).frame(width: proxy.size.width * share)
                        }
                    }
                    .frame(height: 6)
                    Text(status.epic.isCompleted ? "веха" : "\(status.doneCount) из \(status.steps.count)")
                        .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary).monospacedDigit()
                }
                if !status.epic.isCompleted, let next = status.nextStep {
                    Text("Следующий шаг: \(next.quest.title)").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary).lineLimit(1)
                } else if status.canComplete {
                    Text("Все шаги выполнены — можно завершить").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                }
            }
        }
        .padding(QSpacing.l)
        .contentShape(Rectangle())
        .sheetCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: Квесты — отдельные карточки без рамки

    @ViewBuilder
    private var questSection: some View {
        CapsHeader(title: "Квесты", trailing: "по дате · \(openQuests.count)", isExpanded: $questsExpanded)
        if questsExpanded {
            if openQuests.isEmpty { empty("Открытых квестов нет.") } else { ForEach(openQuests) { journalQuestRow($0) } }
        }
        if questsExpanded, !doneQuests.isEmpty {
            Button(showsCompleted ? "Скрыть выполненные" : "Выполненные · \(doneQuests.count)") {
                withAnimation { showsCompleted.toggle() }
            }
            .font(QFont.text(14, weight: .semibold))
            .foregroundStyle(QColor.amberDeep)
            .frame(minHeight: 44)
            if showsCompleted { ForEach(Array(doneQuests.prefix(50))) { journalQuestRow($0) } }
        }
    }

    private func journalQuestRow(_ item: TodayItem, showsEpic: Bool = true) -> some View {
        HStack(spacing: QSpacing.l) {
            Button {
                Task {
                    if item.isCompleted { await model.undo(questId: item.quest.id) }
                    else { report = await model.complete(questId: item.quest.id) }
                }
            } label: { QCheckbox(isOn: item.isCompleted, size: 22) }
            .buttonStyle(.plain)
            .frame(width: 32, height: 44)
            .accessibilityLabel(item.isCompleted ? "Отменить выполнение" : "Выполнить")

            Button { openedQuest = item.quest } label: {
                HStack(spacing: QSpacing.l) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.quest.title)
                            .font(QFont.text(15))
                            .strikethrough(item.isCompleted, color: QColor.inkSecondary)
                            .foregroundStyle(item.isCompleted ? QColor.inkSecondary : QColor.ink)
                            .multilineTextAlignment(.leading)
                        if showsEpic, let epic = model.epic(id: item.quest.epicId) {
                            Text(epic.epic.title).font(QFont.text(12)).foregroundStyle(QColor.amberDeep)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Format.when(item.quest, today: model.today))
                        .font(QFont.text(12))
                        .foregroundStyle(item.section == .overdue && !item.isCompleted ? QColor.hp : QColor.inkSecondary)
                    PriorityBars(priority: item.quest.priority)
                }
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, QSpacing.l)
        .padding(.vertical, QSpacing.xs)
        .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
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
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(QColor.sheet)
                .frame(width: 56, height: 56)
                .background(QColor.ink, in: RoundedRectangle(cornerRadius: QRadius.hero))
                .shadow(color: QColor.ink.opacity(0.25), radius: 6, y: 4)
        }
        .accessibilityLabel("Создать")
        .padding(.trailing, 20)
        .padding(.bottom, QSpacing.screen)
    }
}
