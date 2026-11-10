import SwiftUI
import Domain
import Application

/// «Герой» (макет HeroV2 без HP/MP): пиксельный герой, ранг, атрибуты, профессии.
struct HeroView: View {
    let model: AppModel
    @State private var isCreatingSkill = false
    @State private var isShowingSettings = false
    @State private var isEditingProfessions = false
    @State private var openedAttribute: Attribute?
    @State private var openedSkill: UUID?

    private var progress: HeroProgress { model.progress }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.l) {
                header
                rank
                attributes
                professions
            }
            .padding(.horizontal, QSpacing.screen)
            .padding(.top, QSpacing.l)
            .padding(.bottom, QSpacing.screen)
        }
        .paperScreen()
        .sheet(isPresented: $isCreatingSkill) { SkillFormView(model: model) }
        .sheet(isPresented: $isShowingSettings) { SettingsView(model: model) }
        .sheet(isPresented: $isEditingProfessions) { ProfessionEditorView(model: model) }
        .sheet(item: $openedAttribute) { AttributeDetailView(model: model, attribute: $0) }
        .sheet(item: Binding(get: { openedSkill.map(IdentifiedID.init) }, set: { openedSkill = $0?.id })) {
            SkillDetailView(model: model, skillId: $0.id)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: QSpacing.xxs) {
            HStack {
                Text(model.hero?.name ?? "")
                    .font(QFont.text(13))
                    .foregroundStyle(QColor.inkSecondary)
                Spacer()
                Button { isShowingSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20))
                        .foregroundStyle(QColor.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Настройки")
            }
            HStack(alignment: .bottom, spacing: QSpacing.l) {
                if let hero = model.hero {
                    HeroStage(appearance: hero.appearance, accent: model.heroAccent, scale: 2, height: 136)
                        .frame(width: 96)
                }
                VStack(alignment: .leading, spacing: QSpacing.xxs) {
                    Text(model.hero?.classTitle ?? "Герой")
                        .font(QFont.title(30))
                    Text(classNote)
                        .font(QFont.text(13))
                        .foregroundStyle(QColor.inkSecondary)
                    if let outfit = model.hero?.appearance.outfit {
                        Text("Образ: \(outfit.title)")
                            .font(QFont.text(13))
                            .foregroundStyle(QColor.inkSecondary)
                    }
                }
                .padding(.bottom, QSpacing.xs)
            }
        }
    }

    private var classNote: String {
        let n = model.activeProfessions.count
        let word = n == 1 ? "профессии" : "профессий"
        return "Класс из \(n) \(word)"
    }

    private var rank: some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            Text(AdventurerRank.title(for: progress.rank))
                .font(QFont.title(20))
            if let next = progress.nextRank {
                ProgressBar(fraction: progress.rankPoints / Double(next.threshold), color: QColor.amber)
                Text("\(Format.number(progress.rankPoints)) / \(next.threshold) очков до \(next.letter) · \(next.title)")
                    .font(QFont.text(12))
                    .foregroundStyle(QColor.inkSecondary)
                    .monospacedDigit()
                if next.number >= 6 {
                    Text("Для ранга \(next.letter) каждый атрибут класса должен быть не ниже уровня \(2 * next.number).")
                        .font(QFont.text(12))
                        .foregroundStyle(QColor.inkSecondary)
                }
            } else {
                Text("Высший ранг достигнут.").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
        }
        .padding(QSpacing.xl)
        .sheetCard()
    }

    private var attributes: some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            Text("Атрибуты").font(QFont.title(18))
            VStack(spacing: QSpacing.l) {
                ForEach(Attribute.allCases, id: \.self) { attribute in
                    Button { openedAttribute = attribute } label: { attributeRow(attribute) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Подробнее: начисления и спад")
                }
            }
            .padding(QSpacing.xl)
            .sheetCard()
            if let dis = model.overview?.lastDiscipline {
                Text("Дисциплина за прошлую неделю: \(Format.signedXP(dis.amount)) XP · \(dis.reason)")
                    .font(QFont.text(12))
                    .foregroundStyle(QColor.inkSecondary)
            }
            Text("Тёмные полосы — атрибуты класса, они сильнее влияют на ранг. DIS пересчитывается по понедельникам.")
                .font(QFont.text(12))
                .foregroundStyle(QColor.inkSecondary)
        }
    }

    private func attributeRow(_ attribute: Attribute) -> some View {
        let level = progress.level(attribute)
        let step = progress.levelProgress(attribute)
        let inClass = progress.classAttributes.contains(attribute) || attribute == .focus || attribute == .discipline
        return VStack(spacing: QSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(attribute.code).font(QFont.text(13, weight: .bold)).frame(width: 40, alignment: .leading)
                Text(attribute.title).font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                Spacer()
                if progress.decayEvents(attribute).last?.date == model.today {
                    Image(systemName: "arrow.down.right").font(.system(size: 11, weight: .bold)).foregroundStyle(QColor.hp)
                        .accessibilityLabel("Спад")
                }
                Text("ур. \(level)").font(QFont.text(15, weight: .bold)).monospacedDigit()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(QColor.inkSecondary)
            }
            ProgressBar(fraction: step.current / Double(step.needed), color: inClass ? QColor.ink : Color(hex: 0xB3A890))
            HStack {
                Spacer()
                Text("\(Format.xp(CentiXP(Int((step.current * 100).rounded())))) / \(step.needed) XP до ур. \(level + 1)")
                    .font(QFont.text(11))
                    .foregroundStyle(QColor.inkSecondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func skillRow(_ skill: Skill) -> some View {
        let condition = progress.skillCondition[skill.id]
        let mastery = model.mastery(skillId: skill.id) ?? 0
        return VStack(alignment: .leading, spacing: QSpacing.xs) {
            HStack {
                Text(skill.title).font(QFont.text(15))
                Spacer()
                Text("\(Format.xp(progress.skillXP[skill.id] ?? .zero)) XP")
                    .font(QFont.text(13, weight: .semibold)).foregroundStyle(QColor.inkSecondary).monospacedDigit()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(QColor.inkSecondary)
            }
            HStack(spacing: QSpacing.m) {
                Text(condition.map(conditionText) ?? "Форма: после первой практики")
                    .font(QFont.text(12))
                    .foregroundStyle(condition.map { $0 >= 80 ? QColor.forest : ($0 >= 60 ? QColor.amberDeep : QColor.hp) } ?? QColor.inkSecondary)
                Spacer()
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { n in
                        Circle().fill(n <= mastery ? QColor.amber : QColor.line).frame(width: 6, height: 6)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(mastery == 0 ? "Мастерство не оценено" : "Мастерство \(mastery) из 5")
            }
        }
        .contentShape(Rectangle())
    }

    private func conditionText(_ value: Int) -> String {
        let word = value >= 80 ? "хорошая" : (value >= 60 ? "снижается" : "слабая")
        return "Форма: \(word) · \(value)%"
    }

    private var professions: some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            VStack(alignment: .leading, spacing: QSpacing.xs) {
                Text("Профессии и навыки").font(QFont.title(18))
                HStack(spacing: QSpacing.xl) {
                    Button("+ Навык") { isCreatingSkill = true }
                    Button("Изменить профессии") { isEditingProfessions = true }
                }
                .font(QFont.text(14, weight: .semibold))
                .foregroundStyle(QColor.amberDeep)
                .frame(minHeight: 32)
            }
            ForEach(model.activeProfessions) { profession in
                VStack(alignment: .leading, spacing: QSpacing.m) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(profession.title).font(QFont.text(16, weight: .semibold))
                        if profession.slot == 1 {
                            Text("основная").font(QFont.text(12, weight: .semibold)).foregroundStyle(QColor.amberDeep)
                        }
                        Spacer()
                        Text(profession.attributes.map(\.code).joined(separator: " · "))
                            .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                    }
                    let skills = model.skills.filter { $0.professionId == profession.id && $0.isActive }
                    if skills.isEmpty {
                        Text("Навыков пока нет").font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                    } else {
                        ForEach(skills) { skill in
                            Button { openedSkill = skill.id } label: { skillRow(skill) }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(QSpacing.xl)
                .sheetCard()
            }
        }
    }
}
