import SwiftUI
import Domain

/// Основная кнопка: чернила на бумаге.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QFont.text(16, weight: .semibold))
            .foregroundStyle(QColor.sheet)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(QColor.ink.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.35),
                        in: RoundedRectangle(cornerRadius: QRadius.control))
    }
}

/// Второстепенная кнопка с рамкой.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QFont.text(15, weight: .semibold))
            .foregroundStyle(QColor.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(QColor.sheet.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: QRadius.control))
            .overlay(RoundedRectangle(cornerRadius: QRadius.control).strokeBorder(QColor.lineStrong))
    }
}

/// Полоса из 7 атрибутов с уровнями (макет TodayV2).
struct AttributeStrip: View {
    let progress: HeroProgress

    var body: some View {
        HStack(spacing: QSpacing.xs) {
            ForEach(Attribute.allCases, id: \.self) { attribute in
                VStack(spacing: QSpacing.xxs) {
                    Text(attribute.code)
                        .font(QFont.text(11, weight: .semibold))
                        .foregroundStyle(QColor.inkSecondary)
                    Text(progress.level(attribute), format: .number)
                        .font(QFont.text(17, weight: .bold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(attribute.title), уровень \(progress.level(attribute))")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, QSpacing.s)
        .sheetCard()
    }
}

/// Тонкая полоса прогресса.
struct ProgressBar: View {
    let fraction: Double
    var color: Color = QColor.ink

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(QColor.track)
                Capsule().fill(color).frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
    }
}

/// Строка «название · значение» в карточках.
struct InfoRow: View {
    let label: String
    let value: String
    var note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(QFont.text(13))
                .foregroundStyle(QColor.inkSecondary)
            Spacer(minLength: QSpacing.l)
            VStack(alignment: .trailing, spacing: QSpacing.xxs) {
                Text(value).font(QFont.text(15, weight: .semibold))
                if let note {
                    Text(note).font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                }
            }
            .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
    }
}

extension View {
    /// Фон бумаги и цвет чернил для экрана.
    /// Клавиатуру можно свернуть: прокруткой и кнопкой «Готово» над клавиатурой.
    func keyboardDismissal() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                }
            }
    }

    func paperScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(QColor.paper.ignoresSafeArea())
            .foregroundStyle(QColor.ink)
    }
}

extension AdventurerRank {
    /// «Ранг D · Искатель» или «Без ранга».
    static func title(for rank: AdventurerRank?) -> String { displayName(for: rank) }
}
