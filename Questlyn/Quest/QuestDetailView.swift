import SwiftUI
import Domain
import Application

/// Карточка квеста (макет QuestDetail): выполнить, изменить, перенести.
struct QuestDetailView: View {
    let model: AppModel
    let questId: UUID
    let onComplete: (CompletionReport) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var isEditing = false
    @State private var isRescheduling = false
    @State private var isCompletingWithActivity = false
    @State private var isConfirmingRefusal = false
    @State private var newDay = Date.now

    private var item: TodayItem? { model.questItem(id: questId) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let item {
                    content(item)
                } else {
                    Text("Квест не найден").padding()
                }
            }
            .paperScreen()
            .navigationTitle("Квест")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Изменить") { isEditing = true }.disabled(item == nil) }
            }
            .sheet(isPresented: $isEditing) {
                if let quest = item?.quest { NavigationStack { QuestFormView(model: model, editing: quest) } }
            }
            .sheet(isPresented: $isRescheduling) { rescheduleSheet }
            .sheet(isPresented: $isCompletingWithActivity) {
                if let quest = item?.quest {
                    QuestActivitySheet(model: model, quest: quest) { report in
                        dismiss()
                        onComplete(report)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func content(_ item: TodayItem) -> some View {
        let quest = item.quest
        let profession = model.profession(id: item.skill?.professionId)
        return VStack(alignment: .leading, spacing: QSpacing.l) {
            VStack(alignment: .leading, spacing: QSpacing.s) {
                Text(quest.title).font(QFont.title(24))
                if let details = quest.details {
                    Text(details).font(QFont.text(15)).foregroundStyle(QColor.inkSecondary)
                }
            }

            VStack(spacing: 0) {
                if let epic = model.epic(id: quest.epicId) {
                    InfoRow(label: "Epic", value: epic.epic.title, note: "шаг \(epic.doneCount) из \(epic.steps.count) выполнено")
                    Divider().overlay(QColor.line)
                }
                InfoRow(label: "Навык", value: item.skill?.title ?? "Без навыка", note: profession?.title)
                Divider().overlay(QColor.line)
                InfoRow(label: "Приоритет", value: Format.priority(quest.priority), note: "награда \(Format.multiplier(quest.priority))")
                Divider().overlay(QColor.line)
                InfoRow(label: "Когда", value: Format.when(quest, today: model.overview?.date))
                Divider().overlay(QColor.line)
                InfoRow(label: "Создан", value: quest.createdAt.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "ru_RU"))))
                if let completion = item.completion {
                    Divider().overlay(QColor.line)
                    InfoRow(label: "Выполнен", value: completion.completedAt.formatted(.dateTime.day().month(.wide).hour().minute().locale(Locale(identifier: "ru_RU"))))
                }
            }
            .padding(.horizontal, QSpacing.xl)
            .sheetCard()

            VStack(alignment: .leading, spacing: QSpacing.s) {
                Text(item.isCompleted ? "Получено" : "Награда при выполнении")
                    .font(QFont.text(13, weight: .semibold))
                    .foregroundStyle(QColor.inkSecondary)
                Text(rewardSummary(item, profession: profession))
                    .font(QFont.text(15))
            }
            .padding(QSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheetCard()

            if item.isCompleted {
                Button("Отменить выполнение") {
                    isWorking = true
                    Task {
                        await model.undo(questId: quest.id)
                        isWorking = false
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isWorking)
            } else {
                Button("Выполнить") {
                    isWorking = true
                    Task {
                        if let report = await model.complete(questId: quest.id) {
                            dismiss()
                            onComplete(report)
                        }
                        isWorking = false
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isWorking)
                Button("Выполнить с активностью") { isCompletingWithActivity = true }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Перенести") {
                    newDay = quest.dueDate?.date ?? .now
                    isRescheduling = true
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Button("Отказаться от квеста", role: .destructive) { isConfirmingRefusal = true }
                .font(QFont.text(15, weight: .semibold))
                .foregroundStyle(QColor.hp)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(isWorking)
        }
        .padding(QSpacing.screen)
        .alert("Отказаться от квеста «\(quest.title)»?", isPresented: $isConfirmingRefusal) {
            Button("Отказаться", role: .destructive) {
                isWorking = true
                Task {
                    if await model.deleteQuest(quest.id) { dismiss() }
                    isWorking = false
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(refusalMessage(item))
        }
    }

    private var rescheduleSheet: some View {
        NavigationStack {
            VStack(spacing: QSpacing.l) {
                HStack(spacing: QSpacing.m) {
                    Button("Сегодня") { reschedule(to: model.today) }
                    Button("Завтра") { reschedule(to: model.today.adding(days: 1)) }
                    Button("Без даты") { reschedule(to: nil) }
                }
                .buttonStyle(SecondaryButtonStyle())
                DatePicker("Дата", selection: $newDay, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "ru_RU"))
                    .tint(QColor.amber)
                Button("Перенести на \(Format.shortDay(LocalDate(newDay, timeZone: .current)))") {
                    reschedule(to: LocalDate(newDay, timeZone: .current))
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(QSpacing.screen)
            .paperScreen()
            .navigationTitle("Перенести")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { isRescheduling = false } } }
        }
        .presentationDetents([.large])
    }

    /// Перенос сохраняет время, если новая дата есть; без даты — без времени.
    /// Что случится при отказе: квест исчезнет отовсюду; полученный XP останется.
    private func refusalMessage(_ item: TodayItem) -> String {
        var parts = ["Квест исчезнет из журнала, «Сегодня», карт и календаря. Вернуть его нельзя."]
        if item.isCompleted { parts.append("Он уже выполнен — полученный XP и запись в Летописи останутся.") }
        if let epic = model.epic(id: item.quest.epicId) { parts.append("Это шаг Epic «\(epic.epic.title)» — он уйдёт и из Epic.") }
        return parts.joined(separator: " ")
    }

    private func reschedule(to date: LocalDate?) {
        guard let quest = item?.quest else { return }
        let draft = QuestDraft(title: quest.title, details: quest.details ?? "", priority: quest.priority, skillId: quest.skillId,
                               dueDate: date, dueTime: date == nil ? nil : quest.dueTime, epicId: quest.epicId)
        Task {
            if await model.updateQuest(quest.id, with: draft) { isRescheduling = false }
        }
    }

    /// Предпросмотр по тем же правилам, что и начисление.
    private func rewardSummary(_ item: TodayItem, profession: Profession?) -> String {
        let snapshot = profession.map { ClassRules.snapshot(skillProfession: $0, activeProfessions: model.activeProfessions) } ?? .empty
        let grants = GrantCalculator.questCompletionGrants(
            completionId: UUID(), priority: item.quest.priority, skill: item.skill,
            skillProfessionTitle: profession?.title, snapshot: snapshot, createdAt: .now
        )
        return grants.map { grant in
            switch grant.target {
            case .attribute(let a): "\(a.code) \(Format.signedXP(grant.amount))"
            case .skill: "навык «\(item.skill?.title ?? "")» \(Format.signedXP(grant.amount)) XP"
            }
        }
        .joined(separator: " · ")
    }
}
