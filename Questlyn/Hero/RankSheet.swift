import SwiftUI
import Domain

/// Окно рангов (макет 14.1): текущий ранг, путь до следующего, все 10 рангов с порогами, аурой и требованиями.
struct RankSheet: View {
    let progress: HeroProgress
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: QSpacing.l) {
                    current
                    Text("Очки ранга — сумма уровней атрибутов: атрибуты класса, FOC и DIS считаются полностью, остальные — наполовину. С ранга B каждый атрибут профессий класса должен быть не ниже 2 × номер ранга. При спаде уровней ранг может снизиться.")
                        .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                    VStack(spacing: 0) {
                        ForEach(AdventurerRank.all, id: \.number) { rank in
                            row(rank)
                            if rank.number < AdventurerRank.all.count { Divider().overlay(QColor.line) }
                        }
                    }
                    .sheetCard()
                    Text("Справа — порог очков и цвет ауры ранга.").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                }
                .padding(QSpacing.screen)
            }
            .paperScreen()
            .navigationTitle("Ранги")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .tint(QColor.amber)
    }

    private var current: some View {
        VStack(alignment: .leading, spacing: QSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(AdventurerRank.title(for: progress.rank)).font(QFont.title(22))
                Spacer()
                Text("\(Format.number(progress.rankPoints)) очков").font(QFont.text(13)).monospacedDigit()
            }
            if let next = progress.nextRank {
                ProgressBar(fraction: progress.rankPoints / Double(next.threshold), color: QColor.amber)
                Text("До \(next.letter) · \(next.title): ещё \(Format.number(max(0, Double(next.threshold) - progress.rankPoints))) очков (\(next.threshold))")
                    .font(QFont.text(13)).monospacedDigit()
            } else {
                Text("Высший ранг достигнут.").font(QFont.text(13))
            }
        }
        .foregroundStyle(QColor.sheet)
        .padding(QSpacing.xl)
        .background(QColor.ink, in: RoundedRectangle(cornerRadius: QRadius.card))
    }

    private func row(_ rank: AdventurerRank) -> some View {
        let currentNumber = progress.rank?.number ?? 0
        let isCurrent = rank.number == currentNumber
        let isPassed = rank.number < currentNumber
        let required = 2 * rank.number
        let missing = rank.number >= 6
            ? Attribute.allCases.filter { progress.classAttributes.contains($0) && (progress.levels[$0] ?? 0) < required }
            : []
        let aura = AuraArt.colors(AuraTier.of(rank))?.ring
        return HStack(spacing: QSpacing.m) {
            Text(rank.letter)
                .font(QFont.text(13, weight: .heavy))
                .frame(width: 38, height: 28)
                .background(isCurrent || isPassed ? QColor.amber : QColor.track, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(rank.title + (isCurrent ? " · сейчас" : isPassed ? " ✓" : ""))
                    .font(QFont.text(15, weight: isCurrent ? .bold : .regular))
                if rank.number >= 6 {
                    Text(missing.isEmpty ? "атрибуты класса ≥ \(required) ✓"
                                         : "атрибуты класса ≥ \(required) · " + missing.map { "\($0.code) \(progress.levels[$0] ?? 0)" }.joined(separator: ", "))
                        .font(QFont.text(11))
                        .foregroundStyle(missing.isEmpty ? QColor.forest : QColor.hp)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(rank.threshold)").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary).monospacedDigit()
            Circle()
                .strokeBorder(aura.map { Color(hex: $0) } ?? QColor.lineStrong, style: StrokeStyle(lineWidth: 2, dash: [2, 2]))
                .frame(width: 14, height: 14)
                .accessibilityLabel("Аура: \(AuraArt.title(AuraTier.of(rank)))")
        }
        .padding(.horizontal, QSpacing.l)
        .padding(.vertical, QSpacing.s)
        .background(isCurrent ? QColor.amber.opacity(0.18) : .clear)
        .accessibilityElement(children: .combine)
    }
}
