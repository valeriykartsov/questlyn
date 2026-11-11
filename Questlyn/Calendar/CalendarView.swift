import SwiftUI
import Domain
import Application

/// «Календарь» (макеты 8.13–8.14): неделя или месяц, события Apple Calendar и квесты с датой.
struct CalendarView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    enum Mode: String, CaseIterable { case week = "Неделя", month = "Месяц" }

    @AppStorage("calendar.mode") private var mode: Mode = .week
    @State private var anchor: LocalDate?
    @State private var selected: LocalDate?

    private var today: LocalDate { model.today }
    private var current: LocalDate { anchor ?? today }
    private var weekDays: [LocalDate] { (0..<7).map { current.weekStart.adding(days: $0) } }
    private var monthStart: LocalDate { LocalDate(year: current.year, month: current.month, day: 1) }
    private var monthDays: [LocalDate] {
        let days = Calendar(identifier: .gregorian).range(of: .day, in: .month, for: monthStart.date ?? .now)?.count ?? 30
        return (0..<days).map { monthStart.adding(days: $0) }
    }
    private var range: (LocalDate, LocalDate) {
        mode == .week ? (weekDays[0], weekDays[6]) : (monthStart, monthDays.last ?? monthStart)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.l) {
                ScreenHeader(model: model, subtitle: subtitle, title: "Календарь")
                modePicker
                pager
                if !model.isCalendarAuthorized { connectCard }
                if mode == .week { weekList } else { monthGrid; dayCard(selected ?? today) }
                Text("Цветная полоса — профессия или навык, к которым привязан календарь (только оформление, XP не даёт). Настройки — «Настройки › Календари».")
                    .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
            .padding(.horizontal, QSpacing.screen)
            .padding(.top, QSpacing.l)
            .padding(.bottom, 96)
        }
        .paperScreen()
        .onAppear(perform: reload)
        .onChange(of: mode) { reload() }
        .onChange(of: anchor) { reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        .refreshable {
            await model.reload()
            reload()
        }
    }

    private func reload() { model.loadAgenda(from: range.0, through: range.1) }

    private var subtitle: String {
        // «Ноябрь 2026» — без «г.».
        (current.date.map { $0.formatted(.dateTime.month(.wide).locale(Locale(identifier: "ru_RU"))).capitalized } ?? "") + " \(current.year)"
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(Mode.allCases, id: \.self) { item in
                let isOn = mode == item
                Button { withAnimation(.snappy) { mode = item } } label: {
                    Text(item.rawValue)
                        .font(QFont.text(14, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(isOn ? QColor.sheet : QColor.ink)
                        .background(isOn ? QColor.ink : Color.clear, in: RoundedRectangle(cornerRadius: QRadius.small))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
        .overlay(RoundedRectangle(cornerRadius: QRadius.control).strokeBorder(QColor.line))
    }

    private var pager: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 36) }
                .accessibilityLabel(mode == .week ? "Предыдущая неделя" : "Предыдущий месяц")
            Spacer()
            Button { anchor = nil; selected = nil } label: { Text(pagerTitle).font(QFont.text(15, weight: .semibold)) }
                .accessibilityHint("Вернуться к сегодня")
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 36) }
                .accessibilityLabel(mode == .week ? "Следующая неделя" : "Следующий месяц")
        }
        .buttonStyle(.plain)
        .foregroundStyle(QColor.ink)
    }

    private var pagerTitle: String {
        let ru = Locale(identifier: "ru_RU")
        if mode == .month { return monthStart.date?.formatted(.dateTime.month(.wide).locale(ru)).capitalized ?? "" }
        guard let first = weekDays.first?.date, let last = weekDays.last?.date else { return "" }
        let tail = last.formatted(.dateTime.day().month(.wide).locale(ru))
        return weekDays[0].month == weekDays[6].month ? "\(weekDays[0].day)–\(tail)" : "\(first.formatted(.dateTime.day().month(.abbreviated).locale(ru))) – \(tail)"
    }

    private func shift(_ step: Int) {
        if mode == .week {
            anchor = current.adding(days: 7 * step)
        } else {
            var parts = DateComponents(year: monthStart.year, month: monthStart.month + step, day: 1)
            if parts.month! < 1 { parts.year! -= 1; parts.month = 12 }
            if parts.month! > 12 { parts.year! += 1; parts.month = 1 }
            anchor = LocalDate(year: parts.year!, month: parts.month!, day: 1)
        }
        selected = nil
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            Text("Подключите Apple Calendar").font(QFont.text(15, weight: .semibold))
            Text("События только читаются и не покидают устройство. Событие в календаре — не выполненное действие: наград за него нет.")
                .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
            Button("Подключить") { Task { await model.connectCalendar(); reload() } }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(QSpacing.xl)
        .sheetCard()
    }

    // MARK: Данные дня

    private func events(on day: LocalDate) -> [AgendaEvent] {
        model.agendaEvents.filter { event in
            let start = LocalDate(event.start, timeZone: .current)
            let end = LocalDate(event.end.addingTimeInterval(-1), timeZone: .current)
            return start <= day && day <= max(start, end)
        }
    }

    private func quests(on day: LocalDate) -> [TodayItem] {
        (model.overview?.journal ?? []).filter { $0.quest.dueDate == day }
            .sorted { ($0.quest.dueTime?.description ?? "99", $0.quest.createdAt) < ($1.quest.dueTime?.description ?? "99", $1.quest.createdAt) }
    }

    // MARK: Неделя

    private var weekList: some View {
        VStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                HStack(alignment: .top, spacing: QSpacing.l) {
                    VStack(spacing: 0) {
                        Text(day.weekday.shortTitle).font(QFont.text(11))
                        Text("\(day.day)").font(QFont.text(16, weight: .bold))
                    }
                    .foregroundStyle(day == today ? QColor.amber : (day < today ? QColor.inkSecondary : QColor.ink))
                    .frame(width: 36)
                    dayRows(day, compact: true)
                }
                .padding(.vertical, QSpacing.m)
                .padding(.horizontal, QSpacing.l)
                if day != weekDays.last { Divider().overlay(QColor.line) }
            }
        }
        .sheetCard()
    }

    @ViewBuilder private func dayRows(_ day: LocalDate, compact: Bool) -> some View {
        let dayEvents = events(on: day), dayQuests = quests(on: day)
        VStack(alignment: .leading, spacing: QSpacing.s) {
            if dayEvents.isEmpty && dayQuests.isEmpty {
                Text("свободно").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
            ForEach(dayEvents) { event in
                let link = model.calendarLink(for: event)
                row(time: event.isAllDay || LocalDate(event.start, timeZone: .current) != day ? "Весь день" : event.start.formatted(date: .omitted, time: .shortened),
                    title: event.title,
                    note: [link?.label ?? event.calendarTitle, event.attendees > 0 ? "участников: \(event.attendees)" : nil].compactMap { $0 }.joined(separator: " · "),
                    color: Color(hex: link?.color ?? model.calendarColor(event.calendarId)), struck: false)
            }
            ForEach(dayQuests) { item in
                row(time: item.quest.dueTime?.description ?? "—", title: item.quest.title,
                    note: item.isCompleted ? "Квест · выполнен" : (model.calendarPreferences.sendQuests ? "Квест → «Questlyn»" : "Квест"),
                    color: QColor.amberDeep, struck: item.isCompleted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(time: String, title: String, note: String, color: Color, struck: Bool) -> some View {
        HStack(alignment: .top, spacing: QSpacing.m) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            Text(time).font(QFont.text(12, weight: .bold)).monospacedDigit().frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(QFont.text(14)).strikethrough(struck, color: QColor.inkSecondary)
                if !note.isEmpty { Text(note).font(QFont.text(11)).foregroundStyle(QColor.inkSecondary) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Месяц

    private var monthGrid: some View {
        let offset = monthStart.weekday.rawValue - 1
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return VStack(spacing: QSpacing.xs) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Weekday.allCases, id: \.self) { Text($0.shortTitle).font(QFont.text(11)).foregroundStyle(QColor.inkSecondary) }
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 46) }
                ForEach(monthDays, id: \.self) { day in
                    let isSelected = day == (selected ?? today)
                    let colors = (events(on: day).map { Color(hex: model.calendarLink(for: $0)?.color ?? model.calendarColor($0.calendarId)) }
                                  + quests(on: day).map { _ in QColor.amberDeep }).prefix(4)
                    Button { selected = day } label: {
                        VStack(spacing: 3) {
                            Text("\(day.day)").font(QFont.text(14, weight: .semibold))
                                .foregroundStyle(isSelected ? QColor.sheet : (day == today ? QColor.amber : QColor.ink))
                            HStack(spacing: 2) {
                                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in Circle().fill(color).frame(width: 5, height: 5) }
                            }
                            .frame(height: 5)
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(isSelected ? QColor.ink : Color.clear, in: RoundedRectangle(cornerRadius: QRadius.small))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(day.day), событий: \(colors.count)")
                }
            }
        }
        .padding(QSpacing.m)
        .sheetCard()
    }

    private func dayCard(_ day: LocalDate) -> some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            Text(day.date.map { Format.longDay($0) } ?? "").font(QFont.text(14, weight: .bold))
            dayRows(day, compact: false)
        }
        .padding(QSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheetCard()
    }
}
