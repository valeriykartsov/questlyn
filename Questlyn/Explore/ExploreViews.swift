import SwiftUI
import SpriteKit
import Domain
import Application

/// «Побродить» (8B, макеты 8B.1–8B.4): выбор диапазона и навыков → остров → итог. Песочница — ничего не сохраняется.
struct ExploreFlowView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    enum Phase { case setup, game, summary }
    @State private var phase: Phase = .setup
    /// Мир строится в фоне (16.3: до 6 месяцев и 7 глав).
    @State private var building = false
    @State private var first: Date
    @State private var last: Date
    @State private var chosen: [UUID] = []
    @State private var attempt = 0
    @State private var session: ExploreSession?

    init(model: AppModel) {
        self.model = model
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        _last = State(initialValue: yesterday)
        _first = State(initialValue: Calendar.current.date(byAdding: .day, value: -27, to: yesterday) ?? yesterday)
    }

    var body: some View {
        Group {
            switch phase {
            case .setup:
                NavigationStack {
                    ExploreSetupView(model: model, first: $first, last: $last, chosen: $chosen) { start(background: true) }
                }
                .overlay {
                    if building {
                        ZStack {
                            Color.black.opacity(0.35).ignoresSafeArea()
                            VStack(spacing: QSpacing.m) {
                                ProgressView()
                                Text("Строю мир…").font(QFont.text(15, weight: .semibold))
                                Text("Большой диапазон — до нескольких секунд").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                            }
                            .padding(QSpacing.xl)
                            .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.card))
                        }
                    }
                }
            case .game:
                if let session { ExploreGameView(session: session) { phase = .summary } }
            case .summary:
                if let session {
                    ExploreSummaryView(session: session) {
                        attempt += 1
                        phase = .setup
                        start(background: true)
                    } close: { dismiss() }
                }
            }
        }
        .task {
            await model.loadExploreHabits()
            autoStartIfNeeded()
        }
    }

    private var range: (LocalDate, LocalDate) { (LocalDate(first, timeZone: .current), LocalDate(last, timeZone: .current)) }

    private func start(background: Bool = false) {
        guard !building else { return }
        let (a, b) = range
        let skills = model.exploreSkills.filter { chosen.contains($0.id) }
        let input = model.exploreInput(first: a, last: b), hero = model.exploreHero(skills: skills)
        let attempt = attempt
        func open(_ island: Island?) {
            session = ExploreSession(input: input, hero: hero, attempt: attempt, appearance: model.hero?.appearance, accent: model.heroAccent,
                                     mode: ExploreModeSetting.current, prebuilt: island)
            session?.ghostCount = model.ghosts.count
            session?.aura = model.auraTier
            session?.badge = model.heroBadge
            phase = .game
        }
        guard background else { open(nil); return }
        building = true
        Task {
            let seed = input.seed(attempt: attempt)
            let island = await Task.detached(priority: .userInitiated) { IslandGenerator.generate(input, seed: seed) }.value
            open(island)
            building = false
        }
    }

    private func autoStartIfNeeded() {
        #if DEBUG
        // `-QuestlynExploreAuto YES` — сразу на остров (проверка в симуляторе без нажатий).
        guard UserDefaults.standard.bool(forKey: "QuestlynExploreAuto"), phase == .setup else { return }
        first = Calendar.current.date(byAdding: .day, value: -60, to: last) ?? first
        chosen = Array(model.exploreSkills.prefix(2).map(\.id))
        start()
        if UserDefaults.standard.bool(forKey: "QuestlynExploreEncounter"), let session, let npc = session.island.npcs.last {
            session.startEncounter(npc: npc)
            session.encounter?.perform(.fight)
        }
        // `-QuestlynExploreDemo night | bag | tower` — этап 14: ночь, сумка со спутником, герой у Чёрной башни.
        if let demo = UserDefaults.standard.string(forKey: "QuestlynExploreDemo"), let session {
            if demo.contains("night") { session.clockHour = 22 }
            if demo.contains("map") { session.isWorldMapOpen = true }
            // `pier` (17.12) — герой у первой пристани крупного города.
            if demo.contains("pier"), let pier = session.island.piers.first { session.heroTile = pier.landing }
            // `ship` / `sea` (15E) — корабль готов, 14 досок, лучший спутник в экипаже; `sea` — сразу на корабле.
            if demo.contains("ship") || demo.contains("sea") {
                session.shipReady = true
                session.planks = 14
                for npc in session.island.npcs.filter({ $0.legend != nil }).prefix(2) { session.crew.append(npc) }
                session.companion = session.island.npcs.first { $0.isPeaceful && $0.legend == nil }
            }
            if demo.contains("sea"), let ship = session.ships.first, let landing = session.island.landing(near: ship) { session.heroTile = landing }
            // `talk` / `legend` (15H) — открыт диалог с мирным NPC или легендой.
            if demo.contains("talk") { session.talkNPC = session.island.npcs.first { $0.isPeaceful && $0.legend == nil && !$0.meetingTitle.isEmpty } }
            if demo.contains("legend") { session.talkNPC = session.island.npcs.first { $0.legend != nil } }
            // `boss` — у финальной башни; `shrine` — у монумента полезного; `swamp` — в болоте (15B, 15G).
            if demo.contains("boss"), let tower = session.finalTower,
               let spot = [(2, 0), (0, 2), (-2, 0), (0, -2)].map({ TilePoint(tower.position.x + $0.0, tower.position.y + $0.1) }).first(where: { session.island.isWalkable($0) }) {
                session.heroTile = spot
            }
            if demo.contains("shrine"), let shrine = session.island.shrines.first,
               let spot = [(2, 0), (0, 2), (-2, 0), (0, -2)].map({ TilePoint(shrine.position.x + $0.0, shrine.position.y + $0.1) }).first(where: { session.island.isWalkable($0) }) {
                session.heroTile = spot
            }
            // `cave` — у входа в пещеру; `treasure` — все обрывки найдены, герой у клада; `lookout` — у площадки (15C).
            if demo.contains("cave"), let cave = session.island.caves.first { session.heroTile = cave.entrance }
            // `merchant` — у торговца с вещами в сумке (15D).
            if demo.contains("merchant"), let merchant = session.island.merchants.first {
                session.heroTile = merchant.position
                for item in ExploreItem.allCases { _ = session.addItem(item) }
            }
            if demo.contains("lookout"), let lookout = session.island.lookouts.first,
               let spot = [(2, 0), (0, 2), (-2, 0), (0, -2)].map({ TilePoint(lookout.position.x + $0.0, lookout.position.y + $0.1) }).first(where: { session.island.isWalkable($0) }) {
                session.heroTile = spot
            }
            if demo.contains("treasure"), let chest = session.island.chests.first(where: { $0.fragment != nil }) {
                for fragment in session.island.chests.compactMap(\.fragment) { session.findFragment(fragment, in: chest) }
                if let spot = session.treasureSpot,
                   let near = [(3, 0), (0, 3), (-3, 0), (0, -3)].map({ TilePoint(spot.x + $0.0, spot.y + $0.1) }).first(where: { session.island.isWalkable($0) }) {
                    session.heroTile = near
                }
            }
            if demo.contains("swamp"), let index = session.island.swamp.firstIndex(of: true) {
                session.heroTile = TilePoint(index % session.island.side, index / session.island.side)
            }
            // `fight` — герой в клетке от NPC: встреча начнётся сама (в активном режиме — бой на карте).
            if demo.contains("fight"), let npc = session.island.npcs.first(where: { session.island.isWalkable(TilePoint($0.home.x + 1, $0.home.y)) }) {
                session.heroTile = TilePoint(npc.home.x + 1, npc.home.y)
            }
            // `north` — герой на севере у гор (15A): самая северная клетка суши рядом с горой.
            if demo.contains("north") {
                let island = session.island, side = island.side
                var best: TilePoint?
                for y in 0..<side { for x in 0..<side where island.isWalkable(TilePoint(x, y)) && island.zone(at: TilePoint(x, y)).isCold {
                    let point = TilePoint(x, y)
                    let nearMountain = (-3...3).contains { dx in (-3...3).contains { dy in island.terrain(at: TilePoint(x + dx, y + dy)) == .mountain } }
                    if nearMountain, best.map({ x + y < $0.x + $0.y }) ?? true { best = point }
                } }
                if let best { session.heroTile = best }
            }
            if demo.contains("bag") {
                for item in ExploreItem.allCases { _ = session.addItem(item) }
                session.companion = session.island.npcs.first
                if let city = session.island.cities.first, let task = session.island.tasks.first(where: { $0.cityId == city.id }) {
                    session.takeTask(task)
                }
            }
            if demo.contains("tower"), let tower = session.island.towers.first,
               let spot = [(2, 0), (0, 2), (-2, 0), (0, -2)].map({ TilePoint(tower.position.x + $0.0, tower.position.y + $0.1) }).first(where: { session.island.isWalkable($0) }) {
                session.heroTile = spot
            }
        }
        // `-QuestlynExploreShip shore | sail` — герой у корабля своего острова или уже на нём, в паре клеток от берега (12B).
        if let mode = UserDefaults.standard.string(forKey: "QuestlynExploreShip"), let session, let ship = session.island.ships.last {
            if mode == "sail" {
                var tile = ship.position
                let toward = session.island.regions[max(0, ship.region - 1)].center
                for _ in 0..<12 {
                    let dx = (toward.x - tile.x).signum(), dy = (toward.y - tile.y).signum()
                    let next = TilePoint(tile.x + dx, tile.y + dy)
                    guard !session.island.isLand(next) else { break }
                    tile = next
                }
                session.ships[ship.id] = tile
                session.sailing = ship.id
                session.heroTile = tile
            } else if let landing = session.island.landing(near: ship.position) {
                session.heroTile = landing
            }
        }
        #endif
    }
}

extension View {
    /// «×1,25».
    static func power(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "ru_RU")))
    }
}

// MARK: - Выбор диапазона и навыков (8B.1)

struct ExploreSetupView: View {
    let model: AppModel
    @Binding var first: Date
    @Binding var last: Date
    @Binding var chosen: [UUID]
    let start: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var preview: Island?

    /// «Малый остров» или «Архипелаг · 3 острова» (12B).
    static func title(_ island: Island) -> String {
        let count = island.regions.count
        guard count > 1 else { return island.size.title }
        return "Архипелаг · \(count) \(count < 5 ? "острова" : "островов")"
    }

    private var yesterday: Date { Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now)) ?? .now }
    private var firstDay: LocalDate { LocalDate(first, timeZone: .current) }
    private var lastDay: LocalDate { LocalDate(last, timeZone: .current) }
    private var days: Int { firstDay.days(until: lastDay) + 1 }
    private var isValid: Bool { ExploreInput.isValidRange(first: firstDay, last: lastDay, today: model.today) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.l) {
                CapsHeader(title: "Диапазон · прошлые даты, до 3 месяцев")
                VStack(spacing: 0) {
                    DatePicker("С", selection: $first, in: earliest...last, displayedComponents: .date)
                        .padding(.horizontal, QSpacing.xl).frame(minHeight: 50)
                    Divider().overlay(QColor.line)
                    DatePicker("По", selection: $last, in: first...yesterday, displayedComponents: .date)
                        .padding(.horizontal, QSpacing.xl).frame(minHeight: 50)
                }
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .sheetCard()
                HStack(spacing: QSpacing.s) {
                    preset("2 нед.", days: 14)
                    preset("Месяц", days: 30)
                    preset("3 мес.", days: 92)
                    preset("6 мес.", days: ExploreRules.maxDays)
                }
                summary
                // 15A: время года заменили климатические зоны, погода — из настроения.
                VStack(alignment: .leading, spacing: 2) {
                    Text("Погода — из твоего настроения").font(QFont.text(14, weight: .semibold))
                    Text("Случайная отметка месяца: плохо — дождь (на севере — снег), нормально — облачно, хорошо — ясно. Климат — от тундры на севере до пустыни на юге.")
                        .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                }
                .padding(QSpacing.l).frame(maxWidth: .infinity, alignment: .leading)
                .sheetCard()
                skillsSection
                Text("Песочница: XP, HP, MP и Летопись героя не меняются. HP и MP в игре стартуют с текущих.")
                    .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                    .padding(QSpacing.l).frame(maxWidth: .infinity, alignment: .leading)
                    .background(QColor.track, in: RoundedRectangle(cornerRadius: QRadius.card))
                Button("Создать остров", action: start)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!isValid)
            }
            .padding(QSpacing.screen)
        }
        .paperScreen()
        .navigationTitle("Побродить")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
        .task(id: "\(firstDay)-\(lastDay)") {
            guard isValid else { preview = nil; return }
            let input = model.exploreInput(first: firstDay, last: lastDay)
            preview = IslandGenerator.generate(input, seed: input.seed(attempt: 0))
        }
        .tint(QColor.amber)
    }

    /// Самое раннее начало: 183 дня до конца диапазона (16.3).
    private var earliest: Date { Calendar.current.date(byAdding: .day, value: -(ExploreRules.maxDays - 1), to: last) ?? last }

    private func preset(_ title: String, days: Int) -> some View {
        let isOn = self.days == days && Calendar.current.isDate(last, inSameDayAs: yesterday)
        return Button(title) {
            last = yesterday
            first = Calendar.current.date(byAdding: .day, value: -(days - 1), to: yesterday) ?? yesterday
        }
        .font(QFont.text(13, weight: isOn ? .bold : .medium))
        .foregroundStyle(isOn ? QColor.sheet : QColor.ink)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(isOn ? QColor.ink : Color.clear, in: Capsule())
        .overlay(Capsule().strokeBorder(isOn ? .clear : QColor.lineStrong))
        .buttonStyle(.plain)
    }

    @ViewBuilder private var summary: some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            HStack {
                Text(preview.map(Self.title) ?? "Остров").font(QFont.text(15, weight: .bold))
                Spacer()
                Text(Format.dayCount(days)).font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
            if let island = preview {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: QSpacing.s), count: 3), spacing: QSpacing.s) {
                    count(island.cities.count, "городов")
                    count(island.villages.count, "деревень")
                    count(island.npcs.count, "NPC")
                    count(island.chests.count, "сундуков")
                    count(island.campfires.count, "костров")
                    if island.regions.count > 1 { count(island.regions.count, "островов-месяцев") } else { count(island.roads.count, "дорог") }
                }
                if !model.isCalendarAuthorized && island.cities.isEmpty {
                    Text("Без доступа к календарю на острове не будет городов и NPC. Подключите Apple Calendar во вкладке «Календарь».")
                        .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                }
            } else {
                Text("Выберите прошлые даты — не больше 3 месяцев.").font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
            }
        }
        .padding(QSpacing.l)
        .sheetCard()
    }

    private func count(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)").font(QFont.text(16, weight: .bold)).monospacedDigit()
            Text(label).font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(QSpacing.s)
        .background(QColor.paper, in: RoundedRectangle(cornerRadius: QRadius.small))
    }

    @ViewBuilder private var skillsSection: some View {
        HStack {
            CapsHeader(title: "Навыки в дорогу")
            Spacer()
            Text("\(chosen.count) из \(ExploreRules.maxSkills)").font(QFont.text(12, weight: .bold))
        }
        let skills = model.exploreSkills
        if skills.isEmpty {
            Text("Пока нет навыков — можно побродить и без них. Навык получает способность по виду активности или атрибуту профессии.")
                .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(skills.enumerated()), id: \.element.id) { index, skill in
                    if index > 0 { Divider().overlay(QColor.line) }
                    let isOn = chosen.contains(skill.id)
                    Button {
                        if isOn { chosen.removeAll { $0 == skill.id } } else if chosen.count < ExploreRules.maxSkills { chosen.append(skill.id) }
                    } label: {
                        HStack(spacing: QSpacing.l) {
                            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                                .font(.system(size: 20)).foregroundStyle(isOn ? QColor.ink : QColor.lineStrong)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.title).font(QFont.text(15, weight: .semibold)).foregroundStyle(QColor.ink)
                                Text("\(skill.ability.title) · \(skill.ability.summary)").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("×\(Self.power(skill.power))").font(QFont.text(13, weight: .bold)).foregroundStyle(QColor.amberDeep)
                        }
                        .padding(.horizontal, QSpacing.xl).frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isOn && chosen.count >= ExploreRules.maxSkills)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .sheetCard()
            Text("Способность — по виду активности навыка, без привязки — по атрибуту профессии. Сила — от XP навыка.")
                .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
        }
    }
}

// MARK: - Остров (8B.2)

struct ExploreGameView: View {
    @Bindable var session: ExploreSession
    let exit: () -> Void
    @State private var scene: ExploreScene?
    @State private var caveScene: CaveScene?
    @State private var hallScene: HallScene?
    @State private var showsTasks = false

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width > proxy.size.height
            ZStack(alignment: .top) {
                if let hallScene {
                    SpriteView(scene: hallScene, preferredFramesPerSecond: 60)
                        .ignoresSafeArea()
                        .accessibilityLabel("Зал башни: босс у дальней стены")
                } else if let caveScene {
                    SpriteView(scene: caveScene, preferredFramesPerSecond: 60)
                        .ignoresSafeArea()
                        .accessibilityLabel("Пещера: найдите выход")
                } else if let scene {
                    SpriteView(scene: scene, preferredFramesPerSecond: 60)
                        .ignoresSafeArea()
                        .accessibilityLabel("Остров: касание — идти туда")
                } else {
                    Color(hex: 0x3F6E9C).ignoresSafeArea()
                }
                VStack(spacing: QSpacing.s) {
                    if wide {
                        // Горизонтально: всё сверху в одну строку, панели снизу — по центру.
                        HStack(alignment: .top, spacing: QSpacing.s) {
                            topBar.frame(maxWidth: 380)
                            goals
                            Spacer()
                            VStack(spacing: QSpacing.s) {
                                minimap
                                zoomButtons
                            }
                        }
                    } else {
                        topBar
                        HStack(alignment: .top) {
                            goals
                            Spacer()
                            VStack(spacing: QSpacing.s) {
                                minimap
                                zoomButtons
                            }
                        }
                    }
                    if let toast = session.toast {
                        Text(toast).font(QFont.text(13, weight: .semibold)).foregroundStyle(QColor.ink)
                            .padding(.horizontal, QSpacing.l).padding(.vertical, QSpacing.s)
                            .background(QColor.sheet.opacity(0.95), in: Capsule())
                            .transition(.opacity)
                    }
                    Spacer()
                    VStack(spacing: QSpacing.s) {
                        // Горизонтально в активном режиме сумка — в нижней строке между джойстиком и кнопками.
                        if !(wide && session.mode == .active) { bagBar }
                        shipBar
                        if session.mode == .turnBased { abilityBar }
                    }
                    .frame(maxWidth: wide ? 560 : .infinity)
                    // Джойстик и кнопки — по углам экрана, во всю ширину (и горизонтально).
                    if session.mode == .active { activeControls(wide: wide) }
                }
                .padding(.horizontal, QSpacing.l)
                if let merchant = session.merchantOpen {
                    MerchantView(session: session, merchant: merchant) { withAnimation { session.merchantOpen = nil } }
                        .transition(.opacity)
                }
                if let npc = session.talkNPC {
                    TalkView(session: session, npc: npc)
                        .transition(.opacity)
                }
                if session.shipyardOpen {
                    ShipyardView(session: session).transition(.opacity)
                }
                if session.crewOpen {
                    CrewView(session: session).transition(.opacity)
                }
                if let trader = session.traderOpen {
                    MerchantView(session: session, merchant: IslandMerchant(id: -1 - trader.id, region: 0, cityId: -1, position: trader.position)) {
                        withAnimation { session.traderOpen = nil }
                    }
                    .transition(.opacity)
                }
                if session.isPaused {
                    PauseCard(session: session, exit: exit)
                        .transition(.opacity)
                }
                // Атлас — поверх паузы: открывается и из её меню (исправлено 17.11.2026).
                if session.showsAtlas {
                    AtlasView(session: session) { session.showsAtlas = false }
                        .transition(.opacity)
                        .zIndex(1)
                }
                if showsTasks {
                    TaskListCard(session: session) { showsTasks = false }
                        .transition(.opacity)
                }
                if let monument = session.monumentCard {
                    MonumentCard(monument: monument) { session.monumentCard = nil }
                        .transition(.opacity)
                }
                if let letter = session.letter {
                    LetterCard(bottle: letter) { session.letter = nil }
                        .transition(.opacity)
                }
                if session.isWorldMapOpen {
                    WorldMapView(session: session) { session.isWorldMapOpen = false }
                        .transition(.opacity)
                }
                if session.encounter != nil {
                    EncounterView(session: session) { outcome, npc, tower in
                        scene?.resolveEncounter(outcome, npcId: npc, towerId: tower)
                        // 16.5: бой в зале — победа или поражение выводят из башни, побег — передышка в зале.
                        if hallScene != nil {
                            if outcome == .won || outcome == .lost {
                                session.leaveTower()
                                hallScene = nil
                            } else {
                                hallScene?.calmBoss()
                            }
                        }
                    }
                        .transition(.opacity)
                }
            }
            .onAppear {
                if scene == nil { scene = ExploreScene(session: session, size: proxy.size) }
                OrientationLock.set(.allButUpsideDown)
                demoHall()
            }
            .onDisappear { OrientationLock.set(.portrait) }
        }
        .task(id: session.toast) {
            guard session.toast != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            withAnimation { session.toast = nil }
        }
    }

    private var topBar: some View {
        HStack(spacing: QSpacing.s) {
            Button { withAnimation { session.isPaused = true } } label: {
                Image(systemName: "pause.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(QColor.ink)
                    .frame(width: 44, height: 40)
                    .background(QColor.sheet.opacity(0.94), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Пауза")
            VStack(spacing: 5) {
                bar("HP", value: session.hp, max: session.maxHP, color: QColor.hp)
                bar("MP", value: session.mp, max: session.maxMP, color: QColor.mp)
            }
            .padding(.horizontal, QSpacing.l).padding(.vertical, QSpacing.s)
            .background(QColor.sheet.opacity(0.94), in: RoundedRectangle(cornerRadius: QRadius.card))
        }
    }

    private func bar(_ code: String, value: Double, max: Double, color: Color) -> some View {
        HStack(spacing: QSpacing.s) {
            Text(code).font(QFont.text(11, weight: .bold)).foregroundStyle(color).frame(width: 22, alignment: .leading)
            GeometryReader { p in
                ZStack(alignment: .leading) {
                    Capsule().fill(QColor.track)
                    Capsule().fill(color).frame(width: p.size.width * min(1, value / Swift.max(max, 1)))
                }
            }
            .frame(height: 6)
            Text("\(Int(value.rounded()))/\(Int(max.rounded()))").font(QFont.text(11, weight: .bold)).monospacedDigit().foregroundStyle(QColor.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(code) \(Int(value.rounded())) из \(Int(max.rounded()))")
    }

    /// Масштаб +/− (9.7).
    private var zoomButtons: some View {
        HStack(spacing: 0) {
            Button { session.zoom = max(ExploreSession.zoomRange.lowerBound, session.zoom - 0.1) } label: {
                Image(systemName: "plus").frame(width: 40, height: 36)
            }
            .accessibilityLabel("Крупнее")
            Divider().frame(height: 20)
            Button { session.zoom = min(ExploreSession.zoomRange.upperBound, session.zoom + 0.1) } label: {
                Image(systemName: "minus").frame(width: 40, height: 36)
            }
            .accessibilityLabel("Мельче")
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(QColor.ink)
        .buttonStyle(.plain)
        .background(QColor.sheet.opacity(0.94), in: Capsule())
    }

    private var goals: some View {
        VStack(alignment: .leading, spacing: 2) {
            WrapRow(spacing: QSpacing.l) {
                if session.island.regions.count > 1 { Text("Острова \(session.visitedRegions.count)/\(session.island.regions.count)") }
                if !session.island.cities.isEmpty { Text("Города \(session.visitedCities.count)/\(session.island.cities.count)") }
                if !session.island.chests.isEmpty { Text("Сундуки \(session.openedChests.count)/\(session.island.chests.count)") }
            }
            .font(QFont.text(12, weight: .semibold))
            // Этап 14: часы острова, башни, задания, спутник.
            WrapRow(spacing: QSpacing.m) {
                Text("\(session.isNight ? "☾" : "☀") \(session.clockText)").monospacedDigit().lineLimit(1).fixedSize()
                // 15F.2: текущий шаг главного квеста.
                if let current = session.mainCurrent, !(current.title == "Корабль") {
                    Text("★ \(current.title): \(current.detail)").lineLimit(1).truncationMode(.tail)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: 0xF2D9A8), in: Capsule())
                }
                // 15E: квест «Корабль» и доски.
                if session.hasShipQuest && !session.shipReady {
                    Text("⛵ Корабль: монстры \(session.shipQuestKills)/\(ExploreRules.shipQuestKills)").lineLimit(1).fixedSize()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(QColor.amber.opacity(0.25), in: Capsule())
                }
                if session.planks > 0 { Text("🪵 \(session.planks)").lineLimit(1).fixedSize() }
                if !session.island.towers.isEmpty { Text("Башни \(session.conqueredTowers.count)/\(session.island.towers.count)").lineLimit(1).fixedSize() }
                if !session.island.tasks.isEmpty {
                    Button { showsTasks = true } label: {
                        HStack(spacing: 3) {
                            Text("Задания \(session.doneTasks.count)/\(session.takenTasks.count)").lineLimit(1).fixedSize()
                            Image(systemName: "list.bullet").font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(QColor.amber.opacity(0.25), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Задания: выполнено \(session.doneTasks.count) из \(session.takenTasks.count) взятых")
                }
                if let skill = session.companionSkill {
                    // Умение спутника (15D.4).
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill").foregroundStyle(QColor.forest)
                        Text("\(skill.title) · \(skill.summary)").lineLimit(1).truncationMode(.tail)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Спутник: \(skill.title), \(skill.summary)")
                }
            }
            .font(QFont.text(11, weight: .semibold))
            // Баффы монументов полезного (15G.4) и болото под ногами (15B.3).
            if !session.buffs.isEmpty || session.island.isSwamp(session.heroTile) {
                WrapRow(spacing: 4) {
                    ForEach(ExploreBuff.allCases.filter { session.buffs[$0] != nil }, id: \.self) { buff in
                        Text("\(Self.buffSymbol(buff)) \(buff.effect(session.buffs[buff] ?? 0))").lineLimit(1).fixedSize()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(QColor.forest.opacity(0.18), in: Capsule())
                            .accessibilityLabel("Бафф: \(buff.title), \(buff.effect(session.buffs[buff] ?? 0))")
                    }
                    if session.island.isSwamp(session.heroTile) {
                        Text("Болото: −1% HP/с, шаг медленнее").lineLimit(1).fixedSize()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(QColor.hp.opacity(0.18), in: Capsule())
                    }
                }
                .font(QFont.text(10, weight: .semibold))
            }
        }
        .foregroundStyle(QColor.ink)
        .padding(.horizontal, QSpacing.l).padding(.vertical, QSpacing.s)
        .background(QColor.sheet.opacity(0.94), in: RoundedRectangle(cornerRadius: QRadius.control))
    }

    /// Мини-карта (15H): изометрия, как на экране, герой — в центре окна; север и стороны совпадают с картой мира.
    private var minimap: some View {
        let side = session.island.side
        // 1 px картинки = 0,75 pt: в окне ~53 клетки по ширине.
        let k: CGFloat = 0.75
        let hero = ExploreRenderer.worldMapPoint(session.heroTile, side: side)
        let width = CGFloat(side * 2) * k, height = CGFloat(side + 1) * k
        // Окно фиксированного размера; картинка мира сдвинута так, чтобы герой был в центре.
        return Color(hex: 0x3F6E9C)
            .frame(width: 80, height: 80)
            .overlay(alignment: .topLeading) {
                if let image = session.minimapImage {
                    Image(decorative: image, scale: 1).resizable().interpolation(.none)
                        .frame(width: width, height: height)
                        .offset(x: 40 - hero.x * width, y: 40 - hero.y * height)
                }
            }
            .overlay {
                Rectangle().fill(Color(hex: 0xE2A04A))
                    .frame(width: 6, height: 6)
                    .overlay(Rectangle().strokeBorder(Color(hex: 0x1F2A44), lineWidth: 1))
            }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(QColor.sheet, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { session.isWorldMapOpen = true } }
        .accessibilityLabel("Мини-карта")
        .accessibilityHint("Открыть карту мира")
        .accessibilityAddTraits(.isButton)
    }

    static func buffSymbol(_ buff: ExploreBuff) -> String {
        switch buff {
        case .water: "💧"
        case .walk: "👟"
        case .stretch: "🧘"
        case .vegetables: "🍎"
        case .nap: "🌙"
        case .custom: "⭐"
        }
    }

    /// Сумка (14.5, макет ExploreBag): четыре вида расходников, касание — использовать.
    @ViewBuilder private var bagBar: some View {
        if session.bagCount > 0 {
            HStack(spacing: QSpacing.xs) {
                ForEach(ExploreItem.allCases, id: \.self) { item in
                    let count = session.bag[item] ?? 0
                    Button { session.useItem(item) } label: {
                        VStack(spacing: 1) {
                            Image(systemName: Self.symbol(item)).font(.system(size: 14, weight: .semibold))
                            Text(item.title).font(QFont.text(11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            Text("×\(count)").font(QFont.text(10)).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(count > 0 ? QColor.ink : QColor.inkSecondary)
                        .background(QColor.sheet.opacity(count > 0 ? 0.96 : 0.6), in: RoundedRectangle(cornerRadius: QRadius.small))
                    }
                    .buttonStyle(.plain)
                    .disabled(count == 0)
                    .accessibilityLabel("\(item.title), \(count), \(item.note)")
                }
            }
            .padding(.bottom, QSpacing.s)
        }
    }

    static func symbol(_ item: ExploreItem) -> String {
        switch item {
        case .potionHP: "heart.fill"
        case .potionMP: "drop.fill"
        case .torch: "flame.fill"
        case .compass: "location.north.fill"
        }
    }

    /// «Сесть на корабль» у фрегата, «Сойти на берег» в плавании (12B, макеты ExploreBoarding и ExploreSailing).
    /// Войти в пещеру (15C.2) — у входа или выхода.
    private func enterCave(size: CGSize) {
        session.enterCave()
        guard let id = session.inCave, let cave = session.island.caves.first(where: { $0.id == id }) else { return }
        let cave_ = CaveScene(session: session, cave: cave, size: size)
        cave_.onLeave = { [session] in
            if let tile = session.leaveCave() { scene?.placeHero(at: tile) }
            session.toast = "Выход из пещеры"
            caveScene = nil
        }
        caveScene = cave_
    }

    /// Отладка: `-QuestlynExploreDemo boss hall` — сразу в зал финальной башни.
    private func demoHall() {
        #if DEBUG
        guard UserDefaults.standard.string(forKey: "QuestlynExploreDemo")?.contains("hall") == true, hallScene == nil else { return }
        session.encounter = nil
        session.encounterNPC = nil
        enterTower(size: scene?.size ?? CGSize(width: 390, height: 844))
        #endif
    }

    /// Войти в зал Чёрной башни (16.5).
    private func enterTower(size: CGSize) {
        session.enterTower()
        guard let id = session.inTower, let tower = session.island.towers.first(where: { $0.id == id }) else { return }
        let hall = HallScene(session: session, tower: tower, size: size)
        hall.onLeave = { [session] in
            session.leaveTower()
            session.toast = "Вы вышли из башни"
            hallScene = nil
        }
        hall.onBoss = { [session] in session.startGuardian(tower) }
        hallScene = hall
    }

    @ViewBuilder private var shipBar: some View {
        if let id = session.talkCandidate, session.talkNPC == nil, let npc = session.island.npcs.first(where: { $0.id == id }) {
            // 15H: мирный NPC рядом — поговорить, чтобы позвать в спутники.
            Button { withAnimation { session.talkNPC = npc } } label: {
                VStack(spacing: 2) {
                    Text("Поговорить").font(QFont.text(15, weight: .bold))
                    Text(npc.title + (npc.meetings > 0 ? " · \(Format.meetings(npc.meetings))" : "")).font(QFont.text(11))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(QColor.sheet)
                .background(QColor.forest, in: RoundedRectangle(cornerRadius: QRadius.card))
            }
            .buttonStyle(.plain)
            .padding(.bottom, QSpacing.s)
        }
        if let merchant = session.nearbyMerchant {
            Button { withAnimation { session.merchantOpen = merchant } } label: {
                VStack(spacing: 2) {
                    Text("Торговец").font(QFont.text(15, weight: .bold))
                    Text("обмен 2 → 1 · хранилище").font(QFont.text(11))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(QColor.ink)
                .background(Color(hex: 0xE2A04A), in: RoundedRectangle(cornerRadius: QRadius.card))
            }
            .buttonStyle(.plain)
            .padding(.bottom, QSpacing.s)
        }
        if let tower = session.enterableTower {
            Button { enterTower(size: scene?.size ?? CGSize(width: 390, height: 844)) } label: {
                VStack(spacing: 2) {
                    Text("Войти в башню").font(QFont.text(15, weight: .bold))
                    Text(tower.isFinal ? "финальный босс" : "Чёрная башня «\(tower.title)»").font(QFont.text(11)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(QColor.sheet)
                .background(Color(hex: 0x2B2B35), in: RoundedRectangle(cornerRadius: QRadius.card))
            }
            .buttonStyle(.plain)
            .padding(.bottom, QSpacing.s)
        }
        if session.enterableCave != nil {
            Button { enterCave(size: scene?.size ?? CGSize(width: 390, height: 844)) } label: {
                VStack(spacing: 2) {
                    Text("Войти в пещеру").font(QFont.text(15, weight: .bold))
                    Text("темно — пригодится факел").font(QFont.text(11))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(QColor.sheet)
                .background(QColor.ink, in: RoundedRectangle(cornerRadius: QRadius.card))
            }
            .buttonStyle(.plain)
            .padding(.bottom, QSpacing.s)
        }
        if session.sailing != nil {
            let canLand = session.landingTile != nil
            Button { scene?.disembark() } label: {
                VStack(spacing: 2) {
                    Text("Сойти на берег").font(QFont.text(15, weight: .bold))
                    Text(canLand ? "корабль останется здесь" : "подплывите к берегу").font(QFont.text(11))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(canLand ? QColor.ink : QColor.inkSecondary)
                .background(canLand ? Color(hex: 0xE2A04A) : QColor.sheet.opacity(0.94), in: RoundedRectangle(cornerRadius: QRadius.card))
            }
            .buttonStyle(.plain)
            .disabled(!canLand)
            .padding(.bottom, QSpacing.s)
        } else if session.boardableShip != nil {
            Button { scene?.boardShip() } label: {
                VStack(spacing: 2) {
                    Text("Сесть на корабль").font(QFont.text(15, weight: .bold))
                    Text("управление — кораблём").font(QFont.text(11))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(QColor.ink)
                .background(Color(hex: 0xE2A04A), in: RoundedRectangle(cornerRadius: QRadius.card))
            }
            .buttonStyle(.plain)
            .padding(.bottom, QSpacing.s)
        }
        seaButtons
    }

    /// 15E: верфь, экипаж, встречный корабль; корабль у причала, пока квест не выполнен.
    @ViewBuilder private var seaButtons: some View {
        HStack(spacing: QSpacing.s) {
            if session.nearbyShipyard {
                pill("Верфь", note: "🪵 \(session.planks) · улучшения") { session.shipyardOpen = true }
            }
            if session.nearShip {
                pill("Экипаж", note: "\(session.crew.count)/\(ExploreRules.crewCap)") { session.crewOpen = true }
            }
            if let trader = session.nearbyTrader {
                pill("Обмен", note: "встречный корабль") { session.traderOpen = trader }
                if !session.traderGifts.contains(trader.id) {
                    pill("Доска", note: "в подарок") { session.takeGift(trader) }
                }
            }
        }
        .padding(.bottom, QSpacing.s)
        if session.hasShipQuest, !session.shipReady, session.sailing == nil,
           let ship = session.ships.first, ship.distance(to: session.heroTile) <= ExploreRules.boardRadius + 1 {
            Text("Корабль ещё не готов: победи монстров острова \(session.shipQuestKills)/\(ExploreRules.shipQuestKills)")
                .font(QFont.text(13, weight: .semibold)).foregroundStyle(QColor.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(QColor.sheet.opacity(0.94), in: RoundedRectangle(cornerRadius: QRadius.card))
                .padding(.bottom, QSpacing.s)
        }
    }

    private func pill(_ title: String, note: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation { action() } } label: {
            VStack(spacing: 2) {
                Text(title).font(QFont.text(15, weight: .bold))
                Text(note).font(QFont.text(11)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(QColor.sheet)
            .background(QColor.ink, in: RoundedRectangle(cornerRadius: QRadius.card))
        }
        .buttonStyle(.plain)
    }

    /// Активный режим (макет ExploreActive): джойстик слева, «Удар» и способности справа.
    private func activeControls(wide: Bool) -> some View {
        HStack(alignment: .bottom) {
            JoystickView(session: session)
            Spacer(minLength: QSpacing.l)
            if wide {
                bagBar.frame(maxWidth: 360)
                Spacer(minLength: QSpacing.l)
            }
            ActiveActionsView(session: session)
        }
        .padding(.bottom, QSpacing.l)
    }

    @ViewBuilder private var abilityBar: some View {
        let skills = session.hero.skills
        if !skills.isEmpty {
            HStack(spacing: QSpacing.s) {
                ForEach(skills) { skill in
                    let onMap = skill.ability == .dash || skill.ability == .scout
                    Button { session.useOnMap(skill) } label: {
                        VStack(spacing: 2) {
                            Text(skill.ability.title).font(QFont.text(14, weight: .bold))
                            Text(session.sailing != nil ? "на корабле — нет" : onMap ? "\(skill.title) · −\(Int((skill.ability.mpShare * session.maxMP).rounded())) MP" : "только во встрече")
                                .font(QFont.text(11)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(session.canUseOnMap(skill) ? QColor.sheet : QColor.inkSecondary)
                        .background(session.canUseOnMap(skill) ? QColor.ink : QColor.sheet.opacity(0.94), in: RoundedRectangle(cornerRadius: QRadius.card))
                    }
                    .buttonStyle(.plain)
                    .disabled(!session.canUseOnMap(skill))
                }
            }
            .padding(.bottom, QSpacing.l)
        }
    }
}

// MARK: - Встреча (8B.3)

struct EncounterView: View {
    @Bindable var session: ExploreSession
    let resolved: (EncounterOutcome?, Int?, Int?) -> Void
    @State private var showsSkills = true

    var body: some View {
        if let encounter = session.encounter {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(alignment: .leading, spacing: QSpacing.m) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Встреча · ход \(encounter.turn)").font(QFont.text(11, weight: .bold)).textCase(.uppercase).tracking(0.6)
                            .foregroundStyle(QColor.hp)
                        Spacer()
                        if encounter.guardian == nil {
                            Text("встречались в событиях: \(npcMeetings)").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                        } else {
                            Text("Чёрная башня").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                        }
                    }
                    Text(title(encounter)).font(QFont.title(18, weight: .bold))
                    HStack(spacing: QSpacing.l) {
                        meter("Вы", value: encounter.heroHP, max: session.maxHP, color: QColor.hp)
                        meter(encounter.opponentTitle, value: encounter.npcHP, max: encounter.npcMaxHP, color: QColor.hp)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(encounter.log.suffix(3).enumerated()), id: \.offset) { _, line in
                            Text(line).font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                        }
                    }
                    if encounter.outcome == nil { actions(encounter) } else {
                        Button("Продолжить") {
                            let npc = session.encounterNPC, tower = session.encounterTower
                            let outcome = session.finishEncounter()
                            resolved(outcome, npc, tower)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    Text("Поражение — герой приходит в себя у корабля (до квеста — на старте), ничего не теряется.")
                        .font(QFont.text(11)).foregroundStyle(QColor.inkSecondary)
                }
                .foregroundStyle(QColor.ink)
                .padding(QSpacing.xl)
                .frame(maxWidth: 600)
                .background(QColor.sheet)
                .overlay(Rectangle().strokeBorder(QColor.ink, lineWidth: 3))
                .background(Color.black.opacity(0.35).offset(x: 4, y: 4))
                .padding(QSpacing.l)
                .padding(.bottom, QSpacing.xl)
            }
            .accessibilityAddTraits(.isModal)
        }
    }

    private var npcMeetings: Int {
        session.encounterNPC.flatMap { id in session.island.npcs.first { $0.id == id }?.meetings } ?? 1
    }

    private func title(_ encounter: Encounter) -> String {
        switch encounter.outcome {
        case .won: "Победа"
        case .persuaded: "Разошлись миром"
        case .fled: "Вы оторвались"
        case .lost: "Без сил"
        case nil:
            if let name = encounter.opponentName { name == "Морской змей" || name == "Пираты" ? "\(name) атакуют" : "\(name) преграждает путь" }
            else { encounter.guardian.map { "Страж башни «\($0.title)»" } ?? "\(encounter.tier.title) преградил путь" }
        }
    }

    private func meter(_ title: String, value: Double, max: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(QFont.text(12, weight: .semibold))
                Spacer()
                Text("\(Int(value.rounded()))/\(Int(max.rounded()))").font(QFont.text(12, weight: .bold)).monospacedDigit()
            }
            GeometryReader { p in
                ZStack(alignment: .leading) {
                    Rectangle().fill(QColor.track)
                    Rectangle().fill(color).frame(width: p.size.width * min(1, value / Swift.max(max, 1)))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func actions(_ encounter: Encounter) -> some View {
        HStack(spacing: QSpacing.s) {
            actionButton("Сражаться", note: "удар \(encounter.strikeRange.lowerBound)–\(encounter.strikeRange.upperBound)", filled: true) {
                session.encounter?.perform(.fight)
            }
            actionButton("Навык", note: "\(session.fightSkills.filter { encounter.isReady($0) }.count) готовы", filled: false, accent: true) {
                showsSkills.toggle()
            }
            .disabled(session.fightSkills.isEmpty)
            actionButton("Бежать", note: "шанс \(Int((encounter.escapeChance * 100).rounded()))%", filled: false) {
                session.encounter?.perform(.flee)
            }
        }
        if showsSkills, !session.fightSkills.isEmpty {
            VStack(spacing: 0) {
                ForEach(session.fightSkills) { skill in
                    Button { session.encounter?.perform(.ability(skill)) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(skill.ability.title) · \(skill.title) ×\(Self.power(skill.power))").font(QFont.text(14, weight: .bold))
                                Text(skillNote(skill, encounter)).font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                            }
                            Spacer()
                            Text("−\(Int(encounter.cost(skill.ability))) MP").font(QFont.text(12, weight: .bold)).foregroundStyle(QColor.mp)
                        }
                        .padding(.horizontal, QSpacing.l).frame(minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!encounter.isReady(skill))
                    .opacity(encounter.isReady(skill) ? 1 : 0.45)
                    .overlay(alignment: .bottom) { Rectangle().fill(QColor.ink).frame(height: 2) }
                }
            }
            .overlay(Rectangle().strokeBorder(QColor.ink, lineWidth: 2))
        }
    }

    private func skillNote(_ skill: ExploreSkill, _ encounter: Encounter) -> String {
        if let wait = encounter.cooldowns[skill.ability], wait > 0 { return "перезарядка: \(wait) хода" }
        if skill.ability == .persuade { return "шанс \(Int((encounter.persuadeChance(power: skill.power) * 100).rounded()))% — NPC станет мирным" }
        return skill.ability.summary
    }

    private func actionButton(_ title: String, note: String, filled: Bool, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(QFont.text(14, weight: .bold))
                Text(note).font(QFont.text(11)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(filled ? QColor.sheet : QColor.ink)
            .background(filled ? QColor.ink : accent ? Color(hex: 0xE2A04A) : QColor.sheet)
            .overlay(Rectangle().strokeBorder(QColor.ink, lineWidth: 3))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Итог (8B.4)

struct ExploreSummaryView: View {
    let session: ExploreSession
    let again: () -> Void
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.l) {
                VStack(alignment: .leading, spacing: QSpacing.xs) {
                    Text("Прогулка окончена").font(QFont.text(12, weight: .semibold)).textCase(.uppercase).tracking(0.7).foregroundStyle(QColor.amberDeep)
                    Text("\(session.island.regions.count > 1 ? "Архипелаг" : "Остров") \(Format.shortDay(session.input.first)) — \(Format.shortDay(session.input.last))").font(QFont.title(26))
                    Text("\(Format.dayCount(session.input.days)) · \(ExploreSetupView.title(session.island).lowercased()) · \(minutes) мин в пути")
                        .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                }
                HStack(spacing: QSpacing.s) {
                    goal("Городов посещено", session.visitedCities.count, session.island.cities.count)
                    goal("Сундуков найдено", session.openedChests.count, session.island.chests.count)
                }
                VStack(spacing: 0) {
                    if session.island.regions.count > 1 { row("Островов посещено", session.visitedRegions.count) }
                    if !session.island.bottles.isEmpty { row("Бутылок найдено", session.readBottles.count) }
                    if !session.island.towers.isEmpty { row("Башен взято", session.conqueredTowers.count) }
                    if session.finalTower != nil {
                        HStack {
                            Text(session.isArchipelagoPassed ? "🏆 Архипелаг пройден" : "Финальная башня").font(QFont.text(15, weight: session.isArchipelagoPassed ? .bold : .regular))
                            Spacer()
                            Text(session.isArchipelagoPassed ? "босс повержен" : "не взята").font(QFont.text(15, weight: .bold))
                                .foregroundStyle(session.isArchipelagoPassed ? QColor.forest : QColor.inkSecondary)
                        }
                        .padding(.horizontal, QSpacing.xl).frame(minHeight: 44)
                        .overlay(alignment: .bottom) { Divider().overlay(QColor.line) }
                    }
                    if !session.buffs.isEmpty { row("Монументов полезного", session.buffs.count) }
                    // 15C.
                    if let treasure = session.island.treasure {
                        textRow(session.treasureFound ? "Клад «\(treasure.title)»" : "Клад", session.treasureFound ? "найден" : "обрывков \(session.fragmentsFound.count)/\(session.fragmentsTotal)")
                    }
                    if !session.island.caves.isEmpty { row("Пещер пройдено", session.visitedCaves.count) }
                    if !session.island.lookouts.isEmpty { row("Смотровых площадок", session.usedLookouts.count) }
                    textRow("Атлас", "\(Int((session.exploredShare * 100).rounded()))% мира")
                    if !session.island.lighthouses.isEmpty { row("Маяков зажжено", session.litLighthouses.count) }
                    if !session.island.tasks.isEmpty { row("Заданий выполнено", session.doneTasks.count) }
                    row("Побед", session.wins)
                    row("Уговорено", session.persuaded)
                    if !session.recruitedLegends.isEmpty { row("Легенды-спутники", session.recruitedLegends.count) }
                    if session.shipReady { row("Улучшений корабля", session.upgrades.count) }
                    if session.serpentDefeated { row("Морской змей повержен", 1) }
                    if !session.errandsDone.isEmpty { row("Поручений Epic выполнено", session.errandsDone.count) }
                    if session.walkCompleted { row("🏆 Прогулка пройдена", 1) }
                    row("Убежал", session.escapes)
                    row("Поражений", session.defeats)
                    row("Костров зажжено", session.litCampfires.count)
                    row("Пройдено клеток", session.steps)
                }
                .sheetCard()
                let found = session.island.chests.filter { session.openedChests.contains($0.id) }
                if !found.isEmpty {
                    CapsHeader(title: "Найденные сундуки")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(found) { chest in
                            Text(chest.title).font(QFont.text(15)).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                                .padding(.horizontal, QSpacing.xl)
                                .overlay(alignment: .bottom) { Divider().overlay(QColor.line) }
                        }
                    }
                    .sheetCard()
                }
                Text("Это была песочница: XP, HP, MP и Летопись героя не изменились. Итог не сохраняется.")
                    .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                    .padding(QSpacing.l).frame(maxWidth: .infinity, alignment: .leading)
                    .background(QColor.track, in: RoundedRectangle(cornerRadius: QRadius.card))
                Button("Побродить ещё — другой остров", action: again).buttonStyle(PrimaryButtonStyle())
                Button("К карте", action: close).buttonStyle(SecondaryButtonStyle())
            }
            .padding(QSpacing.screen)
            .padding(.top, QSpacing.xl)
        }
        .paperScreen()
    }

    private var minutes: Int { max(1, Int(Date.now.timeIntervalSince(session.startedAt) / 60)) }

    private func textRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(QFont.text(15)).lineLimit(1)
            Spacer()
            Text(value).font(QFont.text(15, weight: .bold))
        }
        .padding(.horizontal, QSpacing.xl).frame(minHeight: 44)
        .overlay(alignment: .bottom) { Divider().overlay(QColor.line) }
    }

    private func goal(_ title: String, _ value: Int, _ total: Int) -> some View {
        VStack(alignment: .leading, spacing: QSpacing.s) {
            Text(title).font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            Text("\(value) из \(total)").font(QFont.title(22))
            GeometryReader { p in
                ZStack(alignment: .leading) {
                    Capsule().fill(QColor.track)
                    Capsule().fill(QColor.amber).frame(width: p.size.width * (total == 0 ? 0 : Double(value) / Double(total)))
                }
            }
            .frame(height: 6)
        }
        .padding(QSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheetCard()
    }

    private func row(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title).font(QFont.text(15)).foregroundStyle(QColor.inkSecondary)
            Spacer()
            Text("\(value)").font(QFont.text(15, weight: .bold)).monospacedDigit()
        }
        .padding(.horizontal, QSpacing.xl).frame(minHeight: 46)
        .overlay(alignment: .bottom) { Divider().overlay(QColor.line) }
    }
}

/// Письмо из бутылки (14.5): заметка «Дневника» — дата, настроение, текст.
struct LetterCard: View {
    let bottle: IslandBottle
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: QSpacing.m) {
                Text("Письмо в бутылке").font(QFont.text(11, weight: .bold)).textCase(.uppercase).tracking(0.6).foregroundStyle(QColor.mp)
                HStack(spacing: QSpacing.s) {
                    Image(systemName: WeatherStyle.symbol(Weather.from(bottle.note.mood, on: bottle.note.date)))
                    Text("\(Format.shortDay(bottle.note.date)) · \(bottle.note.mood.title)").font(QFont.text(15, weight: .bold))
                }
                Text(bottle.note.note).font(QFont.title(18)).fixedSize(horizontal: false, vertical: true)
                Button("Дальше", action: close).buttonStyle(PrimaryButtonStyle())
            }
            .foregroundStyle(QColor.ink)
            .padding(QSpacing.xl)
            .background(QColor.paper, in: RoundedRectangle(cornerRadius: QRadius.card))
            .padding(QSpacing.xl)
        }
        .accessibilityAddTraits(.isModal)
    }
}

/// Задания досок (16.11.2026): что взято, что нужно сделать и прогресс. Условия считаются за всю прогулку.
struct TaskListCard: View {
    let session: ExploreSession
    let close: () -> Void

    private var taken: [CityTask] { session.takenTasks.compactMap { id in session.island.tasks.first { $0.id == id } } }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: QSpacing.m) {
                HStack {
                    Text("Задания досок").font(QFont.title(20))
                    Spacer()
                    Text("\(session.doneTasks.count) из \(taken.count)").font(QFont.text(13, weight: .semibold)).monospacedDigit()
                }
                // 15F.1: взятые поручения Epic — шаги по порядку.
                ForEach(session.island.errands.filter { session.errandStep[$0.id] != nil }) { errand in
                    errandCard(errand)
                }
                if taken.isEmpty {
                    Text("Пока ни одного. Задание берётся при первом входе в город с доской.")
                        .font(QFont.text(14)).foregroundStyle(QColor.inkSecondary)
                } else {
                    // Мало заданий — карточка по содержимому, много — прокрутка.
                    ViewThatFits(in: .vertical) {
                        VStack(spacing: QSpacing.s) { ForEach(taken) { task in row(task) } }
                        ScrollView {
                            VStack(spacing: QSpacing.s) { ForEach(taken) { task in row(task) } }
                        }
                    }
                    .frame(maxHeight: 360)
                    .fixedSize(horizontal: false, vertical: taken.count <= 4)
                }
                let left = session.island.tasks.count - taken.count
                if left > 0 {
                    Text("Ещё не взято: \(left). Награда за каждое — +\(Int(ExploreRules.taskRewardShare * 100))% HP и MP.")
                        .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                }
                Button("Закрыть", action: close).buttonStyle(SecondaryButtonStyle())
            }
            .foregroundStyle(QColor.ink)
            .padding(QSpacing.xl)
            .background(QColor.paper, in: RoundedRectangle(cornerRadius: QRadius.card))
            .padding(QSpacing.l)
        }
        .accessibilityAddTraits(.isModal)
    }

    private func errandCard(_ errand: IslandErrand) -> some View {
        let current = session.errandStep[errand.id] ?? 0
        let finished = session.errandsDone.contains(errand.id)
        let city = session.island.cities.indices.contains(errand.cityId) ? session.island.cities[errand.cityId].name : ""
        return VStack(alignment: .leading, spacing: 6) {
            Text("Поручение Epic «\(errand.epicTitle)» · доска «\(city)»").font(QFont.text(13, weight: .bold))
            ForEach(Array(errand.steps.enumerated()), id: \.offset) { index, step in
                let done = finished || index < current
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: done ? "checkmark.circle.fill" : index == current ? "circle" : "lock.circle")
                        .foregroundStyle(done ? QColor.forest : index == current ? QColor.amberDeep : QColor.inkSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(index == errand.steps.count - 1 ? "Финал · \(step.title)" : "Шаг \(index + 1) · «\(step.title)»")
                            .font(QFont.text(13, weight: .semibold))
                        let progress = index == current && !finished ? session.errandProgress(errand) : nil
                        Text(session.errandText(step) + (progress.map { $0.total > 1 ? " · \($0.done)/\($0.total)" : "" } ?? ""))
                            .font(QFont.text(11)).foregroundStyle(QColor.inkSecondary)
                    }
                }
            }
        }
        .padding(QSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
    }

    private func row(_ task: CityTask) -> some View {
        let state = session.progress(task)
        let done = session.doneTasks.contains(task.id)
        return HStack(spacing: QSpacing.m) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(done ? QColor.forest : QColor.inkSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.taskTitle(task)).font(QFont.text(15, weight: .semibold))
                    .strikethrough(done, color: QColor.inkSecondary)
                Text("Доска «\(session.cityName(task))»").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(done ? "готово" : "\(state.done)/\(state.total)")
                .font(QFont.text(13, weight: .bold)).monospacedDigit()
                .foregroundStyle(done ? QColor.forest : QColor.ink)
        }
        .padding(QSpacing.m)
        .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Карта мира (15A.3, макет ExploreWorldMap)

/// Весь мир в изометрии, как на экране: неоткрытое — под туманом; города, задания, корабли, герой. Игра на паузе.
struct WorldMapView: View {
    let session: ExploreSession
    let close: () -> Void
    @State private var showsCities = true
    @State private var showsTasks = true
    @State private var showsChests = false
    @State private var showsShips = true
    @State private var image: CGImage?
    @State private var scale: CGFloat = 1
    @State private var position = ScrollPosition()
    @GestureState private var pinch: CGFloat = 1

    init(session: ExploreSession, close: @escaping () -> Void) {
        self.session = session
        self.close = close
        // Картинка готова до первого кадра — окно открывается без пустой вспышки.
        _image = State(initialValue: session.worldMapImage)
    }

    var body: some View {
        GeometryReader { outer in
            let wide = outer.size.width > outer.size.height
            Group {
                if wide {
                    HStack(alignment: .top, spacing: QSpacing.l) {
                        mapArea
                        VStack(alignment: .leading, spacing: QSpacing.m) {
                            header
                            filters
                            legend
                            Spacer(minLength: 0)
                            Button("К герою", action: close).buttonStyle(PrimaryButtonStyle())
                        }
                        .frame(width: 280)
                    }
                } else {
                    VStack(alignment: .leading, spacing: QSpacing.m) {
                        header
                        filters
                        mapArea
                        legend
                        Text("Неоткрытое — под туманом. Щипок или +/− — масштаб. Игра на паузе, пока открыта карта.")
                            .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                        Button("К герою", action: close).buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
        }
        .padding(QSpacing.screen)
        .background(QColor.paper.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Карта мира").font(QFont.title(20))
                Text(subtitle).font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44)
                    .background(QColor.sheet, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Закрыть")
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: QSpacing.s) {
                chip("Города", $showsCities)
                chip("Задания", $showsTasks)
                chip("Сундуки", $showsChests)
                if !session.island.ships.isEmpty { chip("Корабли", $showsShips) }
            }
        }
    }

    /// Карта: щипок и кнопки +/−; при смене масштаба герой — в центре.
    private var mapArea: some View {
        GeometryReader { proxy in
            // Масштаб 1 — весь мир в окне; крупнее — прокрутка, герой в центре.
            let width = min(proxy.size.width, proxy.size.height * 2) * scale * pinch, height = width / 2
            let hero = ExploreRenderer.worldMapPoint(session.heroTile, side: session.island.side)
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    if let image {
                        Image(decorative: image, scale: 1).resizable().interpolation(scale > 2 ? .none : .medium)
                            .frame(width: width, height: height)
                    }
                    markers(width: width, height: height)
                }
                .frame(width: width, height: height)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
            .scrollPosition($position)
            .task(id: scale) {
                // Герой — в центре окна (с поправкой на края карты).
                try? await Task.sleep(for: .milliseconds(60))
                let x = min(max(0, hero.x * width - proxy.size.width / 2), max(0, width - proxy.size.width))
                let y = min(max(0, hero.y * height - proxy.size.height / 2), max(0, height - proxy.size.height))
                withAnimation { position.scrollTo(point: CGPoint(x: x, y: y)) }
            }
            .gesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { scale = min(Self.maxScale, max(1, scale * $0.magnification)) })
            .overlay(alignment: .bottomTrailing) { zoomButtons.padding(QSpacing.s) }
        }
        .background(Color(hex: 0x3F6E9C), in: RoundedRectangle(cornerRadius: QRadius.card))
        .clipShape(RoundedRectangle(cornerRadius: QRadius.card))
    }

    static let maxScale: CGFloat = 6

    private var zoomButtons: some View {
        VStack(spacing: 0) {
            Button { scale = min(Self.maxScale, scale * 1.5) } label: {
                Image(systemName: "plus").frame(width: 44, height: 40)
            }
            .disabled(scale >= Self.maxScale)
            .accessibilityLabel("Крупнее")
            Divider().frame(width: 24)
            Button { scale = max(1, scale / 1.5) } label: {
                Image(systemName: "minus").frame(width: 44, height: 40)
            }
            .disabled(scale <= 1)
            .accessibilityLabel("Мельче")
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(QColor.ink)
        .buttonStyle(.plain)
        .background(QColor.sheet.opacity(0.95), in: RoundedRectangle(cornerRadius: QRadius.control))
    }

    private var subtitle: String {
        let regions = session.island.regions.count
        let share = Int((session.exploredShare * 100).rounded())
        return "Открыто \(share)%" + (regions > 1 ? " · \(regions) \(regions < 5 ? "острова" : "островов")" : "") + " · \(session.clockText)"
    }

    private func isOpen(_ point: TilePoint) -> Bool {
        let index = point.y * session.island.side + point.x
        return session.explored.indices.contains(index) && session.explored[index]
    }

    @ViewBuilder private func markers(width: CGFloat, height: CGFloat) -> some View {
        let side = session.island.side
        let place = { (point: TilePoint) -> CGPoint in
            let p = ExploreRenderer.worldMapPoint(point, side: side)
            return CGPoint(x: p.x * width, y: p.y * height)
        }
        if showsCities {
            ForEach(session.island.cities.filter { isOpen($0.center) }) { city in
                let p = place(city.center)
                RoundedRectangle(cornerRadius: 2).fill(QColor.ink).frame(width: 9, height: 9)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(QColor.sheet, lineWidth: 1.5))
                    .position(p)
                Text(city.name).font(QFont.text(10, weight: .bold)).lineLimit(1).fixedSize()
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(QColor.sheet.opacity(0.9), in: Capsule())
                    .position(x: p.x, y: p.y - 12)
            }
        }
        if showsTasks {
            ForEach(session.island.tasks.filter { session.takenTasks.contains($0.id) && !session.doneTasks.contains($0.id) }) { task in
                if let city = session.island.cities.first(where: { $0.id == task.cityId }) {
                    Text("!").font(QFont.text(11, weight: .bold)).foregroundStyle(QColor.sheet)
                        .frame(width: 16, height: 16).background(QColor.amberDeep, in: Circle())
                        .position(x: place(city.center).x + 10, y: place(city.center).y - 24)
                }
            }
        }
        if showsChests {
            ForEach(session.island.chests.filter { isOpen($0.position) && !session.openedChests.contains($0.id) }) { chest in
                Rectangle().fill(QColor.amber).frame(width: 5, height: 5).position(place(chest.position))
            }
        }
        if showsShips {
            ForEach(Array(session.ships.enumerated()), id: \.offset) { index, ship in
                if index != session.sailing {
                    Image(systemName: "sailboat.fill").font(.system(size: 10)).foregroundStyle(Color(hex: 0x6B3F22)).position(place(ship))
                }
            }
        }
        if let spot = session.treasureSpot, !session.treasureFound {
            Text("✕").font(QFont.text(16, weight: .heavy)).foregroundStyle(Color(hex: 0xA8281E)).position(place(spot))
                .accessibilityLabel("Клад")
        }
        ZStack {
            Circle().fill(QColor.amber.opacity(0.3)).frame(width: 22, height: 22)
            Circle().fill(QColor.amber).frame(width: 10, height: 10).overlay(Circle().strokeBorder(QColor.sheet, lineWidth: 2))
        }
        .position(place(session.heroTile))
        .accessibilityLabel("Герой")
    }

    private var legend: some View {
        HStack(spacing: QSpacing.m) {
            HStack(spacing: 4) { Circle().fill(QColor.amber).frame(width: 9, height: 9); Text("Ты") }
            HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(QColor.ink).frame(width: 9, height: 9); Text("Город") }
            HStack(spacing: 4) {
                Text("!").font(QFont.text(9, weight: .bold)).foregroundStyle(QColor.sheet).frame(width: 13, height: 13).background(QColor.amberDeep, in: Circle())
                Text("Задание")
            }
            HStack(spacing: 4) { Rectangle().fill(Color(hex: 0x9A7A4E)).frame(width: 14, height: 5); Text("Дорога") }
        }
        .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
    }

    private func chip(_ title: String, _ isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Text(title).font(QFont.text(12, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? QColor.sheet : QColor.ink)
                .padding(.horizontal, QSpacing.l).frame(height: 32)
                .background(isOn.wrappedValue ? QColor.ink : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn.wrappedValue ? .clear : QColor.lineStrong))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }
}

// MARK: - Пауза (16.11.2026)

/// Игра стоит: часы, NPC и восстановление не идут.
struct PauseCard: View {
    let session: ExploreSession
    let exit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: QSpacing.m) {
                Text("Пауза").font(QFont.title(22))
                Text("Время на острове стоит, NPC не двигаются.").font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                    .multilineTextAlignment(.center)
                // 15F.2: главный квест — по шагам (длинный — прокрутка, чтобы пауза помещалась и горизонтально).
                ScrollView { VStack(alignment: .leading, spacing: 6) {
                    Text("Главный квест · \(session.mainSteps.filter(\.done).count) из \(session.mainSteps.count)").font(QFont.text(13, weight: .bold))
                    ForEach(session.mainSteps) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: step.done ? "checkmark.circle.fill" : step.id == session.mainCurrent?.id ? "circle" : "lock.circle")
                                .foregroundStyle(step.done ? QColor.forest : step.id == session.mainCurrent?.id ? QColor.amberDeep : QColor.inkSecondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(step.title).font(QFont.text(13, weight: .semibold))
                                Text(step.detail).font(QFont.text(11)).foregroundStyle(QColor.inkSecondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(QSpacing.m) }
                .frame(maxHeight: 230)
                .fixedSize(horizontal: false, vertical: session.mainSteps.count <= 4)
                .background(QColor.paper, in: RoundedRectangle(cornerRadius: QRadius.control))
                Button("Продолжить") { withAnimation { session.isPaused = false } }.buttonStyle(PrimaryButtonStyle())
                Button("Карта мира") { session.isPaused = false; withAnimation { session.isWorldMapOpen = true } }
                    .font(QFont.text(15, weight: .semibold)).foregroundStyle(QColor.ink).frame(minHeight: 44)
                Button("Атлас") { withAnimation { session.showsAtlas = true } }
                    .font(QFont.text(15, weight: .semibold)).foregroundStyle(QColor.ink).frame(minHeight: 44)
                Button("Выйти с острова", action: exit)
                    .font(QFont.text(15, weight: .semibold)).foregroundStyle(QColor.hp).frame(minHeight: 44)
            }
            .padding(QSpacing.xl)
            .frame(maxWidth: 340)
            .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.card))
            .padding(QSpacing.xl)
        }
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Активный режим: джойстик и кнопки (16.11.2026, макеты ExploreActive)

/// Джойстик: тянуть от центра — герой идёт в эту сторону, отпустить — стоит.
struct JoystickView: View {
    let session: ExploreSession
    @State private var knob = CGSize.zero
    static let size: CGFloat = 120
    private var radius: CGFloat { Self.size / 2 - 22 }

    var body: some View {
        ZStack {
            Circle().fill(QColor.sheet.opacity(0.22))
                .overlay(Circle().strokeBorder(QColor.sheet.opacity(0.75), lineWidth: 2))
            Circle().fill(QColor.sheet.opacity(0.95)).frame(width: 50, height: 50)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                .offset(knob)
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                var dx = value.location.x - Self.size / 2, dy = value.location.y - Self.size / 2
                let length = hypot(dx, dy)
                if length > radius { dx = dx / length * radius; dy = dy / length * radius }
                knob = CGSize(width: dx, height: dy)
                session.stick = CGVector(dx: dx / radius, dy: dy / radius)
            }
            .onEnded { _ in
                withAnimation(.spring(duration: 0.2)) { knob = .zero }
                session.stick = .zero
            })
        .accessibilityElement()
        .accessibilityLabel("Джойстик")
        .accessibilityHint("Перетащите, чтобы идти")
    }
}

/// «Удар» и способности: в бою — по противнику, без боя — «Рывок» и «Разведка» как на карте.
struct ActiveActionsView: View {
    let session: ExploreSession

    var body: some View {
        let fight = session.activeFight
        let canStrike = fight.map { $0.strikeCooldown <= 0 && session.activeDistance <= ExploreRules.activeRange } ?? false
        HStack(alignment: .bottom, spacing: QSpacing.s) {
            VStack(spacing: QSpacing.s) {
                ForEach(session.fightSkills) { skill in
                    let ready = fight.map { $0.isReady(skill) } ?? session.canUseOnMap(skill)
                    let left = fight.map { ($0.cooldowns[skill.ability] ?? 0) / max(0.01, $0.abilityCooldown) } ?? 0
                    Button { session.activeUse(skill) } label: {
                        VStack(spacing: 0) {
                            Text(Self.short(skill.ability)).font(QFont.text(11, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                            Text("−\(Int((skill.ability.mpShare * session.maxMP).rounded())) MP").font(QFont.text(9))
                        }
                        .foregroundStyle(QColor.ink)
                        .frame(width: 58, height: 58)
                        .background(QColor.sheet.opacity(0.94), in: Circle())
                        .overlay(Circle().trim(from: 0, to: left).stroke(Color(hex: 0xE2A04A), lineWidth: 3).rotationEffect(.degrees(-90)))
                        .opacity(ready ? 1 : 0.55)
                    }
                    .buttonStyle(.plain)
                    .disabled(!ready)
                    .accessibilityLabel(skill.ability.title)
                }
            }
            Button { session.activeStrike() } label: {
                VStack(spacing: 0) {
                    Text("Удар").font(QFont.text(15, weight: .bold))
                    Text(fight == nil ? "нет цели" : canStrike ? "1,2 с" : session.activeDistance > ExploreRules.activeRange ? "далеко" : "…")
                        .font(QFont.text(11))
                }
                .foregroundStyle(QColor.sheet)
                .frame(width: 88, height: 88)
                .background(QColor.ink, in: Circle())
                .overlay(Circle().trim(from: 0, to: (fight?.strikeCooldown ?? 0) / ExploreRules.activeTurnSeconds)
                    .stroke(Color(hex: 0xE2A04A), lineWidth: 4).rotationEffect(.degrees(-90)))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                .opacity(canStrike ? 1 : 0.6)
            }
            .buttonStyle(.plain)
            .disabled(!canStrike)
            .accessibilityLabel("Удар")
        }
    }

    static func short(_ ability: ExploreAbility) -> String {
        switch ability {
        case .powerStrike: "Мощный"
        case .teamMove: "Командный"
        default: ability.title
        }
    }
}

/// Карточка памятника Epic (15B.2, макет ExploreLife).
struct MonumentCard: View {
    let monument: IslandMonument
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: QSpacing.m) {
                Text("Памятник Epic").font(QFont.text(11, weight: .bold)).textCase(.uppercase).tracking(0.6).foregroundStyle(QColor.amberDeep)
                Text("«\(monument.epic.title)»").font(QFont.title(20)).fixedSize(horizontal: false, vertical: true)
                Text("Начат \(Format.shortDay(monument.epic.started)) · \(monument.epic.steps) шагов · закрыт \(Format.shortDay(monument.epic.closed))")
                    .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                Button("Дальше", action: close).buttonStyle(PrimaryButtonStyle())
            }
            .foregroundStyle(QColor.ink)
            .padding(QSpacing.xl)
            .frame(maxWidth: 420)
            .background(QColor.paper, in: RoundedRectangle(cornerRadius: QRadius.card))
            .padding(QSpacing.xl)
        }
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Атлас (15C.4, макет ExploreAtlas)

/// По каждому острову-месяцу: открыто %, города, сундуки, костры, пещера, площадка, обрывки. Без сравнения с прошлыми прогулками.
struct AtlasView: View {
    let session: ExploreSession
    let close: () -> Void

    private struct Line: Identifiable {
        let id: Int
        let title: String
        let share: Double
        let details: String
    }

    private var lines: [Line] {
        let island = session.island, side = island.side
        return island.regions.map { region in
            var land = 0, open = 0
            for y in region.origin.y..<min(side, region.origin.y + region.side) {
                for x in region.origin.x..<min(side, region.origin.x + region.side) where island.terrain[y * side + x] != .water {
                    land += 1
                    if session.explored[y * side + x] { open += 1 }
                }
            }
            func count<T>(_ items: [T], _ position: (T) -> TilePoint, _ done: (T) -> Bool) -> String {
                let mine = items.filter { region.contains(position($0)) }
                return "\(mine.filter(done).count)/\(mine.count)"
            }
            var parts = ["Города \(count(island.cities, \.center) { session.visitedCities.contains($0.id) })",
                         "Сундуки \(count(island.chests, \.position) { session.openedChests.contains($0.id) })",
                         "Костры \(count(island.campfires, \.position) { session.litCampfires.contains($0.id) })"]
            if let cave = island.caves.first(where: { $0.region == region.id }) { parts.append("Пещера \(session.visitedCaves.contains(cave.id) ? "✓" : "—")") }
            if let lookout = island.lookouts.first(where: { $0.region == region.id }) { parts.append("Площадка \(session.usedLookouts.contains(lookout.id) ? "✓" : "—")") }
            let fragments = island.chests.filter { $0.fragment != nil && region.contains($0.position) }
            if !fragments.isEmpty { parts.append("Обрывки \(fragments.filter { session.fragmentsFound.contains($0.fragment!) }.count)/\(fragments.count)") }
            return Line(id: region.id, title: island.regions.count > 1 ? region.title : "Остров",
                        share: land == 0 ? 0 : Double(open) / Double(land), details: parts.joined(separator: " · "))
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: QSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Атлас").font(QFont.title(20))
                    Spacer()
                    Text("открыто \(Int((session.exploredShare * 100).rounded()))% мира").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(lines) { line in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(line.title).font(QFont.text(14, weight: .bold))
                                    Spacer()
                                    Text("\(Int((line.share * 100).rounded()))%").font(QFont.text(13, weight: .bold)).foregroundStyle(QColor.forest)
                                }
                                ProgressBar(fraction: line.share, color: QColor.forest)
                                Text(line.details).font(QFont.text(11)).foregroundStyle(QColor.inkSecondary)
                            }
                            .padding(.vertical, QSpacing.s)
                            .overlay(alignment: .bottom) { Divider().overlay(QColor.line) }
                        }
                    }
                }
                .frame(maxHeight: 360)
                Button("Закрыть", action: close).buttonStyle(PrimaryButtonStyle())
            }
            .foregroundStyle(QColor.ink)
            .padding(QSpacing.xl)
            .frame(maxWidth: 420)
            .background(QColor.paper, in: RoundedRectangle(cornerRadius: QRadius.card))
            .padding(QSpacing.xl)
        }
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Торговец (15D.2, макет ExploreMerchant)

/// Обмен 2 предметов на 1 и хранилище на прогулку. Игра на паузе, пока окно открыто.
struct MerchantView: View {
    let session: ExploreSession
    let merchant: IslandMerchant
    let close: () -> Void
    @State private var tab = 0
    @State private var give: [ExploreItem] = []
    @State private var get: ExploreItem?

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: QSpacing.m) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(merchant.id < 0 ? "Встречный корабль" : "Торговец").font(QFont.title(20))
                        Text(merchant.id < 0 ? "команда — люди из встреч соседней главы"
                             : "город «\(session.island.cities.first { $0.id == merchant.cityId }?.name ?? "")»").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                    }
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).frame(width: 40, height: 40)
                            .background(QColor.sheet, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Закрыть")
                }
                Picker("Раздел", selection: $tab) {
                    Text("Обмен").tag(0)
                    Text("Хранилище · \(session.storageCount)").tag(1)
                }
                .pickerStyle(.segmented)
                if tab == 0 { trade } else { storage }
            }
            .foregroundStyle(QColor.ink)
            .padding(QSpacing.xl)
            .frame(maxWidth: 420)
            .background(QColor.paper, in: RoundedRectangle(cornerRadius: QRadius.card))
            .padding(QSpacing.xl)
        }
        .accessibilityAddTraits(.isModal)
    }

    private func count(_ item: ExploreItem) -> Int { session.bag[item] ?? 0 }

    @ViewBuilder private var trade: some View {
        Text("ОТДАТЬ 2 ИЗ СУМКИ").font(QFont.text(11, weight: .semibold)).foregroundStyle(QColor.inkSecondary)
        HStack(spacing: QSpacing.s) {
            ForEach(ExploreItem.allCases, id: \.self) { item in
                let chosen = give.filter { $0 == item }.count
                Button {
                    if chosen < count(item) && give.count < ExploreRules.tradeGive { give.append(item) }
                    else if let index = give.firstIndex(of: item) { give.remove(at: index) }
                } label: {
                    tile(item, note: "×\(count(item))", mark: chosen > 0 ? "−\(chosen)" : nil, color: QColor.hp, on: chosen > 0)
                }
                .buttonStyle(.plain)
                .disabled(count(item) == 0)
            }
        }
        Text("ПОЛУЧИТЬ 1").font(QFont.text(11, weight: .semibold)).foregroundStyle(QColor.inkSecondary)
        HStack(spacing: QSpacing.s) {
            ForEach(ExploreItem.allCases, id: \.self) { item in
                Button { get = item } label: { tile(item, note: item.note, mark: get == item ? "+1" : nil, color: QColor.forest, on: get == item) }
                    .buttonStyle(.plain)
            }
        }
        Button {
            if let get, session.trade(give: give, get: get) { give = []; self.get = nil }
        } label: {
            Text(give.count == ExploreRules.tradeGive && get != nil
                 ? "Обменять: \(give.map(\.title).joined(separator: " + ")) → \(get!.title)" : "Выберите 2 предмета и 1 взамен")
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(give.count != ExploreRules.tradeGive || get == nil)
    }

    @ViewBuilder private var storage: some View {
        Text("Положить — освободить сумку; забрать — у любого торговца этой прогулки. Хранилище: \(session.storageCount)/\(ExploreRules.storageCap).")
            .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
        ForEach(ExploreItem.allCases, id: \.self) { item in
            HStack {
                Text(item.title).font(QFont.text(14, weight: .semibold))
                Spacer()
                Text("сумка \(count(item)) · хранилище \(session.storage[item] ?? 0)").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                Button("Положить") { session.deposit(item) }
                    .disabled(count(item) == 0 || session.storageCount >= ExploreRules.storageCap)
                Button("Забрать") { session.withdraw(item) }
                    .disabled((session.storage[item] ?? 0) == 0 || session.bagCount >= session.bagCap)
            }
            .font(QFont.text(12, weight: .semibold))
            .buttonStyle(.bordered)
        }
    }

    private func tile(_ item: ExploreItem, note: String, mark: String?, color: Color, on: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: ExploreGameView.symbol(item)).font(.system(size: 16, weight: .semibold))
            Text(item.title).font(QFont.text(10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(QFont.text(9)).foregroundStyle(QColor.inkSecondary).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.small))
        .overlay(RoundedRectangle(cornerRadius: QRadius.small).strokeBorder(on ? color : QColor.line, lineWidth: on ? 2 : 1))
        .overlay(alignment: .topTrailing) {
            if let mark { Text(mark).font(QFont.text(10, weight: .bold)).foregroundStyle(color).padding(4) }
        }
    }
}


/// Строка, которая переносится, если не помещается по ширине (15H: в портрете счётчики, спутник и баффы
/// больше не выталкивают мини-карту за правый край экрана).
struct WrapRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = Self.size(subviews[index], width: bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    /// Размер элемента: по своему тексту, но не шире строки — длинный текст обрезается многоточием (17.8).
    private static func size(_ subview: LayoutSubview, width: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard width.isFinite, ideal.width > width else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = Self.size(subviews[index], width: width)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}


/// Диалог с мирным NPC (15H, макет ExploreMonsters): реплика про общую встречу и два ответа с шансом.
struct TalkView: View {
    let session: ExploreSession
    let npc: IslandNPC

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { session.talkNPC = nil }
            VStack(alignment: .leading, spacing: QSpacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(npc.title).font(QFont.title(20))
                    Text(subtitle).font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                }
                Text(line)
                    .font(QFont.text(15)).foregroundStyle(QColor.ink)
                    .padding(QSpacing.m).frame(maxWidth: .infinity, alignment: .leading)
                    .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
                answer(npc.meetingTitle.isEmpty ? "Позвать с собой" : "Вспомнить встречу", help: false, filled: true)
                answer("Предложить помощь · −\(Int(npc.talkHelpMP)) MP", help: true, filled: false)
                    .disabled(session.mp < npc.talkHelpMP)
                Button("Уйти") { session.talkNPC = nil }
                    .font(QFont.text(15)).foregroundStyle(QColor.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                Text("Удалось — \(npc.legend == nil ? "идёт" : "легенда идёт") с тобой спутником (\(CompanionSkill.of(npc).summary)). Не удалось — снова можно через минуту.")
                    .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
            .padding(QSpacing.l)
            .frame(maxWidth: 380)
            .background(QColor.paper, in: RoundedRectangle(cornerRadius: QRadius.card))
            .padding(QSpacing.screen)
        }
    }

    private var subtitle: String {
        var parts = [Format.meetings(npc.meetings)]
        if let id = npc.cityId, session.island.cities.indices.contains(id) { parts.append("город «\(session.island.cities[id].name)»") }
        return parts.joined(separator: " · ")
    }

    private var line: String {
        if npc.legend != nil { return "«Слышал о тебе. Докажи, что достоин идти рядом с легендой.»" }
        return npc.meetingTitle.isEmpty ? "«Давно не виделись!»" : "«Помнишь „\(npc.meetingTitle)“? Давно не виделись!»"
    }

    private func answer(_ title: String, help: Bool, filled: Bool) -> some View {
        Button { withAnimation { session.talk(npc, help: help) } } label: {
            HStack {
                Text(title).font(QFont.text(15, weight: .bold))
                Spacer()
                Text("\(Int((session.talkChance(npc, help: help) * 100).rounded()))%").font(QFont.text(14, weight: .semibold)).monospacedDigit()
            }
            .padding(.horizontal, QSpacing.l)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(filled ? QColor.sheet : QColor.ink)
            .background(filled ? QColor.ink : Color.clear, in: RoundedRectangle(cornerRadius: QRadius.control))
            .overlay(RoundedRectangle(cornerRadius: QRadius.control).strokeBorder(QColor.ink, lineWidth: filled ? 0 : 1.5))
        }
        .buttonStyle(.plain)
    }
}


/// Верфь (15E.2, макет ExploreShipyard): улучшения корабля за доски — до конца прогулки.
struct ShipyardView: View {
    let session: ExploreSession

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { session.shipyardOpen = false }
            VStack(alignment: .leading, spacing: QSpacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Верфь").font(QFont.title(20))
                    Spacer()
                    Text("🪵 Доски: \(session.planks)").font(QFont.text(14, weight: .bold))
                }
                Text("Улучшения — до конца прогулки; каждое видно на корабле.").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                ForEach(ShipUpgrade.allCases, id: \.self) { upgrade in
                    HStack(spacing: QSpacing.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(upgrade.title).font(QFont.text(14, weight: .bold))
                            Text(upgrade.summary).font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                        }
                        Spacer()
                        if session.upgrades.contains(upgrade) {
                            Text("установлено").font(QFont.text(12, weight: .bold)).foregroundStyle(QColor.forest)
                        } else {
                            Button("🪵 \(upgrade.planks)") { withAnimation { session.buy(upgrade) } }
                                .font(QFont.text(13, weight: .bold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .foregroundStyle(QColor.sheet)
                                .background(QColor.ink.opacity(session.planks >= upgrade.planks ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 10))
                                .disabled(session.planks < upgrade.planks)
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(QSpacing.m)
                    .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
                }
                Button("Закрыть") { session.shipyardOpen = false }
                    .font(QFont.text(15, weight: .bold)).foregroundStyle(QColor.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(QSpacing.l)
            .frame(maxWidth: 380)
            .background(QColor.paper, in: RoundedRectangle(cornerRadius: QRadius.card))
            .padding(QSpacing.screen)
        }
    }
}

/// Экипаж корабля (15E, макет ExploreShipCrew): до 2 человек; назначить спутника или поменять местами.
struct CrewView: View {
    let session: ExploreSession

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { session.crewOpen = false }
            VStack(alignment: .leading, spacing: QSpacing.s) {
                Text("Экипаж · \(session.crew.count)/\(ExploreRules.crewCap)").font(QFont.title(20))
                ForEach(Array(session.crew.enumerated()), id: \.element.id) { index, member in
                    HStack {
                        person(member)
                        Spacer()
                        if session.companion != nil {
                            Button("Поменять") { withAnimation { session.swapCrew(index) } }
                                .font(QFont.text(13, weight: .bold)).foregroundStyle(QColor.ink)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(QColor.ink, lineWidth: 1.5))
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(QSpacing.m)
                    .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
                }
                if session.crew.count < ExploreRules.crewCap {
                    Text("Свободно мест: \(ExploreRules.crewCap - session.crew.count)").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                }
                Text("СПУТНИК").font(QFont.text(12, weight: .semibold)).foregroundStyle(QColor.inkSecondary)
                if let companion = session.companion {
                    HStack {
                        person(companion)
                        Spacer()
                        if session.crew.count < ExploreRules.crewCap {
                            Button("В экипаж") { withAnimation { session.assignCrew() } }
                                .font(QFont.text(13, weight: .bold)).foregroundStyle(QColor.sheet)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(QColor.ink, in: RoundedRectangle(cornerRadius: 10))
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(QSpacing.m)
                    .background(QColor.track, in: RoundedRectangle(cornerRadius: QRadius.control))
                } else {
                    Text("Спутника нет — уговори человека или легенду в диалоге и приведи к кораблю.")
                        .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                }
                Text("Экипаж на палубе не виден — значки с умениями у корабля; умения экипажа работают, пока ты на корабле. Бьёт в бою только спутник.")
                    .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                Button("Закрыть") { session.crewOpen = false }
                    .font(QFont.text(15, weight: .bold)).foregroundStyle(QColor.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(QSpacing.l)
            .frame(maxWidth: 380)
            .background(QColor.paper, in: RoundedRectangle(cornerRadius: QRadius.card))
            .padding(QSpacing.screen)
        }
    }

    private func person(_ npc: IslandNPC) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(npc.title).font(QFont.text(14, weight: .bold))
            Text(CompanionSkill.of(npc).summary).font(QFont.text(12, weight: .semibold)).foregroundStyle(QColor.forest)
        }
    }
}
