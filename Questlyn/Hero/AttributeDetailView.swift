import SwiftUI
import Domain
import Application

/// «Подробнее» по атрибуту (07, раздел 9): каждое начисление и спад — с причиной.
struct AttributeDetailView: View {
    let model: AppModel
    let attribute: Attribute
    @Environment(\.dismiss) private var dismiss

    private var progress: HeroProgress { model.progress }
    private var state: ProgressTimeline.AttributeState? { progress.attributeStates[attribute] }

    private enum Entry: Identifiable {
        case grant(ProgressGrant)
        case decay(from: LocalDate, to: LocalDate, amount: CentiXP, days: Int, floor: Bool)

        var id: String {
            switch self {
            case .grant(let g): g.id.uuidString
            case .decay(let from, _, _, _, _): "decay-\(from)"
            }
        }

        var date: LocalDate {
            switch self {
            case .grant(let g): g.effectiveDate
            case .decay(_, let to, _, _, _): to
            }
        }
    }

    /// Начисления и периоды спада, новые сверху. Дни спада подряд собираются в один период.
    private var entries: [Entry] {
        var runs: [Entry] = []
        var current: (from: LocalDate, to: LocalDate, amount: CentiXP, days: Int, floor: Bool)?
        for event in progress.decayEvents(attribute) {
            if let c = current, c.to.adding(days: 1) == event.date {
                current = (c.from, event.date, c.amount + event.amount, event.daysWithoutXP, event.reachedFloor)
            } else {
                if let c = current { runs.append(.decay(from: c.from, to: c.to, amount: c.amount, days: c.days, floor: c.floor)) }
                current = (event.date, event.date, event.amount, event.daysWithoutXP, event.reachedFloor)
            }
        }
        if let c = current { runs.append(.decay(from: c.from, to: c.to, amount: c.amount, days: c.days, floor: c.floor)) }
        let grants = progress.grants(for: attribute).map(Entry.grant)
        return (grants + runs).sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: QSpacing.l) {
                    summary
                    CapsHeader(title: "История", trailing: "новые сверху")
                    if entries.isEmpty {
                        Text("Начислений пока нет. \(hint)")
                            .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { Divider().overlay(QColor.line) }
                                row(entry)
                            }
                        }
                        .padding(.horizontal, QSpacing.xl)
                        .sheetCard()
                    }
                }
                .padding(QSpacing.screen)
            }
            .paperScreen()
            .navigationTitle("\(attribute.code) · \(attribute.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }

    private var hint: String {
        switch attribute {
        case .focus: "FOC растёт от выполненных квестов."
        case .discipline: "DIS пересчитывается по понедельникам по доле выполненных привычек."
        default: "Атрибут растёт от квестов, привычек и Activity профессий, где он есть."
        }
    }

    private var summary: some View {
        let level = progress.level(attribute)
        let step = progress.levelProgress(attribute)
        return VStack(alignment: .leading, spacing: QSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Уровень \(level)").font(QFont.title(24))
                Spacer()
                Text("\(Format.xp(progress.xp(attribute))) XP").font(QFont.text(15, weight: .semibold)).monospacedDigit()
            }
            ProgressBar(fraction: step.current / Double(step.needed))
            Text("До уровня \(level + 1): \(Format.xp(CentiXP(Int(((Double(step.needed) - step.current) * 100).rounded())))) XP")
                .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            Divider().overlay(QColor.line)
            Text(decayStatus).font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
            if attribute != .discipline, let state, state.peak.value > 0 {
                Text("Пик \(Format.xp(state.peak)) XP · граница спада \(Format.xp(state.floor)) XP (70% пика или стартовый бонус)")
                    .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
        }
        .padding(QSpacing.xl)
        .sheetCard()
    }

    private var decayStatus: String {
        if attribute == .discipline { return "У DIS свой недельный механизм — общий спад к нему не применяется." }
        guard let state, let last = state.lastGainDate else { return "Спад начнётся через 7 дней после первого XP." }
        let days = last.days(until: model.today)
        if days <= ProgressTimeline.graceDays {
            let left = ProgressTimeline.graceDays - days + 1
            return days == 0 ? "XP получен сегодня. Спад начнётся после 7 дней без XP."
                             : "Последний XP — \(days) дн. назад. Спад начнётся через \(left) дн. без XP."
        }
        if state.xp <= state.floor { return "\(days) дн. без XP · достигнута граница спада, ниже не опустится." }
        return "Спад −2% в день · \(days) дн. без XP. Любое начисление остановит спад."
    }

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        switch entry {
        case .grant(let grant):
            line(title: title(for: grant), reason: grant.reason, date: Format.shortDay(grant.effectiveDate),
                 delta: Format.signedXP(grant.amount), color: grant.amount.value >= 0 ? QColor.forest : QColor.hp)
        case let .decay(from, to, amount, days, floor):
            let period = from == to ? Format.shortDay(from) : "\(Format.shortDay(from)) – \(Format.shortDay(to))"
            line(title: "Спад −2% в день",
                 reason: "\(days) дн. без практики" + (floor ? " · граница 70% от пика" : ""),
                 date: period, delta: Format.signedXP(amount), color: QColor.hp)
        }
    }

    private func title(for grant: ProgressGrant) -> String {
        switch grant.sourceType {
        case .questCompletion: "Квест"
        case .habitOccurrence: "Привычка"
        case .weeklyDiscipline: "Недельная дисциплина"
        case .onboardingBonus: "Стартовый бонус"
        case .activity: "Активность"
        }
    }

    private func line(title: String, reason: String, date: String, delta: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: QSpacing.l) {
            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                Text(title).font(QFont.text(15, weight: .semibold))
                Text(reason).font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                Text(date).font(QFont.text(11)).foregroundStyle(QColor.inkSecondary)
            }
            Spacer(minLength: QSpacing.m)
            Text(delta).font(QFont.text(15, weight: .bold)).foregroundStyle(color).monospacedDigit()
        }
        .padding(.vertical, QSpacing.l)
        .accessibilityElement(children: .combine)
    }
}

/// Навык: XP, форма, мастерство (07, раздел 6; макет SkillNew).
struct SkillDetailView: View {
    let model: AppModel
    let skillId: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var pendingTemplate: ActivityTemplate?
    @State private var title = ""
    @State private var isConfirmingDelete = false

    private var skill: Skill? { model.skills.first { $0.id == skillId } }

    var body: some View {
        NavigationStack {
            Form {
                if let skill {
                    Section {
                        TextField("Название", text: $title, prompt: Text("Название навыка").foregroundStyle(QColor.placeholder))
                            .font(QFont.text(17, weight: .semibold))
                            .submitLabel(.done)
                            .onSubmit { rename(skill) }
                    } header: {
                        Text("Навык")
                    }
                    .listRowBackground(QColor.sheet)
                    activitySection(skill)
                    Section {
                        LabeledContent("Профессия", value: model.profession(id: skill.professionId)?.title ?? "—")
                        LabeledContent("XP практики", value: Format.xp(model.progress.skillXP[skill.id] ?? .zero))
                        LabeledContent("Форма", value: model.progress.skillCondition[skill.id].map { "\($0)%" } ?? "после первой практики")
                    } footer: {
                        Text("XP показывает объём практики, а не уровень. Форма: +20 за практику, после 7 дней без практики −3 в день, не ниже 40%. На XP не влияет.")
                    }
                    .listRowBackground(QColor.sheet)
                    Section {
                        MasteryPicker(value: Binding(
                            get: { model.mastery(skillId: skill.id) ?? 0 },
                            set: { value in Task { await model.assessMastery(skillId: skill.id, value: value) } }
                        ))
                    } header: {
                        Text("Мастерство — ваша оценка")
                    } footer: {
                        Text("Мастерство меняете только вы.")
                    }
                    .listRowBackground(QColor.sheet)
                    Section {
                        Button("Удалить навык", role: .destructive) { isConfirmingDelete = true }
                    } footer: {
                        Text("Профессию навыка не меняем — от неё зависят начисления. Удалённый навык пропадёт из выбора, история останется.")
                    }
                    .listRowBackground(QColor.sheet)
                }
            }
            .paperScreen()
            .onAppear { title = skill?.title ?? "" }
            .confirmationDialog("Удалить навык «\(skill?.title ?? "")»?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Удалить навык", role: .destructive) {
                    Task { if await model.deleteSkill(skillId) { dismiss() } }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("XP и записи в Летописи останутся. У открытых квестов и привычек навык снимется; выполненные квесты не меняются.")
            }
            .confirmationDialog(pendingTitle, isPresented: Binding(get: { pendingTemplate != nil }, set: { if !$0 { pendingTemplate = nil } }),
                                titleVisibility: .visible) {
                Button("Перенести") {
                    guard let template = pendingTemplate else { return }
                    Task { await model.linkActivity(templateId: template.id, skillId: skillId) }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("У вида активности может быть только один навык.")
            }
            .navigationTitle(skill?.title ?? "Навык")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { if let skill { rename(skill) }; dismiss() } } }
        }
        .tint(QColor.amber)
    }
}

extension SkillDetailView {
    /// Переименование (8C.6): пустое название не сохраняется.
    private func rename(_ skill: Skill) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != skill.title else { return }
        Task { _ = await model.renameSkill(skill.id, title: name) }
    }

    private var pendingTitle: String {
        guard let template = pendingTemplate, let owner = model.linkedSkill(templateId: template.id) else { return "" }
        return "Перенести «\(template.title)» с навыка «\(owner.title)»?"
    }

    /// Вид активности навыка, один к одному (8.6, макет 8.23).
    @ViewBuilder
    func activitySection(_ skill: Skill) -> some View {
        Section {
            Picker("Вид активности", selection: Binding(
                get: { skill.activityTemplateId },
                set: { id in
                    guard let id else { Task { await model.linkActivity(templateId: nil, skillId: skill.id) }; return }
                    if let owner = model.linkedSkill(templateId: id), owner.id != skill.id {
                        pendingTemplate = ActivityTemplate.template(id: id)
                    } else {
                        Task { await model.linkActivity(templateId: id, skillId: skill.id) }
                    }
                }
            )) {
                Text("Без вида").tag(String?.none)
                ForEach(ActivityTemplate.all) { template in
                    let owner = model.linkedSkill(templateId: template.id)
                    VStack(alignment: .leading, spacing: QSpacing.xxs) {
                        Text(template.title).font(QFont.text(16)).foregroundStyle(QColor.ink)
                        Text(owner.map { $0.id == skill.id ? template.attributes.map(\.code).joined(separator: " · ") : "занят навыком «\($0.title)»" }
                             ?? template.attributes.map(\.code).joined(separator: " · "))
                            .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                    }
                    .tag(String?.some(template.id))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Вид активности · один")
        } footer: {
            Text("В «Новой активности» этот навык подставится сам. У вида — не больше одного навыка. На награды привязка не влияет.")
        }
        .listRowBackground(QColor.sheet)
    }
}

/// Мастерство 1–5 кнопками (макет SkillNew).
struct MasteryPicker: View {
    @Binding var value: Int
    private let labels = ["Новичок", "Базовый", "Уверенный", "Продвинутый", "Эксперт"]

    var body: some View {
        VStack(alignment: .leading, spacing: QSpacing.s) {
            HStack(spacing: QSpacing.s) {
                ForEach(1...5, id: \.self) { n in
                    Button("\(n)") { value = n }
                        .font(QFont.text(15, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(n <= value ? QColor.sheet : QColor.ink)
                        .background(n <= value ? QColor.amber : QColor.paper, in: RoundedRectangle(cornerRadius: QRadius.small))
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(n == value ? .isSelected : [])
                }
            }
            Text(value == 0 ? "Не оценено" : "\(value) из 5 · \(labels[value - 1])")
                .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
        }
    }
}
