import SwiftUI
import Domain

/// Короткий онбординг этапа 1: имя → профессии → класс (макеты OnbHero, Onboarding, OnbClass).
/// Внешность и настройка атрибутов профессий — этап 3.5.
struct OnboardingView: View {
    let model: AppModel

    private enum Step: Int, CaseIterable { case hero, professions, heroClass }

    @State private var step: Step = .hero
    @State private var name = ""
    @State private var selected: [String] = []
    @State private var classTitle = ""
    @State private var isSaving = false

    private var selectedItems: [ProfessionCatalogItem] { selected.compactMap(ProfessionCatalog.item(id:)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if step != .hero {
                    Button {
                        withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .hero }
                    } label: {
                        Label("Назад", systemImage: "chevron.left").font(QFont.text(15, weight: .medium))
                    }
                    .foregroundStyle(QColor.amberDeep)
                }
                Spacer()
                Text("\(step.rawValue + 1) / \(Step.allCases.count)")
                    .font(QFont.text(13, weight: .semibold))
                    .foregroundStyle(QColor.inkSecondary)
                    .monospacedDigit()
            }
            .frame(height: 44)

            ScrollView {
                VStack(alignment: .leading, spacing: QSpacing.l) {
                    switch step {
                    case .hero: heroStep
                    case .professions: professionsStep
                    case .heroClass: classStep
                    }
                }
                .padding(.top, QSpacing.l)
                .padding(.bottom, QSpacing.screen)
            }
            .scrollDismissesKeyboard(.interactively)

            Button(step == .heroClass ? "Начать приключение" : "Далее", action: next)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canContinue || isSaving)
                .padding(.bottom, QSpacing.l)
        }
        .padding(.horizontal, QSpacing.screen)
        .paperScreen()
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            Text(title).font(QFont.title(28))
            Text(subtitle).font(QFont.text(15)).foregroundStyle(QColor.inkSecondary)
        }
    }

    private var heroStep: some View {
        VStack(alignment: .leading, spacing: QSpacing.l) {
            header("Создайте героя", "Герой будет расти вместе с вашими реальными делами.")
            VStack(alignment: .leading, spacing: QSpacing.s) {
                Text("Имя героя").font(QFont.text(13, weight: .semibold)).foregroundStyle(QColor.inkSecondary)
                TextField("Например, Арин", text: $name)
                    .font(QFont.text(17))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit(next)
                    .padding(.horizontal, QSpacing.xl)
                    .frame(height: 50)
                    .sheetCard()
            }
        }
    }

    private var professionsStep: some View {
        VStack(alignment: .leading, spacing: QSpacing.l) {
            header("Чем вы занимаетесь?", "Выберите до трёх профессий. Из них сложится ваш класс, а атрибуты профессий будут расти от квестов.")
            VStack(spacing: QSpacing.m) {
                ForEach(ProfessionCatalog.items) { item in
                    professionRow(item)
                }
            }
            Text("Выбрано \(selected.count) из 3 · первая выбранная — основная профессия")
                .font(QFont.text(13))
                .foregroundStyle(QColor.inkSecondary)
        }
    }

    private func professionRow(_ item: ProfessionCatalogItem) -> some View {
        let index = selected.firstIndex(of: item.id)
        let isOn = index != nil
        return Button {
            if let index { selected.remove(at: index) } else if selected.count < 3 { selected.append(item.id) }
        } label: {
            HStack(spacing: QSpacing.l) {
                VStack(alignment: .leading, spacing: QSpacing.xxs) {
                    Text(item.title).font(QFont.text(16, weight: .semibold))
                    Text(item.attributes.map(\.code).joined(separator: " · "))
                        .font(QFont.text(13))
                        .foregroundStyle(QColor.inkSecondary)
                }
                Spacer()
                if index == 0 {
                    Text("Основная")
                        .font(QFont.text(12, weight: .semibold))
                        .foregroundStyle(QColor.amberDeep)
                }
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isOn ? QColor.ink : QColor.lineStrong)
            }
            .padding(.horizontal, QSpacing.xl)
            .padding(.vertical, QSpacing.l)
            .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.card))
            .overlay(RoundedRectangle(cornerRadius: QRadius.card).strokeBorder(isOn ? QColor.ink : QColor.line, lineWidth: isOn ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isOn && selected.count >= 3)
        .opacity(!isOn && selected.count >= 3 ? 0.5 : 1)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var classStep: some View {
        let attributes = Attribute.professionSelectable.filter { a in selectedItems.contains { $0.attributes.contains(a) } }
        return VStack(alignment: .leading, spacing: QSpacing.l) {
            header("Как назовём класс?", "Класс — это сочетание ваших профессий. Название придумываете вы.")
            VStack(alignment: .leading, spacing: QSpacing.s) {
                Text("Название класса").font(QFont.text(13, weight: .semibold)).foregroundStyle(QColor.inkSecondary)
                TextField(selectedItems.map(\.title).joined(separator: " · "), text: $classTitle)
                    .font(QFont.text(17))
                    .padding(.horizontal, QSpacing.xl)
                    .frame(height: 50)
                    .sheetCard()
            }
            VStack(alignment: .leading, spacing: QSpacing.m) {
                ForEach(selectedItems) { item in
                    HStack {
                        Text(item.title).font(QFont.text(15, weight: .semibold))
                        Spacer()
                        Text(item.attributes.map(\.code).joined(separator: " · "))
                            .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                    }
                }
                Divider().overlay(QColor.line)
                Text("Атрибуты класса: " + attributes.map(\.code).joined(separator: ", "))
                    .font(QFont.text(13, weight: .semibold))
            }
            .padding(QSpacing.xl)
            .sheetCard()
            Text("Ранг появится после первых выполненных квестов.")
                .font(QFont.text(13))
                .foregroundStyle(QColor.inkSecondary)
        }
    }

    private var canContinue: Bool {
        switch step {
        case .hero: !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .professions: !selected.isEmpty
        case .heroClass: true
        }
    }

    private func next() {
        guard canContinue else { return }
        switch step {
        case .hero: withAnimation { step = .professions }
        case .professions: withAnimation { step = .heroClass }
        case .heroClass:
            isSaving = true
            Task {
                _ = await model.startAdventure(name: name, catalogItemIds: selected, classTitle: classTitle)
                isSaving = false
            }
        }
    }
}

#Preview {
    OnboardingView(model: AppEnvironment.preview())
}
