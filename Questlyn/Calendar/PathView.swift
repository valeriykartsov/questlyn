import SwiftUI
import Domain
import Application

/// «Путь героя» (9.4, макеты 9.5–9.6): Гант дня. Фон — зоны «Привал / Фарм / Приключение»,
/// квесты с датой и временем — полосы (тянуть — время, край — длительность), события календарей — только чтение, Epic — акцентные линии.
struct PathTimeline: View {
    enum Axis { case vertical, horizontal }

    let model: AppModel
    let day: LocalDate
    let events: [AgendaEvent]
    let axis: Axis
    /// Масштаб времени щипком (0,5…3).
    var zoom: CGFloat = 1

    static func unit(_ axis: Axis, zoom: CGFloat) -> CGFloat { (axis == .vertical ? 44 : 64) * zoom }
    /// Точек на час.
    private var unit: CGFloat { Self.unit(axis, zoom: zoom) }
    static let space = "pathTimeline"
    private var length: CGFloat { unit * 24 }
    private let questLane: CGFloat = 0.62

    struct Bar: Identifiable {
        let id: UUID
        let title: String
        let start: Double
        let minutes: Int
        let isDone: Bool
        let epicId: UUID?
        var column = 0
    }

    /// Квесты дня со временем; без длительности — 30 минут (02, 12.11.2026).
    private var bars: [Bar] {
        var result = (model.overview?.journal ?? []).compactMap { item -> Bar? in
            guard item.quest.dueDate == day, let time = item.quest.dueTime, let minutes = QuestTiming.effectiveDuration(item.quest) else { return nil }
            return Bar(id: item.quest.id, title: item.quest.title, start: Double(time.hour) + Double(time.minute) / 60,
                       minutes: minutes, isDone: item.isCompleted, epicId: item.quest.epicId)
        }
        .sorted { $0.start < $1.start }
        // Пересекающиеся полосы — в соседние колонки.
        var ends: [Double] = []
        for index in result.indices {
            let end = result[index].start + Double(result[index].minutes) / 60
            if let free = ends.firstIndex(where: { $0 <= result[index].start }) { result[index].column = free; ends[free] = end }
            else { result[index].column = ends.count; ends.append(end) }
        }
        return result
    }

    private var dayStart: Date { VitalsCalculator.date(day, LocalTime(hour: 0, minute: 0)!, timeZone: .current) }
    private func hours(_ date: Date) -> Double { min(24, max(0, date.timeIntervalSince(dayStart) / 3600)) }

    @State private var drag: (id: UUID, delta: CGFloat, resize: Bool)?

    var body: some View {
        GeometryReader { proxy in
            let cross = axis == .vertical ? proxy.size.width : proxy.size.height
            ZStack(alignment: .topLeading) {
                zones(cross: cross)
                hourLines(cross: cross)
                epicLines(cross: cross)
                eventBlocks(cross: cross)
                questBars(cross: cross)
                nowLine(cross: cross)
            }
            // Жесты меряются в неподвижной системе ленты: полоса двигается под пальцем без дрожания.
            .coordinateSpace(.named(Self.space))
            .frame(width: axis == .vertical ? cross : length, height: axis == .vertical ? length : cross, alignment: .topLeading)
        }
        .frame(width: axis == .vertical ? nil : length, height: axis == .vertical ? length : nil)
    }

    // MARK: Геометрия

    /// Прямоугольник по времени (часы) и доле поперёк (0…1).
    private func rect(from: Double, to: Double, crossFrom: CGFloat, crossTo: CGFloat, cross: CGFloat) -> CGRect {
        let a = CGFloat(from) * unit, b = CGFloat(to) * unit
        return axis == .vertical
            ? CGRect(x: crossFrom * cross, y: a, width: (crossTo - crossFrom) * cross, height: b - a)
            : CGRect(x: a, y: crossFrom * cross, width: b - a, height: (crossTo - crossFrom) * cross)
    }

    private func zones(cross: CGFloat) -> some View {
        ForEach(0..<96, id: \.self) { quarter in
            let moment = dayStart.addingTimeInterval(Double(quarter) * 900)
            let r = rect(from: Double(quarter) / 4, to: Double(quarter + 1) / 4, crossFrom: 0, crossTo: 1, cross: cross)
            DayRhythmBar.color(model.movementMode(at: moment)).opacity(0.75)
                .frame(width: r.width + 0.5, height: r.height + 0.5).offset(x: r.minX, y: r.minY)
        }
        .accessibilityHidden(true)
    }

    private func hourLines(cross: CGFloat) -> some View {
        ForEach(0..<24, id: \.self) { hour in
            let r = rect(from: Double(hour), to: Double(hour), crossFrom: 0, crossTo: 1, cross: cross)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(QColor.ink.opacity(0.08))
                    .frame(width: axis == .vertical ? r.width : 1, height: axis == .vertical ? 1 : r.height)
                Text(String(format: "%02d:00", hour)).font(QFont.text(10)).foregroundStyle(QColor.inkSecondary)
                    .padding(.leading, 4).padding(.top, 2)
            }
            .offset(x: r.minX, y: r.minY)
        }
        .accessibilityHidden(true)
    }

    private func epicLines(cross: CGFloat) -> some View {
        let groups = Dictionary(grouping: bars.filter { $0.epicId != nil }) { $0.epicId! }
        return ForEach(Array(groups.keys), id: \.self) { epicId in
            let steps = groups[epicId] ?? []
            let from = steps.map(\.start).min() ?? 0
            let to = steps.map { $0.start + Double($0.minutes) / 60 }.max() ?? from
            let r = rect(from: from, to: to, crossFrom: 0.115, crossTo: 0.125, cross: cross)
            RoundedRectangle(cornerRadius: 2).fill(QColor.amber)
                .frame(width: max(r.width, 4), height: max(r.height, 4)).offset(x: r.minX, y: r.minY)
                .accessibilityLabel("Epic «\(model.epic(id: epicId)?.epic.title ?? "")»: \(MapText.time(from))–\(MapText.time(to))")
        }
    }

    private func eventBlocks(cross: CGFloat) -> some View {
        ForEach(events.filter { !$0.isAllDay }) { event in
            let from = hours(event.start), to = max(hours(event.end), hours(event.start) + 0.4)
            let r = rect(from: from, to: to, crossFrom: questLane + 0.03, crossTo: 0.98, cross: cross)
            Text(event.title).font(QFont.text(10, weight: .semibold)).foregroundStyle(QColor.ink).lineLimit(2)
                .padding(3)
                .frame(width: r.width, height: r.height, alignment: .topLeading)
                .background(QColor.coolFill.opacity(0.95), in: RoundedRectangle(cornerRadius: 5))
                .overlay(alignment: axis == .vertical ? .leading : .top) {
                    Rectangle().fill(Color(hex: model.calendarColor(event.calendarId)))
                        .frame(width: axis == .vertical ? 3 : nil, height: axis == .vertical ? nil : 3)
                }
                .offset(x: r.minX, y: r.minY)
                .accessibilityLabel("Событие \(event.title), \(event.start.formatted(date: .omitted, time: .shortened))")
        }
    }

    private func questBars(cross: CGFloat) -> some View {
        let columns = max(1, (bars.map(\.column).max() ?? 0) + 1)
        return ForEach(bars) { bar in
            let width = (questLane - 0.14) / CGFloat(columns)
            let crossFrom = 0.14 + width * CGFloat(bar.column)
            let isDragged = drag?.id == bar.id
            let deltaHours = isDragged ? Double(drag!.delta / unit) : 0
            let start = isDragged && !drag!.resize ? bar.start + deltaHours : bar.start
            let minutes = isDragged && drag!.resize ? Self.snapDuration(Double(bar.minutes) + deltaHours * 60) : bar.minutes
            let r = rect(from: start, to: start + Double(max(minutes, 20)) / 60, crossFrom: crossFrom, crossTo: crossFrom + width - 0.01, cross: cross)
            barView(bar, start: start, minutes: minutes)
                .frame(width: r.width, height: r.height, alignment: .topLeading)
                .offset(x: r.minX, y: r.minY)
                .gesture(bar.isDone ? nil : move(bar))
                .overlay(alignment: axis == .vertical ? .bottom : .trailing) {
                    if !bar.isDone {
                        Capsule().fill(QColor.sheet.opacity(0.85))
                            .frame(width: axis == .vertical ? 24 : 4, height: axis == .vertical ? 4 : 18)
                            .padding(4)
                            .frame(width: axis == .vertical ? r.width : 20, height: axis == .vertical ? 20 : r.height)
                            .contentShape(Rectangle())
                            .offset(x: r.minX, y: r.minY)
                            .highPriorityGesture(resize(bar))
                            .accessibilityHidden(true)
                    }
                }
        }
    }

    private func barView(_ bar: Bar, start: Double, minutes: Int) -> some View {
        let fill: Color = bar.isDone ? Color(light: 0xDCEBE2, dark: 0x1F3A30) : bar.epicId != nil ? QColor.amber : QColor.ink
        let ink: Color = bar.isDone ? QColor.forest : QColor.sheet
        return VStack(alignment: .leading, spacing: 1) {
            Text(bar.title + (bar.isDone ? " ✓" : "")).font(QFont.text(12, weight: .bold)).lineLimit(1)
            Text("\(MapText.time(start)) · \(WeekMapRenderer.duration(minutes))").font(QFont.text(10)).lineLimit(1).opacity(0.85)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(fill, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(bar.isDone ? QColor.forest : .clear))
        .accessibilityElement(children: .combine)
        .accessibilityHint(bar.isDone ? "Выполнен — не переносится" : "Перетащите, чтобы перенести")
    }

    // MARK: Перетаскивание

    private func along(_ value: DragGesture.Value) -> CGFloat { axis == .vertical ? value.translation.height : value.translation.width }

    private func move(_ bar: Bar) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { drag = (bar.id, along($0), false) }
            .onEnded { value in
                let hours = bar.start + Double(along(value) / unit)
                let snapped = min(23.75, max(0, (hours * 4).rounded() / 4))
                drag = nil
                save(bar, start: snapped, minutes: bar.minutes)
            }
    }

    private func resize(_ bar: Bar) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { drag = (bar.id, along($0), true) }
            .onEnded { value in
                let minutes = Self.snapDuration(Double(bar.minutes) + Double(along(value) / unit) * 60)
                drag = nil
                save(bar, start: bar.start, minutes: minutes)
            }
    }

    /// Ближайшая допустимая длительность (15–180 мин).
    static func snapDuration(_ minutes: Double) -> Int {
        QuestTiming.durations.min { abs(Double($0) - minutes) < abs(Double($1) - minutes) } ?? QuestTiming.defaultDuration
    }

    /// Перенос меняет квест — журнал, «Сегодня» и календарь «Questlyn» обновятся сами.
    private func save(_ bar: Bar, start: Double, minutes: Int) {
        guard let quest = model.questItem(id: bar.id)?.quest else { return }
        var draft = QuestDraft(quest: quest)
        let total = Int((start * 60).rounded())
        draft.dueTime = LocalTime(hour: total / 60, minute: total % 60)
        draft.durationMinutes = minutes
        guard draft.dueTime != quest.dueTime || draft.durationMinutes != quest.durationMinutes else { return }
        Task { _ = await model.updateQuest(bar.id, with: draft) }
    }

    @ViewBuilder private func nowLine(cross: CGFloat) -> some View {
        if day == model.today {
            let now = hours(.now)
            let r = rect(from: now, to: now, crossFrom: 0, crossTo: 1, cross: cross)
            Rectangle().fill(QColor.hp)
                .frame(width: axis == .vertical ? r.width : 2, height: axis == .vertical ? 2 : r.height)
                .offset(x: r.minX, y: r.minY)
                .accessibilityLabel("Сейчас \(MapText.time(now))")
        }
    }
}

/// «Путь» повёрнутый кнопкой (макет 9.6): низ телефона — к левой грани, время идёт слева направо.
/// Приложение остаётся вертикальным: поворачивается сам экран «Пути»; при выходе поворот сбрасывается.
struct PathLandscapeView: View {
    let model: AppModel
    let day: LocalDate
    let events: [AgendaEvent]
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(width: proxy.size.height, height: proxy.size.width)
            VStack(alignment: .leading, spacing: QSpacing.s) {
                HStack {
                    Button { dismiss() } label: {
                        Label("Вертикально", systemImage: "chevron.left").font(QFont.text(13, weight: .semibold))
                            .padding(.horizontal, QSpacing.l).frame(height: 36)
                            .background(QColor.sheet, in: Capsule())
                            .overlay(Capsule().strokeBorder(QColor.lineStrong))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(QColor.ink)
                    Spacer()
                    Text(Format.longDay(day.date ?? .now)).font(QFont.text(15, weight: .bold))
                    Spacer()
                    Text("«Путь героя»").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                }
                ScrollViewReader { reader in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            HStack(spacing: 0) {
                                ForEach(0..<24, id: \.self) { Color.clear.frame(width: 64 * zoom, height: size.height - 90).id($0) }
                            }
                            PathTimeline(model: model, day: day, events: events, axis: .horizontal, zoom: zoom)
                                .frame(width: 64 * zoom * 24, height: size.height - 90)
                        }
                    }
                    .scrollEdgeEffectHidden(true, for: .all)
                    .simultaneousGesture(PathZoom.gesture(zoom: $zoom, base: $zoomBase))
                    .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.card))
                    .clipShape(RoundedRectangle(cornerRadius: QRadius.card))
                    .onAppear { reader.scrollTo(7, anchor: .leading) }
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, QSpacing.l)
            .frame(width: size.width, height: size.height)
            .rotationEffect(.degrees(90))
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(QColor.paper.ignoresSafeArea())
        .ignoresSafeArea()
    }
}

/// Масштаб «Пути» щипком: растянуть — подробнее, сжать — больше часов на экране.
enum PathZoom {
    static let range: ClosedRange<CGFloat> = 0.5...3

    static func gesture(zoom: Binding<CGFloat>, base: Binding<CGFloat>) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in zoom.wrappedValue = min(range.upperBound, max(range.lowerBound, base.wrappedValue * value.magnification)) }
            .onEnded { _ in base.wrappedValue = zoom.wrappedValue }
    }
}
