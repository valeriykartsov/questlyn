import SwiftUI
import Domain
import Application

/// «Квест выполнен»: что изменилось и почему (макет RewardV2, 07 раздел 9). Мана и Epic — этапы 4 и 2.
struct RewardView: View {
    let model: AppModel
    let report: CompletionReport
    @Environment(\.dismiss) private var dismiss
    @State private var isUndoing = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: QSpacing.l) {
                    VStack(alignment: .leading, spacing: QSpacing.s) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(QColor.forest)
                        Text("Квест выполнен").font(QFont.title(28))
                        Text(report.quest.title)
                            .font(QFont.text(16, weight: .semibold))
                            .foregroundStyle(QColor.inkSecondary)
                    }
                    .padding(.top, QSpacing.screen)

                    Text("Что изменилось").font(QFont.title(18))

                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            if index > 0 { Divider().overlay(QColor.line) }
                            changeRow(row)
                        }
                    }
                    .padding(.horizontal, QSpacing.xl)
                    .sheetCard()
                }
                .padding(.horizontal, QSpacing.screen)
            }

            VStack(spacing: QSpacing.m) {
                Button("Продолжить") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Отменить выполнение") {
                    isUndoing = true
                    Task {
                        await model.undo(questId: report.quest.id)
                        dismiss()
                    }
                }
                .font(QFont.text(15, weight: .semibold))
                .foregroundStyle(QColor.amberDeep)
                .frame(minHeight: 44)
                .disabled(isUndoing)
            }
            .padding(QSpacing.screen)
        }
        .paperScreen()
    }

    private struct Row {
        var tag: String
        var title: String
        var why: String
        var delta: String
        var color: Color
    }

    private var rows: [Row] {
        var rows: [Row] = report.grants.map { grant in
            switch grant.target {
            case .attribute(let a):
                Row(tag: a.code, title: a.title, why: grant.reason, delta: Format.signedXP(grant.amount),
                    color: a == .focus ? QColor.amberDeep : QColor.forest)
            case .skill(let id):
                Row(tag: "XP", title: model.skill(id: id)?.title ?? "Навык", why: grant.reason,
                    delta: Format.signedXP(grant.amount), color: QColor.amberDeep)
            }
        }
        for (attribute, level) in report.levelUps {
            rows.append(Row(tag: attribute.code, title: "Новый уровень", why: attribute.title, delta: "ур. \(level)", color: QColor.ink))
        }
        if report.rankChanged {
            rows.append(Row(tag: "Ранг", title: AdventurerRank.title(for: report.after.rank),
                            why: "Очки ранга: \(Format.number(report.after.rankPoints))", delta: report.after.rank?.letter ?? "—", color: QColor.ink))
        }
        return rows
    }

    private func changeRow(_ row: Row) -> some View {
        HStack(spacing: QSpacing.l) {
            Text(row.tag)
                .font(QFont.text(11, weight: .bold))
                .foregroundStyle(row.color)
                .frame(width: 44, height: 28)
                .background(row.color.opacity(0.1), in: RoundedRectangle(cornerRadius: QRadius.chip))
            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                Text(row.title).font(QFont.text(15, weight: .semibold))
                Text(row.why).font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
            Spacer(minLength: QSpacing.m)
            Text(row.delta)
                .font(QFont.text(16, weight: .bold))
                .foregroundStyle(row.color)
                .monospacedDigit()
        }
        .padding(.vertical, QSpacing.l)
        .accessibilityElement(children: .combine)
    }
}
