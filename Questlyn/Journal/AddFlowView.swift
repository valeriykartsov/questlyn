import SwiftUI
import Domain
import Application

/// «Что добавить?» (макет JournalAdd): выбор типа внутри одного листа, затем форма.
struct AddFlowView: View {
    let model: AppModel
    var epicId: UUID?
    @Environment(\.dismiss) private var dismiss

    enum Kind: Hashable, CaseIterable {
        case quest, daily, weekly, epic

        var title: String {
            switch self {
            case .quest: "Квест"
            case .daily: "Ежедневный квест"
            case .weekly: "Недельный квест"
            case .epic: "Epic Quest"
            }
        }

        var subtitle: String {
            switch self {
            case .quest: "Разовая задача · даёт FOC и XP"
            case .daily: "Повторяется по дням · растит дисциплину"
            case .weekly: "N раз за неделю · итог в воскресенье"
            case .epic: "Большая цель из шагов · веха"
            }
        }

        var icon: String {
            switch self {
            case .quest: "checkmark.circle"
            case .daily: "sunrise"
            case .weekly: "calendar"
            case .epic: "flag"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Kind.allCases, id: \.self) { kind in
                    NavigationLink(value: kind) {
                        HStack(spacing: QSpacing.l) {
                            Image(systemName: kind.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(QColor.amber)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                                Text(kind.title).font(QFont.text(16, weight: .semibold))
                                Text(kind.subtitle).font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                            }
                        }
                        .padding(.vertical, QSpacing.xs)
                    }
                    .listRowBackground(QColor.sheet)
                }
            }
            .paperScreen()
            .navigationTitle("Что добавить?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .navigationDestination(for: Kind.self) { kind in
                switch kind {
                case .quest: QuestFormView(model: model, epicId: epicId, onDone: { dismiss() })
                case .daily: HabitFormView(model: model, kind: .daily, onDone: { dismiss() })
                case .weekly: HabitFormView(model: model, kind: .weekly, onDone: { dismiss() })
                case .epic: EpicFormView(model: model, onDone: { dismiss() })
                }
            }
        }
        .tint(QColor.amber)
    }
}
