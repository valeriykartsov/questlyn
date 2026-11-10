import SwiftUI
import Domain
import Application

/// Квадратная отметка 22–24 pt со скруглением 6 (макеты TodayV2, Journal).
struct QCheckbox: View {
    let isOn: Bool
    var dashed = false
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: QRadius.chip)
            .fill(isOn ? QColor.forest : .clear)
            .overlay {
                if isOn {
                    Image(systemName: "checkmark").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(QColor.sheet)
                } else {
                    RoundedRectangle(cornerRadius: QRadius.chip)
                        .strokeBorder(QColor.ink, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 2] : []))
                }
            }
            .frame(width: size, height: size)
    }
}

/// Заголовок раздела: капслок 12 pt с разрядкой (макет Journal).
struct CapsHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(QFont.text(12, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(QColor.inkSecondary)
            Spacer()
            if let trailing {
                Text(trailing).font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
        }
        .padding(.top, QSpacing.xxs)
    }
}

/// Полоски приоритета: 3 столбика 3 pt, закрашено 1 / 2 / 3.
struct PriorityBars: View {
    let priority: QuestPriority

    var body: some View {
        let filled = priority.multiplierInHalves
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= filled ? QColor.amber : Color(hex: 0xD8CCB5))
                    .frame(width: 3, height: CGFloat(2 + 3 * i))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Приоритет: \(Format.priority(priority))")
    }
}

/// 7 точек недели (макет Journal): сегодня — всегда чернила (отметка видна в квадрате слева),
/// выполнено — лес, пропущено — песок, впереди и не запланировано — контур.
struct WeekDots: View {
    let status: HabitStatus

    var body: some View {
        HStack(spacing: 3) {
            ForEach(status.today.weekDays, id: \.self) { day in
                let done = status.marks(on: day) > 0
                let scheduled = status.habit.kind == .weekly || status.habit.isScheduled(on: day)
                Group {
                    if day == status.today {
                        RoundedRectangle(cornerRadius: 2).fill(QColor.ink)
                    } else if done {
                        RoundedRectangle(cornerRadius: 2).fill(QColor.forest)
                    } else if day < status.today && scheduled {
                        RoundedRectangle(cornerRadius: 2).fill(QColor.lineStrong)
                    } else {
                        RoundedRectangle(cornerRadius: 2).strokeBorder(QColor.lineStrong, lineWidth: 1)
                    }
                }
                .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

extension Attribute {
    /// Цвет кода атрибута в строках привычек: тело — лес, ум — янтарь (макет TodayV2).
    var accent: Color {
        switch self {
        case .strength, .endurance: QColor.forest
        default: QColor.amberDeep
        }
    }
}
