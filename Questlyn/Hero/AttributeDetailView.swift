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

    private var skill: Skill? { model.skills.first { $0.id == skillId } }

    var body: some View {
        NavigationStack {
            Form {
                if let skill {
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
                }
            }
            .paperScreen()
            .navigationTitle(skill?.title ?? "Навык")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .tint(QColor.amber)
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
