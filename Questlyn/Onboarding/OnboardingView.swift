import SwiftUI
import Domain
import Application

/// Полный онбординг (макеты OnbHero, Onboarding, OnbAttrs, OnbClass): герой → профессии → атрибуты → класс.
/// На шаге «Класс» выбирается образ героя (макет 8.7).
struct OnboardingView: View {
    let model: AppModel
    /// Только для отладки: открыть сразу шаг «Класс» с двумя профессиями.
    var debugClassStep = false

    private enum Step: Int, CaseIterable { case hero, professions, attributes, heroClass }

    @State private var step: Step = .hero
    @State private var name = ""
    @State private var appearance = HeroAppearance.default
    @State private var setup = ProfessionSetup()
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: QSpacing.screen) {
                    header
                    switch step {
                    case .hero: heroStep
                    case .professions: ProfessionPickerStep(setup: setup)
                    case .attributes: ProfessionAttributesStep(setup: setup)
                    case .heroClass:
                        ClassStep(setup: setup)
                        VStack(alignment: .leading, spacing: QSpacing.s) {
                            CapsHeader(title: "Образ героя")
                            OutfitPicker(appearance: $appearance, accent: accent)
                        }
                        Text("Цвет одежды — по основной профессии. Образ, профессии и название класса можно сменить позже — прогресс сохранится. Ранг появится после первых выполненных квестов.")
                            .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
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
        .padding(.horizontal, 20)
        .paperScreen()
            .keyboardDismissal()
        .onAppear {
            guard debugClassStep, setup.choices.isEmpty else { return }
            name = "Арин"
            setup.choices = ["software-engineer", "athlete"].compactMap(ProfessionChoice.catalog)
            step = .heroClass
        }
    }

    /// Назад · 4 полоски шагов · «N / 4».
    private var topBar: some View {
        HStack {
            Button {
                withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .hero }
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44, alignment: .leading)
            }
            .foregroundStyle(QColor.ink)
            .opacity(step == .hero ? 0 : 1)
            .disabled(step == .hero)
            .accessibilityLabel("Назад")
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule().fill(s.rawValue <= step.rawValue ? QColor.ink : Color(hex: 0xD9CDB6)).frame(width: 28, height: 4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Шаг \(step.rawValue + 1) из 4")
            Spacer()
            Text("\(step.rawValue + 1) / 4")
                .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary).monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
        .frame(height: 44)
    }

    private var header: some View {
        let texts: (String, String) = switch step {
        case .hero: ("Создайте героя", "Герой будет расти вместе с вашими реальными делами. Внешность можно поменять позже.")
        case .professions: ("Чем вы занимаетесь?", "Выберите до трёх профессий. Из них сложится ваш класс, а атрибуты профессий будут расти от квестов.")
        case .attributes: ("Что развивает профессия?", "От 1 до 3 атрибутов по приоритету. Мы подставили значения из каталога — поменяйте, если у вас иначе.")
        case .heroClass: ("Класс и образ", "Класс — это сочетание ваших профессий. Название и образ героя выбираете вы.")
        }
        return VStack(alignment: .leading, spacing: QSpacing.s) {
            Text(texts.0).font(QFont.title(28))
            Text(texts.1).font(QFont.text(15)).foregroundStyle(QColor.inkSecondary)
        }
    }

    private var heroStep: some View {
        VStack(alignment: .leading, spacing: QSpacing.screen) {
            HeroStage(appearance: appearance, accent: accent, scale: 3, height: 200)
            VStack(alignment: .leading, spacing: QSpacing.s) {
                CapsHeader(title: "Имя героя")
                TextField("Например, Странник", text: $name, prompt: Text("Например, Странник").foregroundStyle(QColor.placeholder))
                    .font(QFont.text(17, weight: .medium))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit(next)
                    .padding(.horizontal, QSpacing.xl)
                    .frame(height: 52)
                    .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
                    .overlay(RoundedRectangle(cornerRadius: QRadius.control).strokeBorder(QColor.ink, lineWidth: 2))
            }
            VStack(alignment: .leading, spacing: QSpacing.l) {
                SwatchRow(title: "Волосы", options: HeroAppearance.Hair.allCases, selected: appearance.hair) { appearance.hair = $0 }
                SwatchRow(title: "Кожа", options: HeroAppearance.Skin.allCases, selected: appearance.skin) { appearance.skin = $0 }
                Text("Образ героя выберете на шаге «Класс», цвет одежды задаёт основная профессия.")
                    .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
            }
        }
    }

    /// Цвет одежды — по первой выбранной профессии.
    private var accent: UInt32 { setup.choices.first.map { HeroAccent.hex(catalogItemId: $0.catalogItemId) } ?? HeroAccent.fallback }

    private var canContinue: Bool {
        switch step {
        case .hero: !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .professions: !setup.choices.isEmpty
        case .attributes: setup.choices.allSatisfy { !$0.attributes.isEmpty }
        case .heroClass: true
        }
    }

    private func next() {
        guard canContinue else { return }
        if let following = Step(rawValue: step.rawValue + 1) {
            withAnimation { step = following }
            return
        }
        isSaving = true
        Task {
            let title = setup.classTitle.trimmingCharacters(in: .whitespaces).isEmpty ? setup.defaultClassTitle : setup.classTitle
            _ = await model.startAdventure(name: name, appearance: appearance, professions: setup.choices, classTitle: title)
            isSaving = false
        }
    }
}

/// Цвета волос и кожи из макета OnbHero.
protocol AppearanceSwatch: Hashable {
    var color: Color { get }
    var label: String { get }
}

extension HeroAppearance.Hair: AppearanceSwatch {
    var color: Color { Color(hex: hex) }

    var label: String {
        switch self {
        case .dark: "Тёмные волосы"
        case .red: "Рыжие волосы"
        case .blond: "Светлые волосы"
        case .black: "Чёрные волосы"
        }
    }
}

extension HeroAppearance.Skin: AppearanceSwatch {
    var color: Color { Color(hex: hex) }

    var label: String {
        switch self {
        case .light: "Светлая кожа"
        case .medium: "Средняя кожа"
        case .tan: "Смуглая кожа"
        case .deep: "Тёмная кожа"
        }
    }
}

#Preview {
    OnboardingView(model: AppEnvironment.preview())
}
