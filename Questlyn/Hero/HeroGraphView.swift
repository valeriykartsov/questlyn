import SwiftUI
import Domain
import Application

/// Граф героя (этап 11, вариант А «Созвездие»): Герой → профессии → навыки → привычки; Epic — рядом с навыками своих шагов.
/// Звезда-навык: размер — по XP, яркость — по форме. Запасной вид для VoiceOver — дерево-список (вариант Г).
struct HeroGraphView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var showsList = false
    @State private var selected: Node.ID?
    @State private var zoom: CGFloat = Self.startZoom
    @State private var zoomBase: CGFloat = Self.startZoom
    /// Стартовый масштаб: созвездие целиком помещается над подсказкой.
    static let startZoom: CGFloat = 0.85
    /// Сдвиг поля перетаскиванием (центр поля относительно центра экрана).
    @State private var offset: CGSize = .zero
    @State private var offsetBase: CGSize = .zero
    static let zoomRange: ClosedRange<CGFloat> = 0.4...3
    /// Поле графа больше экрана — вокруг созвездия есть куда перемещаться.
    static let fieldFactor: CGFloat = 2

    struct Node: Identifiable, Hashable {
        enum Kind: Hashable { case hero, profession, skill, habit, epic }
        let id: String
        let kind: Kind
        let title: String
        let subtitle: String
        let detail: [String]
        var point: CGPoint
        var size: CGFloat
        var brightness: Double
        var color: Color
    }

    struct Graph {
        var nodes: [Node] = []
        var lines: [(from: CGPoint, to: CGPoint, color: Color, opacity: Double)] = []
    }

    private static let night = Color(hex: 0x0F1424)
    private static let teal = Color(hex: 0x4FD1C5)
    private static let fire = Color(hex: 0xF2B35B)
    private static let star = Color(hex: 0xE8ECF7)
    private static let muted = Color(hex: 0xAEB8D2)

    var body: some View {
        NavigationStack {
            Group {
                if showsList || voiceOver { list } else { constellation }
            }
            .navigationTitle("Граф героя")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(showsList || voiceOver ? nil : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Готово") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(showsList ? "Созвездие" : "Список") { withAnimation { showsList.toggle() } }
                        .disabled(voiceOver)
                }
            }
        }
    }

    // MARK: Данные

    private struct SkillInfo {
        let skill: Skill
        let xp: Double
        let condition: Int?
        let mastery: Int?
        let habits: [HabitStatus]
        let epics: [EpicStatus]
    }

    private var professions: [(profession: Profession, skills: [SkillInfo], epics: [EpicStatus])] {
        let progress = model.progress
        return model.activeProfessions.sorted { $0.slot < $1.slot }.map { profession in
            let skills = model.skills.filter { $0.professionId == profession.id && $0.isActive && $0.deletedAt == nil }.map { skill in
                SkillInfo(skill: skill, xp: Double((progress.skillXP[skill.id] ?? .zero).value) / 100,
                          condition: progress.skillCondition[skill.id], mastery: model.mastery(skillId: skill.id),
                          habits: model.habits.filter { $0.habit.skillId == skill.id },
                          epics: model.epics.filter { status in !status.epic.isCompleted && status.steps.contains { $0.quest.skillId == skill.id } })
            }
            let skillIds = Set(skills.map(\.skill.id))
            let epics = model.epics.filter { status in
                !status.epic.isCompleted && (status.epic.professionId == profession.id || status.steps.contains { $0.quest.skillId.map(skillIds.contains) ?? false })
            }
            return (profession, skills, epics)
        }
    }

    /// `size` — поле графа, `screen` — видимая область: от неё считается шаг лучей.
    private func graph(in size: CGSize, screen: CGSize) -> Graph {
        var graph = Graph()
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let rank = model.progress.rank
        graph.nodes.append(Node(id: "hero", kind: .hero, title: model.hero?.name ?? "Герой", subtitle: model.hero?.classTitle ?? "",
                                detail: ["Ранг: \(AdventurerRank.title(for: rank))", "Профессий: \(model.activeProfessions.count)"],
                                point: center, size: 46, brightness: 1, color: Self.fire))
        let groups = professions
        let radius = min(screen.width, screen.height) * 0.3
        for (index, group) in groups.enumerated() {
            // Наклон 0,55 рад: при двух профессиях лучи идут по диагонали, а не в одну вертикаль с подписями.
            let angle = -Double.pi / 2 - 0.55 + Double(index) / Double(max(groups.count, 1)) * 2 * .pi
            let color = index % 2 == 0 ? Self.teal : Self.fire
            let p = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            graph.lines.append((center, p, color, 0.8))
            graph.nodes.append(Node(id: "p:\(group.profession.id)", kind: .profession, title: group.profession.title,
                                    subtitle: group.profession.attributes.map(\.code).joined(separator: " · "),
                                    detail: ["Навыков: \(group.skills.count)", "Epic: \(group.epics.count)"],
                                    point: p, size: 22, brightness: 1, color: color))
            let spread = 1.1
            for (k, info) in group.skills.enumerated() {
                let offset = group.skills.count == 1 ? 0.25 : (Double(k) / Double(group.skills.count - 1) - 0.5) * spread
                let a = angle + offset
                let s = CGPoint(x: center.x + cos(a) * radius * 2, y: center.y + sin(a) * radius * 2)
                graph.lines.append((p, s, color, 0.5))
                let starSize = 10 + min(16, info.xp / 40)
                let brightness = 0.45 + 0.55 * Double(info.condition ?? 60) / 100
                var detail = ["XP \(Int(info.xp.rounded()))"]
                if let condition = info.condition { detail.append("форма \(condition)%") }
                if let mastery = info.mastery { detail.append("мастерство \(mastery)/5") }
                graph.nodes.append(Node(id: "s:\(info.skill.id)", kind: .skill, title: info.skill.title, subtitle: group.profession.title,
                                        detail: detail + info.habits.map { "\($0.habit.kind == .weekly ? "Недельный" : "Ежедневный") «\($0.habit.title)»" }
                                            + info.epics.map { "Epic «\($0.epic.title)» · \($0.doneCount) из \($0.steps.count)" },
                                        point: s, size: starSize, brightness: brightness, color: Self.star))
                let satellites = Array(info.habits.prefix(3))
                for (h, habit) in satellites.enumerated() {
                    // Спутники веером наружу от звезды, с шагом, при котором подписи не наползают.
                    let ha = a + (Double(h) - Double(satellites.count - 1) / 2) * 0.95
                    let hp = CGPoint(x: s.x + cos(ha) * 62, y: s.y + sin(ha) * 62)
                    graph.lines.append((s, hp, Self.muted, 0.35))
                    graph.nodes.append(Node(id: "h:\(habit.id)", kind: .habit, title: habit.habit.title,
                                            subtitle: habit.habit.kind == .weekly ? "недельный" : "ежедневный",
                                            detail: ["Эта неделя: \(habit.weekDone) из \(habit.weekPlanned)"], point: hp, size: 6, brightness: 0.8, color: Self.muted))
                }
            }
            // Epic — ромб рядом с навыками своих шагов; без навыков — у профессии.
            for (e, epic) in group.epics.enumerated() {
                let linked = graph.nodes.filter { node in
                    node.kind == .skill && epic.steps.contains { "s:\($0.quest.skillId?.uuidString ?? "")" == node.id }
                }
                let anchor = linked.first?.point ?? p
                // Ромб — дальше от центра, чем его навык, чтобы подписи не наползали.
                let ea = atan2(anchor.y - center.y, anchor.x - center.x) - 0.35 + Double(e) * 0.7
                let ep = CGPoint(x: anchor.x + cos(ea) * 72, y: anchor.y + sin(ea) * 72)
                for node in linked { graph.lines.append((node.point, ep, Self.fire, 0.45)) }
                if linked.isEmpty { graph.lines.append((p, ep, Self.fire, 0.45)) }
                graph.nodes.append(Node(id: "e:\(epic.id)", kind: .epic, title: epic.epic.title, subtitle: "Epic",
                                        detail: ["Шагов: \(epic.doneCount) из \(epic.steps.count)"] + linked.map { "Навык «\($0.title)»" },
                                        point: ep, size: 12, brightness: 1, color: Self.fire))
            }
        }
        return graph
    }

    // MARK: Созвездие

    private var constellation: some View {
        GeometryReader { proxy in
            let screen = proxy.size
            let field = CGSize(width: screen.width * Self.fieldFactor, height: screen.height * Self.fieldFactor)
            let graph = graph(in: field, screen: screen)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    var random = SeededRandom(7)
                    for _ in 0..<220 {
                        let rect = CGRect(x: random.unit() * size.width, y: random.unit() * size.height, width: 2, height: 2)
                        context.fill(Path(rect), with: .color(Color(hex: 0x3A4566)))
                    }
                    for line in graph.lines {
                        var path = Path()
                        path.move(to: line.from)
                        path.addLine(to: line.to)
                        context.stroke(path, with: .color(line.color.opacity(line.opacity)), lineWidth: 1)
                    }
                }
                ForEach(graph.nodes) { node in
                    Button { withAnimation(.snappy) { selected = node.id } } label: { nodeView(node) }
                        .buttonStyle(.plain)
                        .position(node.point)
                        .accessibilityLabel("\(node.title), \(node.subtitle)")
                }
            }
            .frame(width: field.width, height: field.height)
            .scaleEffect(zoom)
            .offset(offset)
            .frame(width: screen.width, height: screen.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        offset = clamped(CGSize(width: offsetBase.width + value.translation.width,
                                                height: offsetBase.height + value.translation.height), field: field, zoom: zoom)
                    }
                    .onEnded { _ in offsetBase = offset }
                    .simultaneously(with: MagnifyGesture()
                        .onChanged { value in
                            zoom = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, zoomBase * value.magnification))
                            offset = clamped(offset, field: field, zoom: zoom)
                        }
                        .onEnded { _ in zoomBase = zoom; offsetBase = offset })
            )
            .overlay(alignment: .topTrailing) { viewControls(field: field).padding(QSpacing.screen) }
            .overlay(alignment: .bottom) {
                if let node = graph.nodes.first(where: { $0.id == selected }) { detailCard(node) }
                else {
                    Text("Звезда — навык: размер по XP, яркость по форме. Ромб — Epic, точки — привычки. Касание — сведения, перетаскивание — обзор, щипок или +/− — масштаб.")
                        .font(QFont.text(12)).foregroundStyle(Self.muted)
                        .padding(QSpacing.m)
                        .background(Self.night.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
                        .padding(QSpacing.screen)
                }
            }
        }
        .background(Self.night.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    /// Сдвиг не уводит край поля дальше середины экрана.
    private func clamped(_ value: CGSize, field: CGSize, zoom: CGFloat) -> CGSize {
        let maxX = field.width * zoom / 2, maxY = field.height * zoom / 2
        return CGSize(width: min(maxX, max(-maxX, value.width)), height: min(maxY, max(-maxY, value.height)))
    }

    private func setZoom(_ value: CGFloat, field: CGSize) {
        withAnimation(.snappy) {
            let next = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, value))
            // Масштаб — вокруг центра экрана: сдвиг меняется пропорционально.
            offset = clamped(CGSize(width: offset.width * next / zoom, height: offset.height * next / zoom), field: field, zoom: next)
            zoom = next
            zoomBase = next
            offsetBase = offset
        }
    }

    private func viewControls(field: CGSize) -> some View {
        VStack(spacing: QSpacing.s) {
            VStack(spacing: 0) {
                Button { setZoom(zoom * 1.25, field: field) } label: { Image(systemName: "plus").frame(width: 40, height: 40) }
                    .accessibilityLabel("Приблизить")
                Divider().frame(width: 22).overlay(Self.muted.opacity(0.4))
                Button { setZoom(zoom / 1.25, field: field) } label: { Image(systemName: "minus").frame(width: 40, height: 40) }
                    .accessibilityLabel("Отдалить")
            }
            .background(Color(hex: 0x182036).opacity(0.94), in: Capsule())
            Button {
                withAnimation(.snappy) { offset = .zero; offsetBase = .zero; zoom = Self.startZoom; zoomBase = Self.startZoom }
            } label: { Image(systemName: "scope").frame(width: 40, height: 40) }
                .background(Color(hex: 0x182036).opacity(0.94), in: Circle())
                .accessibilityLabel("К герою")
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Self.star)
        .buttonStyle(.plain)
    }

    private func nodeView(_ node: Node) -> some View {
        VStack(spacing: 3) {
            Group {
                switch node.kind {
                case .hero:
                    Text(model.progress.rank?.letter ?? "—").font(.system(size: 16, weight: .heavy)).foregroundStyle(Self.night)
                        .frame(width: node.size, height: node.size)
                        .background(node.color, in: Circle())
                case .epic:
                    Rectangle().fill(node.color).frame(width: node.size, height: node.size).rotationEffect(.degrees(45))
                default:
                    Circle().fill(node.color.opacity(node.brightness)).frame(width: node.size, height: node.size)
                }
            }
            .shadow(color: node.color.opacity(0.7 * node.brightness), radius: node.size / 2)
            .overlay {
                if selected == node.id { Circle().strokeBorder(Self.fire, lineWidth: 2).frame(width: node.size + 10, height: node.size + 10) }
            }
            Text(node.title).font(QFont.text(node.kind == .habit ? 10 : 11, weight: .semibold))
                .foregroundStyle(node.kind == .habit ? Self.muted : Self.star).lineLimit(1).fixedSize()
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }

    private func detailCard(_ node: Node) -> some View {
        VStack(alignment: .leading, spacing: QSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(node.title).font(QFont.text(17, weight: .bold))
                Spacer()
                Text(node.subtitle).font(QFont.text(12)).foregroundStyle(Self.muted)
                Button { selected = nil } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }
                    .buttonStyle(.plain).accessibilityLabel("Закрыть")
            }
            ForEach(node.detail, id: \.self) { Text($0).font(QFont.text(13)).foregroundStyle(Color(hex: 0xC9CFE0)) }
        }
        .foregroundStyle(Self.star)
        .padding(QSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x182036), in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
    }

    // MARK: Дерево-список (вариант Г) — для VoiceOver

    private var list: some View {
        List {
            Section {
                LabeledContent(model.hero?.name ?? "Герой", value: AdventurerRank.title(for: model.progress.rank))
            }
            ForEach(professions, id: \.profession.id) { group in
                Section(group.profession.title) {
                    ForEach(group.skills, id: \.skill.id) { info in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.skill.title).font(QFont.text(15, weight: .semibold))
                            Text(["XP \(Int(info.xp.rounded()))", info.condition.map { "форма \($0)%" }, info.mastery.map { "мастерство \($0)/5" }]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                        }
                        ForEach(info.habits) { habit in
                            Label(habit.habit.title, systemImage: habit.habit.kind == .weekly ? "calendar" : "repeat")
                                .font(QFont.text(14)).padding(.leading, QSpacing.xl)
                        }
                    }
                    ForEach(group.epics) { epic in
                        Label("\(epic.epic.title) · \(epic.doneCount) из \(epic.steps.count)", systemImage: "flag")
                            .font(QFont.text(14))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .paperScreen()
    }
}
