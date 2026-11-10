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
                            let x = (4 + hour / 24 * Double(PixelMapRenderer.stripSize.width - 8)) * scale
                            Text("Вы · \(MapText.time(hour))")
                                .font(QFont.text(10, weight: .bold))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Color(hex: 0xE2A04A), in: RoundedRectangle(cornerRadius: 7))
                                .fixedSize()
                                .position(x: min(max(x, 34), proxy.size.width - 34), y: 22 * scale)
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

    /// «Дальше по дороге»: ближайшие поселения и квесты, плюс то, что вне карты.
    @ViewBuilder private func upcoming(_ map: DayMap) -> some View {
        let now = map.heroHour ?? 0
        let next = (map.settlements.filter { $0.endHour > now }.map { ($0.startHour, $0.titles.joined(separator: " + "), $0.kind == .city ? (($0.density > 1) ? "город, пересекаются" : "город") : "деревня", false) }
            + map.questMarkers.filter { $0.hour >= now && !$0.isDone }.map { ($0.hour, $0.title, "квест", true) })
            .sorted { $0.0 < $1.0 }.prefix(3)
        if !next.isEmpty || !map.offMap.isEmpty {
            VStack(alignment: .leading, spacing: QSpacing.xs) {
                if !next.isEmpty {
                    Text("Дальше по дороге").font(QFont.text(12, weight: .bold))
                    ForEach(Array(next.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: QSpacing.s) {
                            Text(MapText.time(item.0)).monospacedDigit().fontWeight(.semibold)
                            Text(item.1).lineLimit(1)
                            Text("· \(item.2)").foregroundStyle(item.3 ? QColor.amberDeep : QColor.inkSecondary)
                        }
                        .font(QFont.text(12))
                    }
                }
                if !map.offMap.isEmpty {
                    Text("Вне карты: " + map.offMap.joined(separator: " · "))
                        .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary).lineLimit(2)
                }
            }
            .padding(.horizontal, QSpacing.l)
            .padding(.vertical, QSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheetCard()
        }
    }
}

/// Большая карта (холст 8.8, макет 3.5): изометрия, листание дней, список «На карте» и «Вне карты».
struct MapOverviewView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var date: LocalDate

    init(model: AppModel) {
        self.model = model
        _date = State(initialValue: model.today)
    }

    var body: some View {
        let map = model.dayMap(for: date)
        let rendered = PixelMapRenderer.isometric(map, appearance: model.hero?.appearance, accent: model.heroAccent)
        VStack(spacing: QSpacing.m) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: QSpacing.l) {
                    GeometryReader { proxy in
                        let scale = proxy.size.width / CGFloat(PixelMapRenderer.isoSize.width)
                        ZStack(alignment: .topLeading) {
                            if let image = rendered.image {
                                Image(decorative: image, scale: 1).resizable().interpolation(.none)
                            }
                            ForEach(Array(labelPositions(rendered.anchors, scale: scale).enumerated()), id: \.offset) { _, item in
                                let anchor = item.anchor
                                Text(anchor.title)
                                    .font(QFont.text(10, weight: .semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .foregroundStyle(anchor.isCity ? QColor.sheet : QColor.ink)
                                    .background(anchor.isCity ? QColor.ink : QColor.sheet, in: RoundedRectangle(cornerRadius: 7))
                                    .fixedSize()
                                    .position(x: min(max(CGFloat(anchor.x) * scale, 50), proxy.size.width - 50), y: item.y)
                            }
                            if let hero = rendered.hero, let hour = map.heroHour {
                                let before = hour < rendered.window.lowerBound
                                Text(hero.outside ? (before ? "← Вы · \(MapText.time(hour)) · дела впереди" : "Вы · \(MapText.time(hour)) · дела позади →") : "Вы · \(MapText.time(hour))")
                                    .font(QFont.text(10, weight: .bold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color(hex: 0xE2A04A), in: RoundedRectangle(cornerRadius: 7))
                                    .fixedSize()
                                    .position(x: min(max(CGFloat(hero.x) * scale, 70), proxy.size.width - 70),
                                              y: CGFloat(hero.y) * scale + 14)
                            }
                            Text("\(MapText.season(map)) · \(MapText.weather(map, lastMood: map.date == model.today ? model.lastMood : nil))")
                                .font(QFont.text(11)).foregroundStyle(QColor.inkSecondary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(QColor.sheet.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
                                .padding(8)
                        }
                    }
                    .aspectRatio(CGFloat(PixelMapRenderer.isoSize.width) / CGFloat(PixelMapRenderer.isoSize.height), contentMode: .fit)
                    .accessibilityElement()
                    .accessibilityLabel("Изометрическая карта дня: \(map.settlements.count) поселений, \(map.questMarkers.count) квестов на дороге")
                    .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                        withAnimation { date = date.adding(days: value.translation.width < 0 ? 1 : -1) }
                    })

                    VStack(spacing: QSpacing.xs) {
                        timeBar(map, window: rendered.window)
                        MapText.timeAxis()
                    }
                    .padding(.horizontal, QSpacing.screen)

                    list(map).padding(.horizontal, QSpacing.screen)
                }
                .padding(.bottom, QSpacing.screen)
            }
        }
        .paperScreen()
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Label("Сегодня", systemImage: "chevron.left").font(QFont.text(15))
            }
            .foregroundStyle(QColor.ink)
            Spacer()
            Button { withAnimation { date = date.adding(days: -1) } } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Предыдущий день")
            Text(date.date.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.wide).locale(Locale(identifier: "ru_RU"))) } ?? "")
                .font(QFont.title(17))
            Button { withAnimation { date = date.adding(days: 1) } } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Следующий день")
            Spacer()
            Color.clear.frame(width: 70, height: 1)
        }
        .foregroundStyle(QColor.ink)
        .padding(.horizontal, QSpacing.m)
        .padding(.top, QSpacing.m)
    }

    /// Подписи поселений без наложений: соседние по горизонтали отодвигаются дальше от дороги.
    private func labelPositions(_ anchors: [PixelMapRenderer.Anchor], scale: CGFloat) -> [(anchor: PixelMapRenderer.Anchor, y: CGFloat)] {
        var placed: [(anchor: PixelMapRenderer.Anchor, y: CGFloat)] = []
        for anchor in anchors.sorted(by: { $0.x < $1.x }) {
            var y = CGFloat(anchor.y) * scale
            let step: CGFloat = anchor.above ? -22 : 22
            while placed.contains(where: { $0.anchor.above == anchor.above && abs(CGFloat($0.anchor.x - anchor.x) * scale) < 96 && abs($0.y - y) < 20 }) {
                y += step
            }
            placed.append((anchor, max(10, y)))
        }
        return placed
    }

    /// Шкала дня: видимая часть (рамка), поселения и «сейчас».
    private func timeBar(_ map: DayMap, window: ClosedRange<Double>) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(QColor.track)
                RoundedRectangle(cornerRadius: 6).strokeBorder(QColor.ink, lineWidth: 2)
                    .frame(width: (window.upperBound - window.lowerBound) / 24 * proxy.size.width)
                    .offset(x: window.lowerBound / 24 * proxy.size.width)
                ForEach(Array(map.settlements.enumerated()), id: \.offset) { _, settlement in
                    Capsule().fill(settlement.kind == .city ? QColor.ink : QColor.lineStrong)
                        .frame(width: max(4, (settlement.endHour - settlement.startHour) / 24 * proxy.size.width))
                        .offset(x: settlement.startHour / 24 * proxy.size.width)
                }
                if let hour = map.heroHour {
                    Rectangle().fill(QColor.amber).frame(width: 3, height: 18).offset(x: hour / 24 * proxy.size.width - 1.5)
                }
            }
        }
        .frame(height: 12)
    }

    @ViewBuilder private func list(_ map: DayMap) -> some View {
        let rows = (map.settlements.map { ($0.startHour, $0.titles.joined(separator: " + "),
                                          $0.kind == .city ? ($0.density > 1 ? "Город · пересекаются" : "Город") : "Деревня",
                                          $0.attendees > 0 ? "участников: \($0.attendees)" : "", 0) }
                    + map.questMarkers.map { ($0.hour, $0.title, $0.isDone ? "Квест ✓" : "Квест", "", 1) })
            .sorted { $0.0 < $1.0 }
        VStack(alignment: .leading, spacing: QSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("На карте").font(QFont.title(17))
                Spacer()
                Text("календарь и квесты").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
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
                        .foregroundStyle(row.2 == "Деревня" ? Color(hex: 0x7A3F0E) : row.4 == 1 ? QColor.ink : QColor.sheet)
                        .background(row.2 == "Деревня" ? Color(hex: 0xF1E3D3) : row.4 == 1 ? Color(hex: 0xE6E8EE) : QColor.ink,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, QSpacing.m)
                .frame(minHeight: 36)
                .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.small))
            }
            if !map.offMap.isEmpty {
                VStack(alignment: .leading, spacing: QSpacing.xxs) {
                    Text("Вне карты — без точного времени").font(QFont.text(12, weight: .bold)).foregroundStyle(QColor.inkSecondary)
                    Text(map.offMap.joined(separator: " · ")).font(QFont.text(12))
                }
                .padding(QSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: QRadius.control).strokeBorder(Color(hex: 0xB8A98A), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
    }
}
