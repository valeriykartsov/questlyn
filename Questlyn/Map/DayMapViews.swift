import SwiftUI
import Domain
import Application

enum MapText {
    static func season(_ map: DayMap) -> String {
        map.season == .autumn && map.date.month == 11 ? "Поздняя осень" : map.season.title
    }

    static func weather(_ map: DayMap, lastMood: MoodEntry?) -> String {
        guard let mood = lastMood, mood.localDate == map.date else { return map.weather.title }
        return "\(map.weather.title) · по отметке \(mood.at.formatted(date: .omitted, time: .shortened))"
    }

    static func time(_ hour: Double) -> String {
        let minutes = Int((hour * 60).rounded())
        return String(format: "%02d:%02d", min(23, minutes / 60), minutes % 60)
    }

    static func timeAxis() -> some View {
        HStack {
            ForEach(["00:00", "06:00", "12:00", "18:00", "23:59"], id: \.self) { label in
                Text(label)
                if label != "23:59" { Spacer() }
            }
        }
        .font(QFont.text(10))
        .foregroundStyle(QColor.inkSecondary)
        .monospacedDigit()
    }
}

/// Миниатюра дня на «Сегодня» (холст 8.9): 2D-дорога 00:00–23:59, герой в «сейчас».
struct DayStripCard: View {
    let model: AppModel
    let open: () -> Void

    var body: some View {
        let map = model.dayMap(for: model.today)
        VStack(alignment: .leading, spacing: QSpacing.s) {
            Button(action: open) {
                GeometryReader { proxy in
                    let scale = proxy.size.width / CGFloat(PixelMapRenderer.stripSize.width)
                    ZStack(alignment: .topLeading) {
                        if let image = PixelMapRenderer.strip(map, appearance: model.hero?.appearance, accent: model.heroAccent) {
                            Image(decorative: image, scale: 1).resizable().interpolation(.none)
                        }
                        Text("\(MapText.season(map)) · \(MapText.weather(map, lastMood: model.lastMood))")
                            .font(QFont.text(10)).foregroundStyle(QColor.inkSecondary)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(QColor.sheet.opacity(0.92), in: RoundedRectangle(cornerRadius: 7))
                            .padding(6)
                        if let hour = map.heroHour {
                            // Под героем: буква ранга и время (11.11.2026). Без ранга — тире.
                            let x = (4 + hour / 24 * Double(PixelMapRenderer.stripSize.width - 8)) * scale
                            Text("\(model.progress.rank?.letter ?? "—") · \(MapText.time(hour))")
                                .font(QFont.text(10, weight: .bold))
                                .foregroundStyle(Color(hex: 0x1F2A44))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Color(hex: 0xE2A04A), in: RoundedRectangle(cornerRadius: 7))
                                .fixedSize()
                                .position(x: min(max(x, 30), proxy.size.width - 30), y: 46.5 * scale)
                                .accessibilityLabel("Ранг \(AdventurerRank.title(for: model.progress.rank)), сейчас \(MapText.time(hour))")
                        }
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .background(QColor.sheet.opacity(0.92), in: Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(6)
                    }
                }
                .aspectRatio(CGFloat(PixelMapRenderer.stripSize.width) / CGFloat(PixelMapRenderer.stripSize.height), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: QRadius.card))
            }
            .buttonStyle(.plain)
            .foregroundStyle(QColor.ink)
            .accessibilityLabel("Карта дня")
            .accessibilityHint("Открыть большую карту с листанием дней")
            MapText.timeAxis()
            upcoming(map)
        }
    }

    /// «Дальше по дороге»: все события и квесты дня по порядку; прошедшие — бледнее (11.11.2026).
    @ViewBuilder private func upcoming(_ map: DayMap) -> some View {
        let now = map.heroHour ?? 0
        let all = (map.settlements.map { ($0.startHour, $0.titles.joined(separator: " + "),
                                          $0.kind == .city ? (($0.density > 1) ? "город, пересекаются" : "город") : "деревня",
                                          false, $0.endHour <= now) }
            + map.questMarkers.map { ($0.hour, $0.title, $0.isDone ? "квест ✓" : "квест", true, $0.isDone || $0.hour < now) })
            .sorted { $0.0 < $1.0 }
        if !all.isEmpty || !map.offMap.isEmpty {
            VStack(alignment: .leading, spacing: QSpacing.xs) {
                if !all.isEmpty {
                    HStack {
                        Text("Дальше по дороге").font(QFont.text(12, weight: .bold))
                        Spacer()
                        Text("\(all.count) за день").font(QFont.text(11)).foregroundStyle(QColor.inkSecondary)
                    }
                    ForEach(Array(all.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: QSpacing.s) {
                            Text(MapText.time(item.0)).monospacedDigit().fontWeight(.semibold)
                            Text(item.1).lineLimit(1)
                            Text("· \(item.2)").foregroundStyle(item.3 ? QColor.amberDeep : QColor.inkSecondary)
                        }
                        .font(QFont.text(12))
                        .opacity(item.4 ? 0.5 : 1)
                    }
                }
                if !map.offMap.isEmpty {
                    Text("Вне карты: " + map.offMap.joined(separator: " · "))
                        .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary).lineLimit(3)
                }
            }
            .padding(.horizontal, QSpacing.l)
            .padding(.vertical, QSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheetCard()
        }
    }
}

/// Большая карта — путь за неделю (02 от 11.11.2026): изометрия, привалы сна, ползунок по дороге, листание недель.
struct MapOverviewView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var weekStart: LocalDate
    /// Час недели в точке ползунка (0…168).
    @State private var position: Double = 0
    @State private var rendered: WeekMapRenderer.Rendered?
    @State private var week: WeekMap?

    init(model: AppModel) {
        self.model = model
        _weekStart = State(initialValue: model.today.weekStart)
    }

    private var selectedDay: Int { min(6, max(0, Int(position / 24))) }
    private var dayMap: DayMap? { week.map { $0.days[selectedDay] } }

    /// Высота нижнего листа с ползунком и делами дня (8.16).
    private let panelHeight: CGFloat = 300

    var body: some View {
        ZStack(alignment: .bottom) {
            viewport.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer()
            }
            panel
        }
        .background(Color(hex: 0x8E8350))
        .onAppear { load(resetPosition: true) }
        .onChange(of: weekStart) { load(resetPosition: true) }
    }

    private func load(resetPosition: Bool) {
        let map = model.weekMap(start: weekStart)
        week = map
        rendered = WeekMapRenderer.render(map, appearance: model.hero?.appearance, accent: model.heroAccent, timeZone: .current)
        // По умолчанию — «сейчас»; в другой неделе — полдень понедельника.
        if resetPosition { position = map.heroHour ?? 12 }
        #if DEBUG
        // `-QuestlynMapHour 31` — открыть неделю в заданном часе (проверка в симуляторе).
        let debugHour = UserDefaults.standard.double(forKey: "QuestlynMapHour")
        if resetPosition, debugHour > 0 { position = debugHour }
        #endif
        dragStart = position
    }

    /// Кнопки поверх карты: назад и листание недель.
    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Label("Сегодня", systemImage: "chevron.left").font(QFont.text(15, weight: .semibold))
                    .padding(.horizontal, QSpacing.xl).frame(height: 40)
                    .background(QColor.sheet.opacity(0.94), in: Capsule())
            }
            Spacer()
            HStack(spacing: 0) {
                Button { weekStart = weekStart.adding(days: -7) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }
                    .accessibilityLabel("Предыдущая неделя")
                Text(weekTitle).font(QFont.text(14, weight: .semibold)).monospacedDigit()
                Button { weekStart = weekStart.adding(days: 7) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 40) }
                    .accessibilityLabel("Следующая неделя")
            }
            .background(QColor.sheet.opacity(0.94), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(QColor.ink)
        .padding(.horizontal, QSpacing.l)
        .padding(.top, QSpacing.s)
    }

    /// Нижний лист: ползунок недели и дела выбранного дня.
    private var panel: some View {
        VStack(spacing: QSpacing.m) {
            Capsule().fill(QColor.lineStrong).frame(width: 40, height: 5).padding(.top, QSpacing.s)
            ScrollView {
                VStack(alignment: .leading, spacing: QSpacing.l) {
                    slider
                    if let dayMap { dayDetails(dayMap) }
                }
                .padding(.horizontal, QSpacing.screen)
                .padding(.bottom, QSpacing.screen)
            }
        }
        .frame(height: panelHeight)
        .frame(maxWidth: .infinity)
        // Фон листа уходит под индикатор «домой» — до самого низа экрана.
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(QColor.paper)
                .shadow(color: .black.opacity(0.15), radius: 12, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
        .foregroundStyle(QColor.ink)
    }

    private var weekTitle: String {
        let end = weekStart.adding(days: 6)
        let ru = Locale(identifier: "ru_RU")
        guard let first = weekStart.date, let last = end.date else { return "" }
        let tail = last.formatted(.dateTime.day().month(.wide).locale(ru))
        return weekStart.month == end.month ? "\(weekStart.day)–\(tail)" : "\(first.formatted(.dateTime.day().month(.abbreviated).locale(ru))) – \(tail)"
    }

    // MARK: Окно карты

    private var viewport: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / CGFloat(WeekMapRenderer.viewport.width)
            let center = WeekMapRenderer.roadPoint(position)
            // Дорога — по центру видимой части над нижним листом.
            let visible = (proxy.size.height - panelHeight) / scale
            let originX = CGFloat(center.x) - CGFloat(WeekMapRenderer.viewport.width) / 2
            let originY = CGFloat(center.y) - visible / 2
            ZStack(alignment: .topLeading) {
                if let image = rendered?.image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: CGFloat(WeekMapRenderer.size.width) * scale, height: CGFloat(WeekMapRenderer.size.height) * scale)
                        .offset(x: -originX * scale, y: -originY * scale)
                }
                // Свет — по времени в точке ползунка.
                lightOverlay
                ForEach(Array((rendered?.labels ?? []).enumerated()), id: \.offset) { _, label in
                    let x = (CGFloat(label.x) - originX) * scale, y = (CGFloat(label.y) - originY) * scale
                    if x > -60, x < proxy.size.width + 60, y > -10, y < proxy.size.height + 10 {
                        labelView(label).position(x: x, y: y)
                    }
                }
                if let hero = week?.heroHour, abs(hero - position) < 10 {
                    let point = WeekMapRenderer.roadPoint(hero)
                    Text("\(model.progress.rank?.letter ?? "—") · \(Date.now.formatted(date: .omitted, time: .shortened))")
                        .font(QFont.text(10, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: 0xE2A04A), in: RoundedRectangle(cornerRadius: 7))
                        .fixedSize()
                        .position(x: (CGFloat(point.x) - originX) * scale, y: (CGFloat(point.y) - originY) * scale + 22)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture().onChanged { value in
                // Перетаскивание карты двигает ползунок: вдоль дороги вправо-вниз — вперёд по времени.
                let along = -(value.translation.width + value.translation.height * 2) / scale
                position = min(WeekMap.hours, max(0, dragStart + Double(along) / 6.4))
            }.onEnded { _ in dragStart = position })
            .onAppear { dragStart = position }
        }
        .accessibilityElement()
        .accessibilityLabel("Карта недели, \(Format.weekPosition(position, start: weekStart))")
    }

    @State private var dragStart: Double = 0

    @ViewBuilder private var lightOverlay: some View {
        let light = DayLight.at(hour: position.truncatingRemainder(dividingBy: 24))
        switch light {
        case .morning: Color(hex: 0xFFD9A0).opacity(0.12)
        case .day: Color.clear
        case .evening: Color(hex: 0xE58A4A).opacity(0.18)
        case .night: Color(hex: 0x1A2340).opacity(0.45)
        }
    }

    private func labelView(_ label: WeekMapRenderer.Label) -> some View {
        let (fg, bg): (Color, Color) = switch label.kind {
        case .settlement(city: true): (QColor.sheet, QColor.ink)
        case .settlement(city: false): (QColor.ink, QColor.sheet)
        case .camp(known: true): (Color(hex: 0x5C3410), Color(hex: 0xF6D9A6))
        case .camp(known: false): (QColor.inkSecondary, QColor.sheet.opacity(0.9))
        case .day: (QColor.sheet, QColor.amberDeep)
        }
        return HStack(spacing: 3) {
            if case .camp = label.kind { Image(systemName: "flame.fill").font(.system(size: 8)) }
            Text(label.title)
        }
        .font(QFont.text(10, weight: .semibold))
        .lineLimit(1)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .foregroundStyle(fg)
        .background(bg, in: RoundedRectangle(cornerRadius: 7))
        .fixedSize()
    }

    // MARK: Ползунок

    private var slider: some View {
        VStack(spacing: QSpacing.xs) {
            HStack {
                Text(Format.weekPosition(position, start: weekStart)).font(QFont.text(13, weight: .semibold)).monospacedDigit()
                Spacer()
                if let hero = week?.heroHour {
                    Button("К «сейчас»") { withAnimation { position = hero; dragStart = hero } }
                        .font(QFont.text(13, weight: .semibold)).foregroundStyle(QColor.amberDeep)
                }
            }
            Slider(value: Binding(get: { position }, set: { position = $0; dragStart = $0 }), in: 0...WeekMap.hours, step: 0.25)
                .tint(QColor.amber)
                .accessibilityLabel("Движение по дороге недели")
                .accessibilityValue(Format.weekPosition(position, start: weekStart))
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    let date = weekStart.adding(days: index)
                    Text(date.date?.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "ru_RU"))) ?? "")
                        .font(QFont.text(11, weight: index == selectedDay ? .bold : .regular))
                        .foregroundStyle(date == model.today ? QColor.amberDeep : QColor.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .onTapGesture { withAnimation { position = Double(index) * 24 + 12; dragStart = position } }
                }
            }
        }
    }

    // MARK: День под ползунком

    @ViewBuilder private func dayDetails(_ map: DayMap) -> some View {
        let rows = (map.settlements.map { ($0.startHour, $0.titles.joined(separator: " + "),
                                          $0.kind == .city ? ($0.density > 1 ? "Город · пересекаются" : "Город") : "Деревня",
                                          $0.attendees > 0 ? "участников: \($0.attendees)" : "", 0) }
                    + map.questMarkers.map { ($0.hour, $0.title, $0.isDone ? "Квест ✓" : "Квест", "", 1) })
            .sorted { $0.0 < $1.0 }
        let camp = week?.camps.first { $0.wakeDate == map.date }
        VStack(alignment: .leading, spacing: QSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(map.date.date.map { Format.longDay($0) } ?? "").font(QFont.title(17))
                Spacer()
                Text("\(MapText.season(map)) · \(map.weather.title.lowercased())").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
            if let camp {
                HStack(spacing: QSpacing.m) {
                    Image(systemName: "flame.fill").foregroundStyle(camp.source == nil ? QColor.inkSecondary : QColor.amber)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Привал \(camp.start.formatted(date: .omitted, time: .shortened))–\(camp.end.formatted(date: .omitted, time: .shortened))")
                            .font(QFont.text(13, weight: .semibold))
                        Text(camp.source == nil ? "нет данных о сне · ночь нейтральная"
                             : "\(WeekMapRenderer.duration(camp.minutes)) · \(camp.source == .health ? "Apple Health" : "вручную")")
                            .font(QFont.text(11)).foregroundStyle(QColor.inkSecondary)
                    }
                }
                .padding(QSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(QColor.warmFill, in: RoundedRectangle(cornerRadius: QRadius.small))
            }
            if rows.isEmpty {
                Text(model.isCalendarAuthorized ? "Событий с точным временем нет — только дорога." : "Подключите Apple Calendar во вкладке «Календарь», чтобы события стали поселениями.")
                    .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: QSpacing.m) {
                    Text(MapText.time(row.0)).font(QFont.text(13, weight: .bold)).monospacedDigit().frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.1).font(QFont.text(13)).lineLimit(1)
                        if !row.3.isEmpty { Text(row.3).font(QFont.text(11)).foregroundStyle(QColor.inkSecondary) }
                    }
                    Spacer()
                    Text(row.2).font(QFont.text(11, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(row.2 == "Деревня" ? QColor.warmInk : row.4 == 1 ? QColor.ink : QColor.sheet)
                        .background(row.2 == "Деревня" ? QColor.warmFill : row.4 == 1 ? QColor.coolFill : QColor.ink,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, QSpacing.m)
                .frame(minHeight: 36)
                .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.small))
                .onTapGesture { withAnimation { position = Double(selectedDay) * 24 + row.0; dragStart = position } }
            }
            if !map.offMap.isEmpty {
                VStack(alignment: .leading, spacing: QSpacing.xxs) {
                    Text("Вне карты — без точного времени").font(QFont.text(12, weight: .bold)).foregroundStyle(QColor.inkSecondary)
                    Text(map.offMap.joined(separator: " · ")).font(QFont.text(12))
                }
                .padding(QSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: QRadius.control).strokeBorder(QColor.dash, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
    }
}
