import SwiftUI
import Domain
import Application

/// Экран «Сегодня» — каркас этапа 0: дата, атрибуты, пустой список квестов.
/// Карта дня, HP/MP и DIS появятся на этапах 4 и 6 (макет TodayV2).
struct TodayView: View {
    @State var model: TodayModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.l) {
                header
                attributes
                questsSection
            }
            .padding(.horizontal, QSpacing.screen)
            .padding(.top, QSpacing.l)
        }
        .background(QColor.paper)
        .foregroundStyle(QColor.ink)
        .overlay(alignment: .bottomTrailing) { addButton }
        .task { await model.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: QSpacing.xxs) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "ru_RU"))).capitalizedFirst)
                .font(QFont.text(13))
                .foregroundStyle(QColor.inkSecondary)
            Text("Сегодня")
                .font(QFont.title(30))
        }
    }

    private var attributes: some View {
        HStack(spacing: QSpacing.xs) {
            ForEach(model.attributeLevels, id: \.0) { attribute, level in
                VStack(spacing: QSpacing.xxs) {
                    Text(attribute.code)
                        .font(QFont.text(11, weight: .semibold))
                        .foregroundStyle(QColor.inkSecondary)
                    Text(level, format: .number)
                        .font(QFont.text(17, weight: .bold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, QSpacing.s)
        .sheetCard()
    }

    @ViewBuilder
    private var questsSection: some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            Text("Квесты на сегодня")
                .font(QFont.title(18))
            if let message = model.errorMessage {
                Text(message)
                    .font(QFont.text(13))
                    .foregroundStyle(QColor.hp)
            } else if model.overview?.quests.isEmpty ?? true {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: QSpacing.xs) {
            Text("Квестов пока нет")
                .font(QFont.text(15, weight: .semibold))
            Text("Скоро здесь можно будет создать первый квест и начать путь героя.")
                .font(QFont.text(13))
                .foregroundStyle(QColor.inkSecondary)
        }
        .padding(.vertical, QSpacing.l)
        .padding(.horizontal, QSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheetCard()
    }

    private var addButton: some View {
        Button {} label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(QColor.sheet)
                .frame(width: 56, height: 56)
                .background(QColor.amber, in: Circle())
        }
        .disabled(true)
        .opacity(0.5)
        .accessibilityLabel("Добавить квест — появится на этапе 1")
        .padding(QSpacing.screen)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

#Preview {
    TodayView(model: TodayModel(service: AppEnvironment.preview().todayService))
}
