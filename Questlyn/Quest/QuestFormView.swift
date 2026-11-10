import SwiftUI
import Domain
import Application

/// Форма «Новый квест» и «Изменить квест» (макет QuestNew). Мана — этап 4.
/// Встраивается в NavigationStack вызывающей стороны.
struct QuestFormView: View {
    let model: AppModel
    var editing: Quest?
    var onDone: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var draft: QuestDraft
    @State private var hasDate: Bool
    @State private var day: Date
    @State private var hasTime: Bool
    @State private var time: Date
    @State private var isCreatingSkill = false
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool

    init(model: AppModel, editing: Quest? = nil, epicId: UUID? = nil, onDone: (() -> Void)? = nil) {
        self.model = model
        self.editing = editing
        self.onDone = onDone
        let calendar = Calendar.current
        if let quest = editing {
            _draft = State(initialValue: QuestDraft(title: quest.title, details: quest.details ?? "", priority: quest.priority,
                                                    skillId: quest.skillId, dueDate: quest.dueDate, dueTime: quest.dueTime, epicId: quest.epicId))
            _hasDate = State(initialValue: quest.dueDate != nil)
            _day = State(initialValue: quest.dueDate?.date ?? .now)
            _hasTime = State(initialValue: quest.dueTime != nil)
            let t = quest.dueTime
            _time = State(initialValue: calendar.date(bySettingHour: t?.hour ?? 18, minute: t?.minute ?? 0, second: 0, of: .now) ?? .now)
        } else {
            _draft = State(initialValue: QuestDraft(epicId: epicId))
            _hasDate = State(initialValue: epicId == nil)
            _day = State(initialValue: .now)
            _hasTime = State(initialValue: false)
            _time = State(initialValue: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now)
        }
    }

    private var isCompleted: Bool {
        guard let editing else { return false }
        return model.questItem(id: editing.id)?.isCompleted ?? false
    }

    var body: some View {
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
                .disabled(isCompleted)
                Text(isCompleted ? "Квест выполнен: приоритет и навык не меняются. Отмените выполнение, чтобы изменить." : rewardHint)
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
                .disabled(isCompleted)
                if !isCompleted {
                    Button("Новый навык…") { isCreatingSkill = true }
                        .foregroundStyle(QColor.amberDeep)
                }
                let activeEpics = model.epics.filter { !$0.epic.isCompleted || $0.id == draft.epicId }
                if !activeEpics.isEmpty {
                    Picker("Epic", selection: $draft.epicId) {
                        Text("Не входит").tag(UUID?.none)
                        ForEach(activeEpics) { Text($0.epic.title).tag(UUID?.some($0.id)) }
                    }
                }
            } header: {
                Text("Навык и Epic")
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
        .navigationTitle(editing == nil ? "Новый квест" : "Изменить квест")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onDone == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? "Добавить" : "Сохранить", action: save)
                    .fontWeight(.semibold)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .sheet(isPresented: $isCreatingSkill) {
            SkillFormView(model: model) { draft.skillId = $0.id }
        }
        .onAppear { if editing == nil { titleFocused = true } }
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
            let ok = if let editing { await model.updateQuest(editing.id, with: draft) } else { await model.createQuest(draft) }
            isSaving = false
            if ok { if let onDone { onDone() } else { dismiss() } }
        }
    }
}
