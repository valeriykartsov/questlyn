import SwiftUI
import Domain
import Application

/// Состояние выбора профессий — общее для онбординга и смены профессий.
@Observable
final class ProfessionSetup {
    var choices: [ProfessionChoice]
    var classTitle: String

    init(choices: [ProfessionChoice] = [], classTitle: String = "") {
        self.choices = choices
        self.classTitle = classTitle
    }

    func isSelected(_ item: ProfessionCatalogItem) -> Bool { choices.contains { $0.catalogItemId == item.id } }

    func toggle(_ item: ProfessionCatalogItem) {
        if let index = choices.firstIndex(where: { $0.catalogItemId == item.id }) {
            choices.remove(at: index)
        } else if choices.count < 3, let choice = ProfessionChoice.catalog(item.id) {
            choices.append(choice)
        }
    }

    var customChoices: [ProfessionChoice] { choices.filter { $0.catalogItemId == nil } }

    /// Атрибуты класса в порядке STR…CHR.
    var classAttributes: [Attribute] {
        Attribute.professionSelectable.filter { a in choices.contains { $0.attributes.contains(a) } }
    }

    func isShared(_ attribute: Attribute) -> Bool { choices.filter { $0.attributes.contains(attribute) }.count > 1 }

    /// Стартовый бонус: основной атрибут каждой профессии +1 уровень (02).
    var startBonus: [(Attribute, Int)] {
        var counts: [Attribute: Int] = [:]
        for choice in choices { if let primary = choice.attributes.first { counts[primary, default: 0] += 1 } }
        return Attribute.professionSelectable.compactMap { a in counts[a].map { (a, $0) } }
    }

    /// Подсказки названия класса: «Инженер-атлет», «Атлет-инженер».
    var suggestions: [String] {
        let words = choices.map { $0.title.split(whereSeparator: { $0 == " " || $0 == "-" }).first.map(String.init) ?? $0.title }
        guard words.count >= 2 else { return words.isEmpty ? [] : [choices[0].title] }
        return [words[0] + "-" + words[1].lowercased(), words[1] + "-" + words[0].lowercased()]
    }

    var defaultClassTitle: String { suggestions.first ?? choices.map(\.title).joined(separator: " · ") }
}

/// Шаг «Чем вы занимаетесь?» (макет Onboarding).
struct ProfessionPickerStep: View {
    @Bindable var setup: ProfessionSetup
    @State private var search = ""
    @State private var isAddingCustom = false

    private var items: [ProfessionCatalogItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return ProfessionCatalog.items.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(QColor.inkSecondary)
                TextField("Поиск профессии", text: $search, prompt: Text("Поиск профессии").foregroundStyle(QColor.placeholder)).font(QFont.text(15))
            }
            .padding(.horizontal, QSpacing.xl)
            .frame(height: 44)
            .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
            .overlay(RoundedRectangle(cornerRadius: QRadius.control).strokeBorder(QColor.line))

            ForEach(items) { item in
                row(title: item.title, attributes: item.attributes, isOn: setup.isSelected(item),
                    isPrimary: setup.choices.first?.catalogItemId == item.id) { setup.toggle(item) }
            }
            ForEach(Array(setup.customChoices.enumerated()), id: \.offset) { _, choice in
                row(title: choice.title, attributes: choice.attributes, isOn: true,
                    isPrimary: setup.choices.first == choice) { setup.choices.removeAll { $0 == choice } }
            }
            Button { isAddingCustom = true } label: {
                Label("Своя профессия", systemImage: "plus")
                    .font(QFont.text(15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(RoundedRectangle(cornerRadius: QRadius.card).strokeBorder(Color(hex: 0xB8A98A), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            .buttonStyle(.plain)
            .disabled(setup.choices.count >= 3)
            .opacity(setup.choices.count >= 3 ? 0.5 : 1)

            Text("Выбрано \(setup.choices.count) из 3 · первая выбранная — основная, атрибуты настроите на следующем шаге")
                .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .sheet(isPresented: $isAddingCustom) {
            CustomProfessionForm { setup.choices.append($0) }
        }
    }

    private func row(title: String, attributes: [Attribute], isOn: Bool, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        let disabled = !isOn && setup.choices.count >= 3
        return Button(action: action) {
            HStack(spacing: QSpacing.l) {
                VStack(alignment: .leading, spacing: QSpacing.xs) {
                    Text(title).font(QFont.text(16, weight: .semibold))
                    Text(attributes.map(\.code).joined(separator: " · ")).font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                }
                Spacer()
                if isPrimary { Text("Основная").font(QFont.text(12, weight: .semibold)).foregroundStyle(QColor.amberDeep) }
                ZStack {
                    if isOn {
                        Circle().fill(QColor.ink)
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(QColor.sheet)
                    } else {
                        Circle().strokeBorder(QColor.lineStrong, lineWidth: 2)
                    }
                }
                .frame(width: 26, height: 26)
            }
            .padding(.horizontal, QSpacing.xl)
            .frame(minHeight: 60)
            .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.card))
            .overlay(RoundedRectangle(cornerRadius: QRadius.card).strokeBorder(isOn ? QColor.ink : QColor.line, lineWidth: isOn ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// «Своя профессия»: название и 1–3 атрибута по приоритету.
struct CustomProfessionForm: View {
    let onCreate: (ProfessionChoice) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var attributes: [Attribute] = [.intelligence]

    var body: some View {
        NavigationStack {
            Form {
                Section("Профессия") {
                    TextField("Например, Музыкант", text: $title, prompt: Text("Например, Музыкант").foregroundStyle(QColor.placeholder)).font(QFont.text(17))
                }
                .listRowBackground(QColor.sheet)
                Section {
                    AttributeSlots(attributes: $attributes)
                } header: {
                    Text("Атрибуты по приоритету")
                } footer: {
                    Text("От 1 до 3. FOC и DIS не выбираются: они растут от квестов и привычек.")
                }
                .listRowBackground(QColor.sheet)
            }
            .tint(QColor.amber)
            .paperScreen()
            .keyboardDismissal()
            .navigationTitle("Своя профессия")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        onCreate(ProfessionChoice(title: title.trimmingCharacters(in: .whitespaces), attributes: attributes))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || attributes.isEmpty)
                }
            }
        }
    }
}

/// Слоты атрибутов профессии: основной / вторичный / третичный (макет OnbAttrs).
struct AttributeSlots: View {
    @Binding var attributes: [Attribute]
    private let roles = ["Основной", "Вторичный", "Третичный"]

    var body: some View {
        VStack(spacing: QSpacing.m) {
            ForEach(Array(attributes.enumerated()), id: \.offset) { index, attribute in
                Menu {
                    ForEach(Attribute.professionSelectable, id: \.self) { option in
                        Button("\(option.code) · \(option.title)") { set(option, at: index) }
                            .disabled(attributes.contains(option) && option != attribute)
                    }
                    if attributes.count > 1 {
                        Divider()
                        Button("Убрать", role: .destructive) { attributes.remove(at: index) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(QFont.text(12, weight: .bold)).foregroundStyle(QColor.sheet)
                            .frame(width: 22, height: 22)
                            .background(QColor.ink, in: RoundedRectangle(cornerRadius: QRadius.chip))
                        Text(roles[index]).font(QFont.text(14)).foregroundStyle(QColor.inkSecondary)
                        Spacer()
                        Text(attribute.code).font(QFont.text(15, weight: .bold)).foregroundStyle(QColor.ink)
                        Text(attribute.title).font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(QColor.inkSecondary)
                    }
                    .padding(.horizontal, QSpacing.l)
                    .frame(height: 44)
                    .background(QColor.paper, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(QColor.line))
                }
            }
            if attributes.count < 3, let next = Attribute.professionSelectable.first(where: { !attributes.contains($0) }) {
                Button("+ Атрибут") { attributes.append(next) }
                    .font(QFont.text(14, weight: .semibold)).foregroundStyle(QColor.amberDeep)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func set(_ option: Attribute, at index: Int) {
        if let other = attributes.firstIndex(of: option), other != index { attributes.swapAt(index, other) } else { attributes[index] = option }
    }
}

/// Шаг «Что развивает профессия?» (макет OnbAttrs).
struct ProfessionAttributesStep: View {
    @Bindable var setup: ProfessionSetup

    var body: some View {
        VStack(alignment: .leading, spacing: QSpacing.l) {
            ForEach(setup.choices.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: QSpacing.m) {
                    Text(setup.choices[index].title).font(QFont.text(16, weight: .semibold))
                    AttributeSlots(attributes: $setup.choices[index].attributes)
                }
                .padding(QSpacing.xl)
                .background(QColor.sheet, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(QColor.line))
            }
            VStack(alignment: .leading, spacing: QSpacing.m) {
                ForEach(setup.classAttributes.filter(setup.isShared), id: \.self) { attribute in
                    Text("**\(attribute.code)** есть в нескольких профессиях — в вашем классе он растёт быстрее.")
                }
                Text("**FOC** и **DIS** не выбираются: они растут от квестов и привычек.")
            }
            .font(QFont.text(13))
            .foregroundStyle(Color(hex: 0x5C3410))
            .padding(.horizontal, QSpacing.xl)
            .padding(.vertical, QSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0xF1E3D3), in: RoundedRectangle(cornerRadius: QRadius.card))
        }
    }
}

/// Шаг «Как назовём класс?» (макет OnbClass): название, подсказки, атрибуты класса, стартовый бонус.
struct ClassStep: View {
    @Bindable var setup: ProfessionSetup
    var showsBonus = true

    var body: some View {
        VStack(alignment: .leading, spacing: QSpacing.l) {
            VStack(alignment: .leading, spacing: QSpacing.s) {
                CapsHeader(title: "Название класса")
                TextField(setup.defaultClassTitle, text: $setup.classTitle, prompt: Text(setup.defaultClassTitle).foregroundStyle(QColor.placeholder))
                    .font(QFont.text(17, weight: .semibold))
                    .padding(.horizontal, QSpacing.xl)
                    .frame(height: 52)
                    .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
                    .overlay(RoundedRectangle(cornerRadius: QRadius.control).strokeBorder(QColor.ink, lineWidth: 2))
            }
            if !setup.suggestions.isEmpty {
                HStack(spacing: QSpacing.m) {
                    ForEach(setup.suggestions, id: \.self) { suggestion in
                        Button(suggestion) { setup.classTitle = suggestion }
                            .font(QFont.text(14, weight: .medium))
                            .padding(.horizontal, QSpacing.xl)
                            .frame(height: 36)
                            .overlay(Capsule().strokeBorder(QColor.lineStrong))
                            .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: QSpacing.s) {
                Text(setup.classTitle.isEmpty ? setup.defaultClassTitle : setup.classTitle).font(QFont.title(20))
                Text(setup.choices.map(\.title).joined(separator: "\n")).font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                HStack(spacing: QSpacing.xs) {
                    ForEach(setup.classAttributes, id: \.self) { attribute in
                        let shared = setup.isShared(attribute)
                        Text(attribute.code)
                            .font(QFont.text(12, weight: .bold))
                            .padding(.horizontal, QSpacing.m).padding(.vertical, QSpacing.xxs)
                            .foregroundStyle(shared ? QColor.sheet : QColor.ink)
                            .background(shared ? QColor.ink : Color(hex: 0xE6E8EE), in: Capsule())
                    }
                }
                if showsBonus, !setup.startBonus.isEmpty {
                    Text("Стартовый бонус: " + setup.startBonus.map { "\($0.0.code) +\($0.1)" }.joined(separator: ", "))
                        .font(QFont.text(13, weight: .semibold))
                        .foregroundStyle(QColor.forest)
                }
            }
            .padding(QSpacing.screen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.hero))
            .overlay(RoundedRectangle(cornerRadius: QRadius.hero).strokeBorder(QColor.line))
        }
    }
}
