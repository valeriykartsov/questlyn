import SwiftUI
import Domain
import Application

/// Экран «Сегодня» этапа 1 (макет TodayV2 без карты, HP/MP и привычек — они на этапах 2, 4, 6).
struct TodayView: View {
    let model: AppModel

    @State private var isCreating = false
    @State private var openedQuest: Quest?
    @State private var openedHabit: UUID?
    @State private var report: CompletionReport?

    private var items: [TodayItem] { model.overview?.items ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.l) {
                header
                rankCard
                AttributeStrip(progress: model.progress)
                habitsSection
                section(.overdue, title: "Просрочено")
                section(.today, title: "Квесты на сегодня", showEmpty: true)
                section(.undated, title: "Без даты")
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: QSpacing.xxs) {
            Text(Format.longDay(.now))
                .font(QFont.text(13))
                .foregroundStyle(QColor.inkSecondary)
            Text("Сегодня")
                .font(QFont.title(30))
        }
    }

    private var rankCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                Text(model.hero?.classTitle ?? "")
                    .font(QFont.text(12))
                    .foregroundStyle(QColor.inkSecondary)
                Text(AdventurerRank.title(for: model.progress.rank))
                    .font(QFont.text(15, weight: .bold))
            }
            Spacer()
            if let next = model.progress.nextRank {
                Text("\(Format.number(model.progress.rankPoints)) / \(next.threshold) до \(next.letter)")
                    .font(QFont.text(12, weight: .semibold))
                    .foregroundStyle(QColor.inkSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, QSpacing.xl)
        .padding(.vertical, QSpacing.l)
        .sheetCard()
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

    @ViewBuilder
    private var habitsSection: some View {
        let habits = model.habits.filter(\.isScheduledToday)
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
