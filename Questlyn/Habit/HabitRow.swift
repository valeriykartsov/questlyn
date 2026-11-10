import SwiftUI
import Domain
import Application

/// Строка Daily / Weekly: отметка за сегодня, название, прогресс недели.
struct HabitRow: View {
    let status: HabitStatus
    let toggle: () -> Void
    let open: () -> Void

    var body: some View {
        HStack(spacing: QSpacing.l) {
            Button(action: toggle) {
                Image(systemName: status.doneToday ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(status.doneToday ? QColor.forest : QColor.lineStrong)
                    .frame(width: 32, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(status.doneToday ? "Снять отметку за сегодня" : "Отметить за сегодня")

            Button(action: open) {
                HStack {
                    VStack(alignment: .leading, spacing: QSpacing.xxs) {
                        Text(status.habit.title)
                            .font(QFont.text(15, weight: .semibold))
                            .foregroundStyle(QColor.ink)
                            .multilineTextAlignment(.leading)
                        Text(subtitle)
                            .font(QFont.text(12))
                            .foregroundStyle(QColor.inkSecondary)
                    }
                    Spacer()
                    if status.habit.kind == .weekly {
                        Text("\(status.weekDone)/\(status.weekPlanned)")
                            .font(QFont.text(13, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(status.weekDone >= status.weekPlanned ? QColor.forest : QColor.inkSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, QSpacing.l)
        .padding(.vertical, QSpacing.s)
    }

    private var subtitle: String {
        var parts: [String] = []
        switch status.habit.kind {
        case .daily:
            if let time = status.habit.time { parts.append(time.description) }
        case .weekly:
            parts.append("На неделе · \(status.weekDone) из \(status.weekPlanned)")
        }
        if let skill = status.skill { parts.append(skill.title) }
        return parts.isEmpty ? "Без навыка" : parts.joined(separator: " · ")
    }
}
