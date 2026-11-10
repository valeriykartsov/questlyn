import SwiftUI
import Domain
import Application

/// «Календарь» (макет 3.6): повестка из Apple Calendar и квестов с датой. Карта дня — этап 6B.
struct CalendarView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    private var days: [LocalDate] {
        (-AppModel.agendaDaysBack...AppModel.agendaDaysForward).map { model.today.adding(days: $0) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: QSpacing.l) {
                    header
                    if !model.isCalendarAuthorized { connectCard }
                    ForEach(days, id: \.self) { day in
                        daySection(day).id(day)
                    }
                }
                .padding(.horizontal, QSpacing.screen)
                .padding(.top, QSpacing.l)
                .padding(.bottom, 96)
            }
            .onAppear {
                model.loadAgenda()
                // Без доступа к календарю наверху карточка подключения — её не прокручиваем.
                if model.isCalendarAuthorized { proxy.scrollTo(model.today, anchor: .top) }
            }
        }
        .paperScreen()
        .refreshable {
            await model.reload()
            model.loadAgenda()
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.loadAgenda() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: QSpacing.xxs) {
            Text(model.today.date.map { $0.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "ru_RU"))).capitalized } ?? "")
                .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
            Text("Календарь").font(QFont.title(30))
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            Text("Подключите Apple Calendar").font(QFont.text(15, weight: .semibold))
            Text("События только читаются и не покидают устройство. Событие в календаре — не выполненное действие: наград за него нет.")
                .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
            Button("Подключить") { Task { await model.connectCalendar() } }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(QSpacing.xl)
        .sheetCard()
    }

    private func events(on day: LocalDate) -> [AgendaEvent] {
        model.agendaEvents.filter { event in
            let start = LocalDate(event.start, timeZone: .current)
            // Событие на несколько дней видно в каждом своём дне (конец не включается).
            let end = LocalDate(event.end.addingTimeInterval(-1), timeZone: .current)
            return start <= day && day <= max(start, end)
        }
    }

    private func quests(on day: LocalDate) -> [TodayItem] {
        (model.overview?.journal ?? []).filter { $0.quest.dueDate == day }
            .sorted { ($0.quest.dueTime?.description ?? "99", $0.quest.createdAt) < ($1.quest.dueTime?.description ?? "99", $1.quest.createdAt) }
    }

    @ViewBuilder
    private func daySection(_ day: LocalDate) -> some View {
        let dayEvents = events(on: day)
        let dayQuests = quests(on: day)
        VStack(alignment: .leading, spacing: QSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title(day)).font(QFont.title(day == model.today ? 20 : 17))
                    .foregroundStyle(day < model.today ? QColor.inkSecondary : QColor.ink)
                Spacer()
                if dayEvents.isEmpty && dayQuests.isEmpty {
                    Text("свободно").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                }
            }
            if !dayEvents.isEmpty || !dayQuests.isEmpty {
                VStack(spacing: 0) {
                    ForEach(dayEvents) { event in row(event: event, day: day) }
                    ForEach(dayQuests) { item in row(quest: item) }
                }
                .padding(.horizontal, QSpacing.xl)
                .sheetCard()
            }
        }
    }

    private func title(_ day: LocalDate) -> String {
        let prefix = day == model.today ? "Сегодня" : day == model.today.adding(days: 1) ? "Завтра" : day == model.today.adding(days: -1) ? "Вчера" : nil
        guard let date = day.date else { return day.description }
        if let prefix { return "\(prefix), \(date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "ru_RU"))))" }
        return Format.longDay(date)
    }

    private func row(event: AgendaEvent, day: LocalDate) -> some View {
        HStack(alignment: .top, spacing: QSpacing.l) {
            Group {
                if event.isAllDay || LocalDate(event.start, timeZone: .current) != day {
                    Text("Весь день")
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(event.start.formatted(date: .omitted, time: .shortened))
                        Text(event.end.formatted(date: .omitted, time: .shortened)).foregroundStyle(QColor.inkSecondary)
                    }
                }
            }
            .font(QFont.text(12, weight: .semibold))
            .monospacedDigit()
            .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                Text(event.title).font(QFont.text(15))
                let attendees = event.attendees > 0 ? "участников: \(event.attendees)" : nil
                let offMap = event.isAllDay ? "вне карты" : nil
                Text([event.calendarTitle, attendees, offMap].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, QSpacing.m)
    }

    private func row(quest item: TodayItem) -> some View {
        HStack(alignment: .top, spacing: QSpacing.l) {
            Text(item.quest.dueTime?.description ?? "—")
                .font(QFont.text(12, weight: .semibold)).monospacedDigit()
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                Text(item.quest.title).font(QFont.text(15)).strikethrough(item.isCompleted, color: QColor.inkSecondary)
                Text(item.isCompleted ? "Квест · выполнен" : item.quest.dueTime == nil ? "Квест · без времени, вне карты" : "Квест")
                    .font(QFont.text(12)).foregroundStyle(QColor.amberDeep)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, QSpacing.m)
    }
}
