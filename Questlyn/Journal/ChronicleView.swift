import SwiftUI
import Domain
import Application

/// Летопись героя (макет Chronicle 5.3): лента по дням, новые сверху, фильтры.
struct ChronicleView: View {
    let model: AppModel
    @State private var category: ChronicleCategory?

    private var days: [ChronicleDay] {
        model.chronicle.compactMap { day in
            let items = day.items.filter { category == nil || $0.category == category }
            return items.isEmpty ? nil : ChronicleDay(date: day.date, items: items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: QSpacing.l) {
            filterBar
            if days.isEmpty {
                Text(category == nil ? "Здесь появится всё, что происходит с героем: квесты, привычки, сон и вехи."
                                     : "За это время записей «\(category!.title)» нет.")
                    .font(QFont.text(14))
                    .foregroundStyle(QColor.inkSecondary)
                    .padding(.top, QSpacing.l)
            }
            ForEach(days) { day in
                daySection(day)
            }
        }
        .task { await model.loadChronicle() }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: QSpacing.m) {
                chip("Все", isOn: category == nil) { category = nil }
                ForEach(ChronicleCategory.allCases, id: \.self) { item in
                    chip(item.title, isOn: category == item) { category = item }
                }
            }
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(QFont.text(14, weight: isOn ? .semibold : .medium))
            .padding(.horizontal, QSpacing.xl)
            .frame(height: 34)
            .foregroundStyle(isOn ? QColor.sheet : QColor.ink)
            .background(isOn ? QColor.ink : QColor.sheet, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? QColor.ink : QColor.lineStrong))
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func daySection(_ day: ChronicleDay) -> some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayTitle(day.date)).font(QFont.title(18))
                Spacer()
                Text(Format.records(day.items.count))
                    .font(QFont.text(12, weight: .semibold))
                    .foregroundStyle(QColor.inkSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(day.items.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < day.items.count - 1 { Divider().overlay(QColor.line).padding(.leading, 58) }
                }
            }
            .padding(.vertical, QSpacing.xs)
            .sheetCard()
        }
    }

    private func dayTitle(_ date: LocalDate) -> String {
        let today = model.today
        let prefix: String? = date == today ? "Сегодня" : date == today.adding(days: -1) ? "Вчера" : nil
        guard let value = date.date else { return date.description }
        let text = value.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "ru_RU")))
        if let prefix { return "\(prefix), \(text)" }
        return Format.longDay(value)
    }

    private func row(_ item: ChronicleItem) -> some View {
        HStack(alignment: .top, spacing: QSpacing.l) {
            Text(item.at.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                .font(QFont.text(12, weight: .semibold))
                .foregroundStyle(QColor.inkSecondary)
                .monospacedDigit()
                .frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                HStack(spacing: QSpacing.s) {
                    if item.isMilestone {
                        Image(systemName: "flag.fill").font(.system(size: 11)).foregroundStyle(QColor.amber)
                    }
                    Text(item.title)
                        .font(QFont.text(15, weight: item.isMilestone ? .semibold : .regular))
                        .strikethrough(item.isCancelled, color: QColor.inkSecondary)
                        .foregroundStyle(item.isCancelled ? QColor.inkSecondary : QColor.ink)
                }
                if let detail = item.detail {
                    Text(detail).font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                }
                if let note = item.note {
                    Text(note).font(QFont.text(12, weight: .semibold)).foregroundStyle(QColor.amberDeep)
                }
                if !item.changes.isEmpty {
                    FlowLine(changes: item.changes)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, QSpacing.xl)
        .padding(.vertical, QSpacing.m)
        .accessibilityElement(children: .combine)
    }
}

/// Изменения строки: «+5 FOC», «+10 Отчётность», «−4 MP».
private struct FlowLine: View {
    let changes: [ChronicleChange]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: QSpacing.m) { content }
            VStack(alignment: .leading, spacing: QSpacing.xxs) { content }
        }
    }

    @ViewBuilder private var content: some View {
        ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
            let (text, color) = describe(change)
            Text(text).font(QFont.text(12, weight: .semibold)).foregroundStyle(color).monospacedDigit()
        }
    }

    private func describe(_ change: ChronicleChange) -> (String, Color) {
        switch change {
        case let .xp(label, amount):
            return ("\(Format.signedXP(amount)) \(label)", amount.value < 0 ? QColor.amberDeep : QColor.forest)
        case let .hp(value):
            return ("\(Format.signedWhole(value)) HP", QColor.hp)
        case let .mp(value):
            return ("\(Format.signedWhole(value)) MP", QColor.mp)
        }
    }
}
