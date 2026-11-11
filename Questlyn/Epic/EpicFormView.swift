import SwiftUI
import Domain
import Application

/// «Новый Epic» и «Изменить Epic» (макет EpicNew): цель, описание, срок, шаги; в изменении — удаление с подтверждением.
struct EpicFormView: View {
    let model: AppModel
    var onDone: (() -> Void)?
    /// Изменение существующего Epic.
    var editing: EpicStatus?
    @Environment(\.dismiss) private var dismiss

    struct StepRow: Identifiable {
        let id = UUID()
        var questId: UUID?
        var title: String
        var isDone = false
    }

    @State private var title = ""
    @State private var details = ""
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now
    @State private var steps: [StepRow] = [StepRow(title: ""), StepRow(title: "")]
    @State private var isSaving = false
    @State private var isConfirmingDelete = false
    @State private var professionId: UUID?

    init(model: AppModel, onDone: (() -> Void)? = nil, editing: EpicStatus? = nil) {
        self.model = model
        self.onDone = onDone
        self.editing = editing
        if let editing {
            _title = State(initialValue: editing.epic.title)
            _details = State(initialValue: editing.epic.details ?? "")
            _hasDeadline = State(initialValue: editing.epic.deadline != nil)
            if let date = editing.epic.deadline?.date { _deadline = State(initialValue: date) }
            _professionId = State(initialValue: editing.epic.professionId)
            _steps = State(initialValue: editing.steps.map { StepRow(questId: $0.quest.id, title: $0.quest.title, isDone: $0.isCompleted) })
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Большая цель", text: $title, prompt: Text("Большая цель").foregroundStyle(QColor.placeholder), axis: .vertical)
                    .font(QFont.text(17, weight: .semibold))
                TextField("Описание · необязательно", text: $details, prompt: Text("Описание · необязательно").foregroundStyle(QColor.placeholder), axis: .vertical)
                    .font(QFont.text(15)).lineLimit(2...6)
            }
            .listRowBackground(QColor.sheet)

            Section {
                Picker("Профессия", selection: $professionId) {
                    Text("Без профессии").tag(UUID?.none)
                    ForEach(activeProfessions) { profession in
                        Text(profession.title).tag(UUID?.some(profession.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Профессия · необязательно")
            } footer: {
                Text("Epic с профессией выделяется акцентом и стоит в журнале выше остальных. Навык и награды шагов не меняются — их задаёт каждый шаг.")
            }
            .listRowBackground(QColor.sheet)

            Section("Срок · необязательно") {
                Toggle("Указать срок", isOn: $hasDeadline.animation())
                if hasDeadline {
                    DatePicker("До", selection: $deadline, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "ru_RU"))
                }
            }
            .listRowBackground(QColor.sheet)

            Section {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, row in
                    HStack {
                        TextField("Шаг \(index + 1)", text: $steps[index].title, prompt: Text("Шаг \(index + 1)").foregroundStyle(QColor.placeholder))
                        if row.isDone { Image(systemName: "checkmark.circle.fill").foregroundStyle(QColor.forest).accessibilityLabel("выполнен") }
                    }
                }
                .onDelete { steps.remove(atOffsets: $0) }
                Button("Добавить шаг") { steps.append(StepRow(title: "")) }.foregroundStyle(QColor.amberDeep)
            } header: {
                Text(editing == nil ? "Шаги · можно добавить позже" : "Шаги · смахните влево, чтобы убрать")
            } footer: {
                Text("Epic не даёт XP сам по себе. Награду приносят шаги — это обычные квесты со своим приоритетом. Завершение Epic — веха в истории героя.")
            }
            .listRowBackground(QColor.sheet)

            if editing != nil {
                Section {
                    Button("Удалить Epic", role: .destructive) { isConfirmingDelete = true }
                } footer: {
                    Text("Epic и все его шаги пропадут из журнала. Награды за выполненные шаги останутся — прогресс не отнимается, в Летописи шаги сохранятся.")
                }
                .listRowBackground(QColor.sheet)
            }
        }
        .tint(QColor.amber)
        .confirmationDialog("Удалить Epic «\(title)»?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить Epic и шаги", role: .destructive) {
                guard let id = editing?.epic.id else { return }
                Task { if await model.deleteEpic(id) { dismiss() } }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Отменить нельзя. Начисления за выполненные шаги останутся.")
        }
        .paperScreen()
            .keyboardDismissal()
        .navigationTitle(editing == nil ? "Новый Epic" : "Изменить Epic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onDone == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? "Создать" : "Сохранить", action: save)
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
    }

    private var activeProfessions: [Profession] {
        (model.overview?.professions ?? []).filter(\.isActive).sorted { $0.slot < $1.slot }
    }

    private func save() {
        isSaving = true
        Task {
            let due = hasDeadline ? LocalDate(deadline, timeZone: .current) : nil
            let ok: Bool
            if let editing {
                let edits = steps.map { row -> EpicService.StepEdit in
                    // Существующий шаг сохраняет дату, время, приоритет и навык — меняется только название.
                    var draft = editing.steps.first { $0.quest.id == row.questId }.map { QuestDraft(quest: $0.quest) } ?? QuestDraft(title: row.title)
                    draft.title = row.title
                    return EpicService.StepEdit(id: row.questId, draft: draft)
                }
                ok = await model.updateEpic(editing.epic.id, title: title, details: details, deadline: due, steps: edits, professionId: professionId)
            } else {
                ok = await model.createEpic(title: title, details: details, deadline: due, steps: steps.map { QuestDraft(title: $0.title) },
                                            professionId: professionId)
            }
            isSaving = false
            if ok { if let onDone { onDone() } else { dismiss() } }
        }
    }
}
