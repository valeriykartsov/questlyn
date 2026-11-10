import SwiftUI
import Domain

/// «Герой» этапа 1 (макет HeroV2 без HP/MP, внешности и формы навыка).
struct HeroView: View {
    let model: AppModel
    @State private var isCreatingSkill = false

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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: QSpacing.xxs) {
            Text(model.hero?.name ?? "")
                .font(QFont.text(13))
                .foregroundStyle(QColor.inkSecondary)
            Text(model.hero?.classTitle ?? "Герой")
                .font(QFont.title(30))
            Text(classNote)
                .font(QFont.text(13))
                .foregroundStyle(QColor.inkSecondary)
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
                    attributeRow(attribute)
                }
            }
            .padding(QSpacing.xl)
            .sheetCard()
            Text("Тёмные полосы — атрибуты класса, они сильнее влияют на ранг.")
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
                Text("ур. \(level)").font(QFont.text(15, weight: .bold)).monospacedDigit()
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

    private var professions: some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            HStack {
                Text("Профессии и навыки").font(QFont.title(18))
                Spacer()
                Button("+ Навык") { isCreatingSkill = true }
                    .font(QFont.text(14, weight: .semibold))
                    .foregroundStyle(QColor.amberDeep)
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
                            HStack {
                                Text(skill.title).font(QFont.text(15))
                                Spacer()
                                Text("\(Format.xp(progress.skillXP[skill.id] ?? .zero)) XP")
                                    .font(QFont.text(13, weight: .semibold))
                                    .foregroundStyle(QColor.inkSecondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .padding(QSpacing.xl)
                .sheetCard()
            }
        }
    }
}
