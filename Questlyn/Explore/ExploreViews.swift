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
    @State private var first: Date
    @State private var last: Date
    @State private var chosen: [UUID] = []
    @State private var attempt = 0
    @State private var session: ExploreSession?
    @State private var season: Season = Season.of(LocalDate(.now, timeZone: .current))
    @State private var precipitation = false

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
                    ExploreSetupView(model: model, first: $first, last: $last, chosen: $chosen, season: $season,
                                     precipitation: $precipitation, start: start)
                }
            case .game:
                if let session { ExploreGameView(session: session) { phase = .summary } }
            case .summary:
                if let session {
                    ExploreSummaryView(session: session) {
                        attempt += 1
                        start()
                    } close: { dismiss() }
                }
            }
        }
        .onAppear(perform: autoStartIfNeeded)
    }

    private var range: (LocalDate, LocalDate) { (LocalDate(first, timeZone: .current), LocalDate(last, timeZone: .current)) }

    private func start() {
        let (a, b) = range
        let skills = model.exploreSkills.filter { chosen.contains($0.id) }
        session = ExploreSession(input: model.exploreInput(first: a, last: b), hero: model.exploreHero(skills: skills),
                                 attempt: attempt, appearance: model.hero?.appearance, accent: model.heroAccent,
                                 season: season, precipitation: precipitation)
        phase = .game
    }

    private func autoStartIfNeeded() {
        #if DEBUG
        // `-QuestlynExploreAuto YES` — сразу на остров (проверка в симуляторе без нажатий).
        guard UserDefaults.standard.bool(forKey: "QuestlynExploreAuto"), phase == .setup else { return }
        first = Calendar.current.date(byAdding: .day, value: -60, to: last) ?? first
        if let value = UserDefaults.standard.string(forKey: "QuestlynExploreSeason"), let chosenSeason = Season(rawValue: value) { season = chosenSeason }
        precipitation = UserDefaults.standard.bool(forKey: "QuestlynExplorePrecipitation")
        chosen = Array(model.exploreSkills.prefix(2).map(\.id))
        start()
        if UserDefaults.standard.bool(forKey: "QuestlynExploreEncounter"), let session, let npc = session.island.npcs.last {
            session.startEncounter(npc: npc)
            session.encounter?.perform(.fight)
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
    @Binding var season: Season
    @Binding var precipitation: Bool
    let start: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var preview: Island?

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
                    preset("2 недели", days: 14)
                    preset("Месяц", days: 30)
                    preset("3 месяца", days: ExploreRules.maxDays)
                }
                summary
                CapsHeader(title: "Время года и погода")
                VStack(spacing: QSpacing.m) {
                    Picker("Время года", selection: $season) {
                        Text("Осень").tag(Season.autumn)
                        Text("Зима").tag(Season.winter)
                        Text("Весна").tag(Season.spring)
                        Text("Лето").tag(Season.summer)
                    }
                    .pickerStyle(.segmented)
                    Picker("Погода", selection: $precipitation) {
                        Text("Ясно").tag(false)
                        Text(season == .winter ? "Снег" : "Дождь").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
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

    /// Самое раннее начало: 92 дня до конца диапазона.
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
                Text(preview?.size.title ?? "Остров").font(QFont.text(15, weight: .bold))
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
                    count(island.weatherBands.count, "недель погоды")
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

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if let scene {
                    SpriteView(scene: scene, preferredFramesPerSecond: 60)
                        .ignoresSafeArea()
                        .accessibilityLabel("Остров: касание — идти туда")
                } else {
                    Color(hex: 0x3F6E9C).ignoresSafeArea()
                }
                VStack(spacing: QSpacing.s) {
                    topBar
                    HStack(alignment: .top) {
                        goals
                        Spacer()
                        minimap
                    }
                    if let toast = session.toast {
                        Text(toast).font(QFont.text(13, weight: .semibold)).foregroundStyle(QColor.ink)
                            .padding(.horizontal, QSpacing.l).padding(.vertical, QSpacing.s)
                            .background(QColor.sheet.opacity(0.95), in: Capsule())
                            .transition(.opacity)
                    }
                    Spacer()
                    abilityBar
                }
                .padding(.horizontal, QSpacing.l)
                if session.encounter != nil {
                    EncounterView(session: session) { outcome, npc in scene?.resolveEncounter(outcome, npcId: npc) }
                        .transition(.opacity)
                }
            }
            .onAppear {
                if scene == nil { scene = ExploreScene(session: session, size: proxy.size) }
            }
        }
        .task(id: session.toast) {
            guard session.toast != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            withAnimation { session.toast = nil }
        }
    }

    private var topBar: some View {
        HStack(spacing: QSpacing.s) {
            Button("Выйти", action: exit)
                .font(QFont.text(14, weight: .semibold)).foregroundStyle(QColor.ink)
                .padding(.horizontal, QSpacing.xl).frame(height: 40)
                .background(QColor.sheet.opacity(0.94), in: Capsule())
            VStack(spacing: 5) {
                bar("HP", value: session.hp, max: session.hero.maxHP, color: QColor.hp)
                bar("MP", value: session.mp, max: session.hero.maxMP, color: QColor.mp)
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

    private var goals: some View {
        HStack(spacing: QSpacing.l) {
            if !session.island.cities.isEmpty { Text("Города \(session.visitedCities.count)/\(session.island.cities.count)") }
            if !session.island.chests.isEmpty { Text("Сундуки \(session.openedChests.count)/\(session.island.chests.count)") }
        }
        .font(QFont.text(12, weight: .semibold)).foregroundStyle(QColor.ink)
        .padding(.horizontal, QSpacing.l).padding(.vertical, QSpacing.s)
        .background(QColor.sheet.opacity(0.94), in: RoundedRectangle(cornerRadius: QRadius.control))
    }

    private var minimap: some View {
        let side = CGFloat(session.island.side)
        return ZStack(alignment: .topLeading) {
            if let image = ExploreRenderer.minimap(session.island, opened: session.openedChests, lit: session.litCampfires) {
                Image(decorative: image, scale: 1).resizable().interpolation(.none)
            }
            Rectangle().fill(Color(hex: 0xE2A04A))
                .frame(width: 6, height: 6)
                .offset(x: CGFloat(session.heroTile.x) / side * 80 - 3, y: CGFloat(session.heroTile.y) / side * 80 - 3)
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(QColor.sheet, lineWidth: 2))
        .accessibilityLabel("Мини-карта")
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
                            Text(onMap ? "\(skill.title) · −\(Int((skill.ability.mpShare * session.hero.maxMP).rounded())) MP" : "только во встрече")
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
    let resolved: (EncounterOutcome?, Int?) -> Void
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
                        Text("встречались в событиях: \(npcMeetings)").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                    }
                    Text(title(encounter)).font(QFont.title(18, weight: .bold))
                    HStack(spacing: QSpacing.l) {
                        meter("Вы", value: encounter.heroHP, max: session.hero.maxHP, color: QColor.hp)
                        meter(encounter.tier.title, value: encounter.npcHP, max: encounter.npcMaxHP, color: QColor.hp)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(encounter.log.suffix(3).enumerated()), id: \.offset) { _, line in
                            Text(line).font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                        }
                    }
                    if encounter.outcome == nil { actions(encounter) } else {
                        Button("Продолжить") {
                            let npc = session.encounterNPC
                            let outcome = session.finishEncounter()
                            resolved(outcome, npc)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    Text("Поражение — герой приходит в себя в последнем городе, ничего не теряется.")
                        .font(QFont.text(11)).foregroundStyle(QColor.inkSecondary)
                }
                .foregroundStyle(QColor.ink)
                .padding(QSpacing.xl)
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
        case nil: "\(encounter.tier.title) преградил путь"
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
            actionButton("Навык", note: "\(session.hero.skills.filter { encounter.isReady($0) }.count) готовы", filled: false, accent: true) {
                showsSkills.toggle()
            }
            .disabled(session.hero.skills.isEmpty)
            actionButton("Бежать", note: "шанс \(Int((encounter.escapeChance * 100).rounded()))%", filled: false) {
                session.encounter?.perform(.flee)
            }
        }
        if showsSkills, !session.hero.skills.isEmpty {
            VStack(spacing: 0) {
                ForEach(session.hero.skills) { skill in
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
                    Text("Остров \(Format.shortDay(session.input.first)) — \(Format.shortDay(session.input.last))").font(QFont.title(26))
                    Text("\(Format.dayCount(session.input.days)) · \(session.island.size.title.lowercased()) · \(minutes) мин в пути")
                        .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                }
                HStack(spacing: QSpacing.s) {
                    goal("Городов посещено", session.visitedCities.count, session.island.cities.count)
                    goal("Сундуков найдено", session.openedChests.count, session.island.chests.count)
                }
                VStack(spacing: 0) {
                    row("Побед", session.wins)
                    row("Уговорено", session.persuaded)
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
