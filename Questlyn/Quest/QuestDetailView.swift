import SwiftUI
import Domain
import Application

/// Карточка квеста (макет QuestDetail). «Изменить» и «Перенести» — этап 2.7.
struct QuestDetailView: View {
    let model: AppModel
    let questId: UUID
    let onComplete: (CompletionReport) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false

    private var item: TodayItem? { model.overview?.items.first { $0.quest.id == questId } }

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
            }
        }
        .padding(QSpacing.screen)
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
