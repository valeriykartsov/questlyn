import SwiftUI
import Domain
import Application

/// Карточка Daily / Weekly (макеты DailyCard, WeeklyCard).
struct HabitDetailView: View {
    let model: AppModel
    let habitId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    private var status: HabitStatus? { model.habit(id: habitId) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let status { content(status) } else { Text("Привычка не найдена").padding() }
            }
            .paperScreen()
            .navigationTitle(status?.habit.kind == .weekly ? "Недельный квест" : "Ежедневный квест")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Изменить") { isEditing = true } }
            }
            .sheet(isPresented: $isEditing) {
                if let habit = status?.habit {
                    NavigationStack { HabitFormView(model: model, kind: habit.kind, editing: habit) }
                }
            }
        }
    }

    private func content(_ status: HabitStatus) -> some View {
        let habit = status.habit
        let profession = model.profession(id: status.skill?.professionId)
        return VStack(alignment: .leading, spacing: QSpacing.l) {
            VStack(alignment: .leading, spacing: QSpacing.s) {
                Text(habit.title).font(QFont.title(24))
                if let details = habit.details {
                    Text(details).font(QFont.text(15)).foregroundStyle(QColor.inkSecondary)
                }
            }

            VStack(alignment: .leading, spacing: QSpacing.m) {
                HStack {
                    Text(habit.kind == .weekly ? "Неделя \(Format.week(status.today.weekStart))" : "Эта неделя")
                        .font(QFont.text(15, weight: .semibold))
                    Spacer()
                    Text("\(status.weekDone) из \(status.weekPlanned)")
                        .font(QFont.text(15, weight: .bold)).monospacedDigit()
                }
                weekStrip(status)
                Text(habit.kind == .weekly
                     ? "Засчитывается в конце недели, в воскресенье 23:59, долей выполнения. Сверх цели — без вклада в дисциплину."
                     : "Дисциплина пересчитается в понедельник по доле выполненных за неделю. Отметить можно за сегодня и за вчера.")
                    .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
            .padding(QSpacing.xl)
            .sheetCard()

            VStack(spacing: 0) {
                if habit.kind == .daily {
                    InfoRow(label: "Расписание", value: Format.weekdays(habit.weekdays))
                    Divider().overlay(QColor.line)
                    InfoRow(label: "Время", value: habit.time?.description ?? "Без времени", note: habit.time == nil ? "только в списке" : nil)
                } else {
                    InfoRow(label: "Цель", value: Format.times(habit.targetPerWeek) + " в неделю")
                }
                Divider().overlay(QColor.line)
                InfoRow(label: "Навык", value: status.skill?.title ?? "Не связан", note: profession?.title)
            }
            .padding(.horizontal, QSpacing.xl)
            .sheetCard()

            VStack(alignment: .leading, spacing: QSpacing.s) {
                Text("За каждую отметку").font(QFont.text(13, weight: .semibold)).foregroundStyle(QColor.inkSecondary)
                Text(rewardText(status, profession: profession)).font(QFont.text(15))
            }
            .padding(QSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheetCard()

            actions(status)
        }
        .padding(QSpacing.screen)
    }

    private func weekStrip(_ status: HabitStatus) -> some View {
        HStack(spacing: QSpacing.xs) {
            ForEach(status.today.weekDays, id: \.self) { day in
                let count = status.weekMarks[day] ?? 0
                let scheduled = status.habit.kind == .weekly || status.habit.isScheduled(on: day)
                let isToday = day == status.today
                VStack(spacing: QSpacing.xs) {
                    Text(day.weekday.shortTitle)
                        .font(QFont.text(11, weight: isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? QColor.ink : QColor.inkSecondary)
                    ZStack {
                        Circle()
                            .fill(count > 0 ? QColor.forest : (scheduled ? QColor.track : QColor.paper))
                            .overlay(Circle().strokeBorder(isToday ? QColor.ink : .clear, lineWidth: 1.5))
                        if count > 0 {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(QColor.sheet)
                        }
                        if count > 1 {
                            Text("\(count)").font(QFont.text(9, weight: .bold)).foregroundStyle(QColor.sheet).offset(x: 10, y: -10)
                        }
                    }
                    .frame(width: 30, height: 30)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.weekday.shortTitle): \(count > 0 ? "отмечено \(count)" : (scheduled ? "не отмечено" : "не запланировано"))")
            }
        }
    }

    private func rewardText(_ status: HabitStatus, profession: Profession?) -> String {
        guard let skill = status.skill, let profession else { return "Вклад в недельную дисциплину. Свяжите с навыком, чтобы получать XP." }
        let attrs = profession.attributes.map(\.code).joined(separator: ", ")
        return "+5 XP навыка «\(skill.title)» · 5 XP атрибутам профессии «\(profession.title)» (\(attrs)) · вклад в недельную дисциплину"
    }

    @ViewBuilder
    private func actions(_ status: HabitStatus) -> some View {
        let today = status.today
        let yesterday = today.adding(days: -1)
        let canYesterday = yesterday >= status.habit.startDate && (status.habit.kind == .weekly || status.habit.isScheduled(on: yesterday))
        VStack(spacing: QSpacing.m) {
            if status.habit.kind == .weekly {
                Button("Отметить выполнение") { Task { await model.markHabit(habitId, on: today) } }
                    .buttonStyle(PrimaryButtonStyle())
                if status.doneToday {
                    Button("Снять отметку за сегодня") { Task { await model.unmarkHabit(habitId, on: today) } }
                        .buttonStyle(SecondaryButtonStyle())
                }
            } else if status.isScheduledToday {
                if status.doneToday {
                    Button("Снять отметку за сегодня") { Task { await model.unmarkHabit(habitId, on: today) } }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("Выполнено сегодня") { Task { await model.markHabit(habitId, on: today) } }
                        .buttonStyle(PrimaryButtonStyle())
                }
            } else {
                Text("Сегодня не запланирован").font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
            }
            if canYesterday {
                let doneYesterday = (status.weekMarks[yesterday] ?? 0) > 0
                Button(doneYesterday && status.habit.kind == .daily ? "Снять отметку за вчера" : "Отметить за вчера") {
                    Task {
                        if doneYesterday && status.habit.kind == .daily { await model.unmarkHabit(habitId, on: yesterday) }
                        else { await model.markHabit(habitId, on: yesterday) }
                    }
                }
                .font(QFont.text(15, weight: .semibold))
                .foregroundStyle(QColor.amberDeep)
                .frame(minHeight: 44)
            }
        }
    }
}
