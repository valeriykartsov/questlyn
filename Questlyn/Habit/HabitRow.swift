import SwiftUI
import Domain
import Application

/// Строка Daily / Weekly на «Сегодня» (макет TodayV2): карточка 44 pt, квадратная отметка
/// (у недельного — пунктир), справа код основного атрибута профессии навыка.
struct HabitRow: View {
    let status: HabitStatus
    var attribute: Attribute?
    let toggle: () -> Void
    let open: () -> Void

    var body: some View {
        HStack(spacing: QSpacing.l) {
            Button(action: toggle) {
                QCheckbox(isOn: status.doneToday, dashed: status.habit.kind == .weekly)
                    .frame(width: 32, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(status.doneToday ? "Снять отметку за сегодня" : "Отметить за сегодня")

            Button(action: open) {
                HStack(spacing: QSpacing.l) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(status.habit.title)
                            .font(QFont.text(15))
                            .strikethrough(status.doneToday && status.habit.kind == .daily, color: QColor.inkSecondary)
                            .foregroundStyle(status.doneToday && status.habit.kind == .daily ? QColor.inkSecondary : QColor.ink)
                            .multilineTextAlignment(.leading)
                        if status.habit.kind == .weekly {
                            Text("На неделе · \(status.weekDone) из \(status.weekPlanned)")
                                .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let attribute {
                        Text(attribute.code).font(QFont.text(12, weight: .semibold)).foregroundStyle(attribute.accent)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, QSpacing.xs)
        .padding(.trailing, QSpacing.l)
        .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
    }
}
