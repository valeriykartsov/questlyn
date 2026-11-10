import SwiftUI
import Domain
import Application

/// Карточка Epic (макет Epic): прогресс, шаги, веха.
struct EpicDetailView: View {
    let model: AppModel
    let epicId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var isAddingStep = false
    @State private var openedQuest: Quest?
    @State private var report: CompletionReport?

    private var status: EpicStatus? { model.epic(id: epicId) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let status { content(status) } else { Text("Epic не найден").padding() }
            }
            .paperScreen()
            .navigationTitle("Epic Quest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .sheet(isPresented: $isAddingStep) {
                NavigationStack { QuestFormView(model: model, epicId: epicId) }
            }
            .sheet(item: $openedQuest) { quest in
                QuestDetailView(model: model, questId: quest.id) { report = $0 }
            }
            .fullScreenCover(item: $report) { RewardView(model: model, report: $0) }
        }
    }

    private func content(_ status: EpicStatus) -> some View {
        let epic = status.epic
        let open = status.steps.filter { !$0.isCompleted }
        let done = status.steps.filter(\.isCompleted)
        return VStack(alignment: .leading, spacing: QSpacing.l) {
            VStack(alignment: .leading, spacing: QSpacing.s) {
                Text(epic.title).font(QFont.title(24))
                if let details = epic.details { Text(details).font(QFont.text(15)).foregroundStyle(QColor.inkSecondary) }
                if let deadline = epic.deadline {
                    Text("Срок — \(Format.shortDay(deadline))").font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                }
            }

            VStack(alignment: .leading, spacing: QSpacing.s) {
                HStack {
                    Text(epic.isCompleted ? "Epic завершён — веха" : "Прогресс").font(QFont.text(15, weight: .semibold))
                    Spacer()
                    Text("\(status.doneCount) из \(status.steps.count)").font(QFont.text(15, weight: .bold)).monospacedDigit()
                }
                ProgressBar(fraction: status.steps.isEmpty ? 0 : Double(status.doneCount) / Double(status.steps.count), color: QColor.forest)
            }
            .padding(QSpacing.xl)
            .sheetCard()

            stepList("Шаги", items: open, emptyText: "Открытых шагов нет")
            Button("Добавить шаг") { isAddingStep = true }
                .buttonStyle(SecondaryButtonStyle())
            if !done.isEmpty { stepList("Выполнено · \(done.count)", items: done, emptyText: "") }

            if status.canComplete {
                Button("Завершить Epic") { Task { await model.completeEpic(epicId) } }
                    .buttonStyle(PrimaryButtonStyle())
            } else if epic.isCompleted {
                Button("Вернуть в работу") { Task { await model.reopenEpic(epicId) } }
                    .font(QFont.text(15, weight: .semibold)).foregroundStyle(QColor.amberDeep).frame(maxWidth: .infinity, minHeight: 44)
            }
            Text("Завершение Epic — веха без XP. Награду приносят шаги.")
                .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
        }
        .padding(QSpacing.screen)
    }

    @ViewBuilder
    private func stepList(_ title: String, items: [TodayItem], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            Text(title).font(QFont.title(18))
            if items.isEmpty {
                Text(emptyText).font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(QColor.line).padding(.leading, 52) }
                        QuestRow(item: item, today: model.today, profession: model.profession(id: item.skill?.professionId)) {
                            Task {
                                if item.isCompleted { await model.undo(questId: item.quest.id) }
                                else { report = await model.complete(questId: item.quest.id) }
                            }
                        } open: { openedQuest = item.quest }
                    }
                }
                .sheetCard()
            }
        }
    }
}
