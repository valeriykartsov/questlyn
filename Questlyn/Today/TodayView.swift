import SwiftUI
import Domain
import Application

/// Экран «Сегодня» (макет TodayV2, миниатюра дня — холст 8.9).
struct TodayView: View {
    let model: AppModel

    @State private var isCreating = false
    @State private var openedQuest: Quest?
    @State private var openedHabit: UUID?
    @State private var report: CompletionReport?
    @State private var isShowingMorning = false
    @State private var isCheckingIn = false
    @State private var isShowingMap = false
    /// Утро показываем сами один раз в день; дальше — по кнопке «Как спали?».
    @AppStorage("morningShownDate") private var morningShownDate = ""

    private var items: [TodayItem] { model.overview?.items ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.l) {
                header
                DayStripCard(model: model) { isShowingMap = true }
                SleepCard(model: model) { isShowingMorning = true }
                WeatherCard(model: model) { isCheckingIn = true }
                if let vitals = model.vitals {
                    VitalsCard(vitals: vitals)
                }
                AttributeStrip(progress: model.progress)
                habitsSection
                activitySection
                section(.overdue, title: "Просрочено")
                section(.today, title: "Квесты на сегодня", showEmpty: true)
            }
            .padding(.horizontal, QSpacing.screen)
            .padding(.top, QSpacing.l)
            .padding(.bottom, 96)
        }
        .paperScreen()
        .overlay(alignment: .bottomTrailing) { AddButton { isCreating = true } }
        .refreshable { await model.reload() }
        .sheet(isPresented: $isCreating) { AddFlowView(model: model) }
        .sheet(item: Binding(get: { openedHabit.map(IdentifiedID.init) }, set: { openedHabit = $0?.id })) {
            HabitDetailView(model: model, habitId: $0.id)
        }
        .sheet(item: $openedQuest) { quest in
            QuestDetailView(model: model, questId: quest.id) { report = $0 }
        }
        .fullScreenCover(item: $report) { report in
            RewardView(model: model, report: report)
        }
        .sheet(isPresented: $isShowingMorning) { MorningView(model: model) }
        .sheet(isPresented: $isCheckingIn) { CheckInView(model: model) }
        .fullScreenCover(isPresented: $isShowingMap) { MapOverviewView(model: model) }
        .onAppear { model.loadAgenda(from: model.today, through: model.today) }
        .onAppear(perform: presentMorningIfNeeded)
        .onChange(of: model.overview?.date) { presentMorningIfNeeded() }
        .onChange(of: model.overview?.hasSleepToday) { presentMorningIfNeeded() }
    }

    private func presentMorningIfNeeded() {
        guard let overview = model.overview, model.hero != nil else { return }
        let today = overview.date.description
        guard morningShownDate != today else { return }
        let fromHealth = overview.hasSleepToday && model.vitals?.lastNight?.session?.source == .health
        guard model.needsSleepAnswer || fromHealth else { return }
        morningShownDate = today
        isShowingMorning = true
    }

    private var header: some View {
        ScreenHeader(model: model, subtitle: Format.longDay(.now), title: "Сегодня")
    }

    @ViewBuilder
    private func section(_ section: TodaySection, title: String, showEmpty: Bool = false) -> some View {
        let rows = items.filter { $0.section == section }
        if !rows.isEmpty || showEmpty {
            VStack(alignment: .leading, spacing: QSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(QFont.title(18))
                    Spacer()
                    if !rows.isEmpty {
                        Text("\(rows.filter(\.isCompleted).count) из \(rows.count)")
                            .font(QFont.text(12, weight: .semibold))
                            .foregroundStyle(QColor.inkSecondary)
                    }
                }
                if rows.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: QSpacing.s) {
                        ForEach(rows) { item in
                            QuestRow(item: item, today: model.overview?.date, profession: model.profession(id: item.skill?.professionId),
                                     epicTitle: model.epic(id: item.quest.epicId)?.epic.title) {
                                toggle(item)
                            } open: {
                                openedQuest = item.quest
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: QSpacing.xs) {
            Text("Квестов на сегодня нет")
                .font(QFont.text(15, weight: .semibold))
            Text("Нажмите «+», чтобы добавить квест, привычку или Epic. Выполненные квесты растят героя.")
                .font(QFont.text(13))
                .foregroundStyle(QColor.inkSecondary)
        }
        .padding(.vertical, QSpacing.l)
        .padding(.horizontal, QSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheetCard()
    }

    @State private var deletingActivity: Activity?

    /// Активность за сегодня: тип, длительность, что дала.
    @ViewBuilder
    private var activitySection: some View {
        if !model.activities.isEmpty {
            VStack(alignment: .leading, spacing: QSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Активность").font(QFont.title(18))
                    Spacer()
                    Text(Format.minutes(model.activities.reduce(0) { $0 + $1.durationMinutes }) + " сегодня")
                        .font(QFont.text(12, weight: .semibold)).foregroundStyle(QColor.inkSecondary)
                }
                VStack(spacing: QSpacing.s) {
                    ForEach(model.activities) { activity in
                        Button { deletingActivity = activity } label: { activityRow(activity) }.buttonStyle(.plain)
                    }
                }
            }
            .alert("Удалить активность?", isPresented: Binding(get: { deletingActivity != nil }, set: { if !$0 { deletingActivity = nil } }), presenting: deletingActivity) { activity in
                Button("Удалить", role: .destructive) { Task { await model.deleteActivity(activity.id) } }
                Button("Отмена", role: .cancel) {}
            } message: { activity in
                Text(activity.questCompletionId == nil ? "Начисления этой активности будут сняты."
                                                       : "Активность закрыла квест. Чтобы убрать её вместе с квестом, отмените выполнение квеста.")
            }
        }
    }

    private func activityRow(_ activity: Activity) -> some View {
        let grants = (model.overview?.progress.grants ?? []).filter { $0.sourceId == activity.id }
        return HStack(spacing: QSpacing.l) {
            Image(systemName: "timer").font(.system(size: 18)).foregroundStyle(QColor.forest).frame(width: 32, height: 44)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(activity.template?.title ?? "Активность") · \(Format.minutes(activity.durationMinutes))").font(QFont.text(15))
                Text(grants.isEmpty ? "Предел дня — без XP" : model.grantSummary(grants))
                    .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(activity.startedAt.formatted(.dateTime.hour().minute().locale(Locale(identifier: "ru_RU"))))
                .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
        }
        .padding(.leading, QSpacing.xs).padding(.trailing, QSpacing.l).padding(.vertical, QSpacing.xs)
        .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var habitsSection: some View {
        // Недельные — под ежедневными (9.7); внутри — по времени.
        let scheduled = model.habits.filter(\.isScheduledToday)
        let habits = scheduled.filter { $0.habit.kind == .daily } + scheduled.filter { $0.habit.kind == .weekly }
        if !habits.isEmpty {
            let daily = habits.filter { $0.habit.kind == .daily }
            VStack(alignment: .leading, spacing: QSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Привычки").font(QFont.title(18))
                    Spacer()
                    if !daily.isEmpty {
                        Text("\(daily.filter(\.doneToday).count) из \(daily.count) сегодня")
                            .font(QFont.text(12, weight: .semibold))
                            .foregroundStyle(QColor.inkSecondary)
                    }
                }
                VStack(spacing: QSpacing.s) {
                    ForEach(habits) { status in
                        HabitRow(status: status, attribute: model.profession(id: status.skill?.professionId)?.attributes.first) {
                            Task {
                                if status.doneToday { await model.unmarkHabit(status.id, on: status.today) }
                                else { await model.markHabit(status.id, on: status.today) }
                            }
                        } open: { openedHabit = status.id }
                    }
                }
            }
        }
    }

    private func toggle(_ item: TodayItem) {
        Task {
            if item.isCompleted {
                await model.undo(questId: item.quest.id)
            } else {
                report = await model.complete(questId: item.quest.id)
            }
        }
    }
}

/// Строка квеста: отметка, название, подпись.
struct QuestRow: View {
    let item: TodayItem
    let today: LocalDate?
    let profession: Profession?
    var epicTitle: String?
    let toggle: () -> Void
    let open: () -> Void

    var body: some View {
        HStack(spacing: QSpacing.l) {
            Button(action: toggle) {
                QCheckbox(isOn: item.isCompleted)
                    .frame(width: 32, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Отменить выполнение" : "Выполнить")

            Button(action: open) {
                VStack(alignment: .leading, spacing: QSpacing.xxs) {
                    Text(item.quest.title)
                        .font(QFont.text(15))
                        .strikethrough(item.isCompleted, color: QColor.inkSecondary)
                        .foregroundStyle(item.isCompleted ? QColor.inkSecondary : QColor.ink)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(QFont.text(12))
                        .foregroundStyle(item.section == .overdue ? QColor.hp : QColor.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, QSpacing.xs)
        .padding(.trailing, QSpacing.l)
        .padding(.vertical, QSpacing.xs)
        .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
    }

    private var subtitle: String {
        var parts: [String] = []
        if let epicTitle { parts.append(epicTitle) }
        if item.section == .today, let time = item.quest.dueTime {
            parts.append("до \(time)")
        } else if item.section != .undated {
            parts.append(Format.when(item.quest, today: today))
        }
        if epicTitle == nil, let skill = item.skill { parts.append(skill.title) }
        if item.quest.priority != .medium { parts.append(Format.priority(item.quest.priority)) }
        return parts.isEmpty ? "Без навыка" : parts.joined(separator: " · ")
    }
}
