import SwiftUI
import Domain
import Application

/// Форма «Новый квест» (макет QuestNew). Тип, Epic и мана — этапы 2 и 4.
struct QuestFormView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft = QuestDraft()
    @State private var hasDate = true
    @State private var day = Date.now
    @State private var hasTime = false
    @State private var time = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now
    @State private var isCreatingSkill = false
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Что нужно сделать", text: $draft.title, axis: .vertical)
                        .font(QFont.text(17, weight: .semibold))
                        .focused($titleFocused)
                    TextField("Описание · необязательно", text: $draft.details, axis: .vertical)
                        .font(QFont.text(15))
                        .lineLimit(2...6)
                }
                .listRowBackground(QColor.sheet)

                Section {
                    Picker("Приоритет", selection: $draft.priority) {
                        ForEach(QuestPriority.allCases, id: \.self) { Text(Format.priority($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    Text(rewardHint)
                        .font(QFont.text(12))
                        .foregroundStyle(QColor.inkSecondary)
                } header: {
                    Text("Приоритет · сложность")
                }
                .listRowBackground(QColor.sheet)

                Section {
                    Picker("Навык", selection: $draft.skillId) {
                        Text("Без навыка").tag(UUID?.none)
                        ForEach(model.activeProfessions) { profession in
                            let skills = model.skills.filter { $0.professionId == profession.id && $0.isActive }
                            if !skills.isEmpty {
                                Section(profession.title) {
                                    ForEach(skills) { Text($0.title).tag(UUID?.some($0.id)) }
                                }
                            }
                        }
                    }
                    Button("Новый навык…") { isCreatingSkill = true }
                        .foregroundStyle(QColor.amberDeep)
                } header: {
                    Text("Навык")
                } footer: {
                    Text("С навыком растут навык и атрибуты его профессии. Без навыка — только FOC.")
                }
                .listRowBackground(QColor.sheet)

                Section("Когда") {
                    Toggle("Дата", isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker("День", selection: $day, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "ru_RU"))
                        Toggle("Время", isOn: $hasTime.animation())
                        if hasTime {
                            DatePicker("Время", selection: $time, displayedComponents: .hourAndMinute)
                                .environment(\.locale, Locale(identifier: "ru_RU"))
                        }
                    }
                }
                .listRowBackground(QColor.sheet)
            }
            .tint(QColor.amber)
            .paperScreen()
            .navigationTitle("Новый квест")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить", action: save)
                        .fontWeight(.semibold)
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $isCreatingSkill) {
                SkillFormView(model: model) { draft.skillId = $0.id }
            }
            .onAppear { titleFocused = true }
        }
    }

    private var rewardHint: String {
        let k = draft.priority.multiplier
        let fmt = { (value: Double) in Format.number(value) }
        if draft.skillId == nil {
            return "\(Format.priority(draft.priority)): FOC +\(fmt(5 * k)). Низкий ×0,5, высокий ×1,5."
        }
        return "\(Format.priority(draft.priority)): FOC +\(fmt(5 * k)) · навык +\(fmt(10 * k)) XP · атрибуты \(fmt(10 * k)) XP. Низкий ×0,5, высокий ×1,5."
    }

    private func save() {
        var draft = draft
        draft.dueDate = hasDate ? LocalDate(day, timeZone: .current) : nil
        if hasDate, hasTime {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            draft.dueTime = LocalTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        } else {
            draft.dueTime = nil
        }
        isSaving = true
        Task {
            if await model.createQuest(draft) { dismiss() }
            isSaving = false
        }
    }
}

#Preview {
    QuestFormView(model: AppEnvironment.preview())
}
