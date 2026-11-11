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
    /// Объект, по которому коснулись: подсказка-реплика над ним (8.3).
    @State private var selected: Selection?
    /// «Побродить» (8B).
    @State private var isExploring = false
    /// Спрайт героя для карты недели.
    @State private var heroImage: CGImage?

    struct Selection: Equatable {
        let x: Int
        let y: Int
        let callout: WeekMapRenderer.Callout
    }

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
        .onChange(of: weekStart) { selected = nil; load(resetPosition: true) }
        .fullScreenCover(isPresented: $isExploring) { ExploreFlowView(model: model) }
    }

    private func load(resetPosition: Bool) {
        let map = model.weekMap(start: weekStart)
        week = map
        rendered = WeekMapRenderer.render(map, appearance: model.hero?.appearance, accent: model.heroAccent, timeZone: .current)
        if heroImage == nil, let appearance = model.hero?.appearance { heroImage = ExploreRenderer.person(appearance, accent: model.heroAccent) }
        // По умолчанию — «сейчас»; в другой неделе — полдень понедельника.
        if resetPosition { position = map.heroHour ?? 12 }
        #if DEBUG
        // `-QuestlynMapHour 31` — открыть неделю в заданном часе (проверка в симуляторе).
        let debugHour = UserDefaults.standard.double(forKey: "QuestlynMapHour")
        if resetPosition, debugHour > 0 { position = debugHour }
        // `-QuestlynMapCallout YES` — сразу открыть подсказку первого поселения.
        if UserDefaults.standard.bool(forKey: "QuestlynMapCallout"),
           let label = rendered?.labels.first(where: { if case .settlement = $0.kind { $0.callout != nil } else { false } }), let callout = label.callout {
            selected = Selection(x: label.x, y: label.y, callout: callout)
            position = callout.weekHour
        }
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
                    Button { isExploring = true } label: {
                        Label("Побродить", systemImage: "figure.walk").font(QFont.text(15, weight: .semibold))
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityHint("Мини-игра на острове из событий за прошлые даты")
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
                        if let callout = label.callout {
                            Button { select(Selection(x: label.x, y: label.y, callout: callout)) } label: {
                                labelView(label).padding(8).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(callout.caption + ": " + callout.title)
                            .position(x: x, y: y)
                        } else {
                            labelView(label).position(x: x, y: y)
                        }
                    }
                }
                // «Сейчас» — постоянная метка на дороге (8C.3).
                if let now = week?.heroHour, abs(now - position) > 0.4 {
                    let point = WeekMapRenderer.roadPoint(now)
                    VStack(spacing: 0) {
                        Text("Сейчас").font(QFont.text(9, weight: .bold)).foregroundStyle(QColor.sheet)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color(hex: 0x1F2A44), in: RoundedRectangle(cornerRadius: 5))
                        Rectangle().fill(Color(hex: 0x1F2A44)).frame(width: 2, height: 8)
                    }
                    .fixedSize()
                    .position(x: (CGFloat(point.x) - originX) * scale, y: (CGFloat(point.y) - originY) * scale - 10)
                    .accessibilityHidden(true)
                }
                // Герой идёт по дороге за ползунком и перетаскиванием (8C.3).
                if let image = heroImage {
                    let point = WeekMapRenderer.roadPoint(position)
                    Image(decorative: image, scale: 1).resizable().interpolation(.none)
                        .frame(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                        .position(x: (CGFloat(point.x) - originX) * scale,
                                  y: (CGFloat(point.y + 7) - originY) * scale - CGFloat(image.height) * scale / 2)
                        .allowsHitTesting(false)
                }
                do {
                    let hero = position
                    let point = WeekMapRenderer.roadPoint(hero)
                    Button { select(Selection(x: point.x, y: point.y + 16, callout: heroCallout(hour: hero))) } label: {
                        Text("\(model.progress.rank?.letter ?? "—") · \(positionTime)")
                            .font(QFont.text(10, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(hex: 0xE2A04A), in: RoundedRectangle(cornerRadius: 7))
                            .fixedSize()
                            .padding(10).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(hex: 0x1F2A44))
                    .accessibilityLabel("Герой")
                    .position(x: (CGFloat(point.x) - originX) * scale, y: (CGFloat(point.y) - originY) * scale + 22)
                }
                if let selected {
                    let x = (CGFloat(selected.x) - originX) * scale, y = (CGFloat(selected.y) - originY) * scale
                    MapCallout(callout: selected.callout, anchorX: x, width: proxy.size.width) { self.selected = nil }
                        .position(x: min(max(x, 136), proxy.size.width - 136), y: y - 12)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { selected = nil }
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
        case .quest: (.clear, .clear)
        }
        if case .quest = label.kind {
            // Флажок квеста нарисован на карте — здесь только место касания.
            return AnyView(Color.clear.frame(width: 28, height: 28))
        }
        return AnyView(HStack(spacing: 3) {
            if case .camp = label.kind { Image(systemName: "flame.fill").font(.system(size: 8)) }
            Text(label.title)
        }
        .font(QFont.text(10, weight: .semibold))
        .lineLimit(1)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .foregroundStyle(fg)
        .background(bg, in: RoundedRectangle(cornerRadius: 7))
        .fixedSize())
    }

    /// Время точки ползунка — подпись над героем.
    private var positionTime: String {
        let start = VitalsCalculator.date(weekStart, LocalTime(hour: 0, minute: 0)!, timeZone: .current)
        return start.addingTimeInterval(position * 3600).formatted(date: .omitted, time: .shortened)
    }

    private func select(_ selection: Selection) {
        selected = selected == selection ? nil : selection
    }

    /// Подсказка героя: ранг, HP и MP сейчас.
    private func heroCallout(hour: Double) -> WeekMapRenderer.Callout {
        var lines = ["Ранг: \(model.progress.rank.map { "\($0.letter) · \($0.title)" } ?? "без ранга")"]
        if let vitals = model.vitals {
            lines.append("HP \(Vitals.whole(vitals.hp)) / \(Vitals.whole(vitals.maxHP)) · MP \(Vitals.whole(vitals.mp)) / \(Vitals.whole(vitals.maxMP))")
        }
        return WeekMapRenderer.Callout(caption: "Герой · сейчас", title: model.hero?.name ?? "Герой", lines: lines, weekHour: hour)
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
                             : "\(WeekMapRenderer.duration(camp.minutes)) · \(camp.source.map(SleepCard.sourceTitle) ?? "")")
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
                let isSelected = selected.map { abs($0.callout.weekHour - (Double(selectedDay) * 24 + row.0)) < 0.01 } ?? false
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
                .background(isSelected ? QColor.warmFill : QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.small))
                .overlay(RoundedRectangle(cornerRadius: QRadius.small).strokeBorder(isSelected ? QColor.amber : .clear, lineWidth: 1.5))
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

/// Подсказка-реплика на большой карте (8.3, макет 8.19): пиксельная рамка, хвостик к объекту, закрытие крестиком или касанием мимо.
struct MapCallout: View {
    let callout: WeekMapRenderer.Callout
    /// Точка объекта по горизонтали — к ней смотрит хвостик.
    let anchorX: CGFloat
    let width: CGFloat
    let close: () -> Void

    private let bubbleWidth: CGFloat = 248

    var body: some View {
        let center = min(max(anchorX, bubbleWidth / 2 + 12), width - bubbleWidth / 2 - 12)
        let tail = min(max(anchorX - (center - bubbleWidth / 2), 16), bubbleWidth - 16)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: QSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(callout.caption).font(QFont.text(11, weight: .bold)).textCase(.uppercase).tracking(0.6)
                        .foregroundStyle(QColor.forest)
                    Spacer(minLength: QSpacing.s)
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Закрыть подсказку")
                }
                Text(callout.title).font(QFont.title(17, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                ForEach(callout.lines, id: \.self) { line in
                    Text(line).font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                }
            }
            .foregroundStyle(QColor.ink)
            .padding(.horizontal, QSpacing.l).padding(.vertical, QSpacing.m)
            .frame(width: bubbleWidth, alignment: .leading)
            .background(QColor.sheet)
            .overlay(Rectangle().strokeBorder(QColor.ink, lineWidth: 3))
            // Тень всегда тёмная: «чернила» в тёмной теме светлые и выглядели как фон за рамкой (8C.1).
            .background(Color.black.opacity(0.35).offset(x: 4, y: 4))
            // Ступенчатый хвостик, как в пиксельном диалоге.
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(QColor.ink).frame(width: 15, height: 3)
                Rectangle().fill(QColor.ink).frame(width: 9, height: 3).padding(.leading, 3)
                Rectangle().fill(QColor.ink).frame(width: 3, height: 3).padding(.leading, 6)
            }
            .padding(.leading, tail - 7.5)
            .accessibilityHidden(true)
        }
        .frame(width: bubbleWidth)
        .offset(x: center - min(max(anchorX, 136), width - 136), y: -bubbleHeightGuess / 2)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// Пузырь стоит над объектом: сдвиг вверх на половину примерной высоты.
    private var bubbleHeightGuess: CGFloat { 70 + CGFloat(callout.lines.count) * 16 }
}
