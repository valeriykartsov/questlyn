import SwiftUI
import Domain
import Application

/// Новый / изменить Daily или Weekly (макеты DailyNew, WeeklyNew).
struct HabitFormView: View {
    let model: AppModel
    let kind: HabitKind
    var editing: HabitDefinition?
    var onDone: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var draft: HabitDraft
    @State private var hasTime = false
    @State private var time = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
    @State private var isCreatingSkill = false
    @State private var isSaving = false

    init(model: AppModel, kind: HabitKind, editing: HabitDefinition? = nil, onDone: (() -> Void)? = nil) {
        self.model = model
        self.kind = kind
        self.editing = editing
        self.onDone = onDone
        if let habit = editing {
            _draft = State(initialValue: HabitDraft(kind: habit.kind, title: habit.title, details: habit.details ?? "",
                                                    skillId: habit.skillId, weekdays: habit.weekdays,
                                                    targetPerWeek: habit.targetPerWeek, time: habit.time))
            _hasTime = State(initialValue: habit.time != nil)
            if let t = habit.time, let date = Calendar.current.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: .now) {
                _time = State(initialValue: date)
            }
        } else {
            _draft = State(initialValue: HabitDraft(kind: kind))
        }
    }

    var body: some View {
        Form {
            Section {
                TextField(kind == .daily ? "Что повторять" : "Что сделать за неделю", text: $draft.title, prompt: Text(kind == .daily ? "Что повторять" : "Что сделать за неделю").foregroundStyle(QColor.placeholder), axis: .vertical)
                    .font(QFont.text(17, weight: .semibold))
                TextField("Описание · необязательно", text: $draft.details, prompt: Text("Описание · необязательно").foregroundStyle(QColor.placeholder), axis: .vertical)
                    .font(QFont.text(15))
                    .lineLimit(2...6)
            }
            .listRowBackground(QColor.sheet)

            if kind == .daily {
                Section {
                    HStack(spacing: QSpacing.s) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            let isOn = draft.weekdays.contains(day)
                            Button(day.shortTitle) {
                                if isOn { draft.weekdays.remove(day) } else { draft.weekdays.insert(day) }
                            }
                            .font(QFont.text(13, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(isOn ? QColor.sheet : QColor.ink)
                            .background(isOn ? QColor.ink : QColor.paper, in: RoundedRectangle(cornerRadius: QRadius.small))
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                    HStack {
                        Button("Каждый день") { draft.weekdays = Weekday.everyDay }
                        Spacer()
                        Button("Будни") { draft.weekdays = Weekday.workdays }
                    }
                    .font(QFont.text(14, weight: .medium))
                    .buttonStyle(.borderless)
                } header: {
                    Text("Дни")
                }
                .listRowBackground(QColor.sheet)
            } else {
                Section {
                    Stepper(value: $draft.targetPerWeek, in: 1...14) {
                        Text(Format.times(draft.targetPerWeek) + " в неделю").font(QFont.text(16, weight: .semibold))
                    }
                } header: {
                    Text("Сколько раз за неделю")
                } footer: {
                    Text("Дни любые. Итог считается в воскресенье 23:59.")
                }
                .listRowBackground(QColor.sheet)
            }

            Section {
                Picker("Навык", selection: $draft.skillId) {
                    Text("Не связан").tag(UUID?.none)
                    ForEach(model.activeProfessions) { profession in
                        let skills = model.skills.filter { $0.professionId == profession.id && $0.isActive }
                        if !skills.isEmpty {
                            Section(profession.title) { ForEach(skills) { Text($0.title).tag(UUID?.some($0.id)) } }
                        }
                    }
                }
                Button("Новый навык…") { isCreatingSkill = true }.foregroundStyle(QColor.amberDeep)
            } header: {
                Text("Навык")
            } footer: {
                Text(rewardHint)
            }
            .listRowBackground(QColor.sheet)

            if kind == .daily {
                Section("Время") {
                    Toggle("Указать время", isOn: $hasTime.animation())
                    if hasTime {
                        DatePicker("Время", selection: $time, displayedComponents: .hourAndMinute)
                            .environment(\.locale, Locale(identifier: "ru_RU"))
                    }
                }
                .listRowBackground(QColor.sheet)
            }
        }
        .tint(QColor.amber)
        .paperScreen()
            .keyboardDismissal()
        .navigationTitle(editing == nil ? (kind == .daily ? "Ежедневный квест" : "Недельный квест") : "Изменить")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onDone == nil || editing != nil {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { close() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? "Добавить" : "Сохранить", action: save)
                    .fontWeight(.semibold)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving
                              || (kind == .daily && draft.weekdays.isEmpty))
            }
        }
        .sheet(isPresented: $isCreatingSkill) { SkillFormView(model: model) { draft.skillId = $0.id } }
    }

    private var rewardHint: String {
        let base = kind == .daily ? "За каждую отметку: вклад в недельную дисциплину."
                                  : "За каждую отметку: в дисциплину — доля от цели, не больше 100%."
        return base + (draft.skillId == nil ? " С навыком — ещё +5 XP навыка и 5 XP атрибутам профессии. FOC не даёт."
                                            : " Навык +5 XP · 5 XP атрибутам профессии. FOC не даёт.")
    }

    private func close() {
        if let onDone, editing == nil { onDone() } else { dismiss() }
    }

    private func save() {
        var draft = draft
        if kind == .daily, hasTime {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            draft.time = LocalTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        } else {
            draft.time = nil
        }
        isSaving = true
        Task {
            let ok = if let editing { await model.updateHabit(editing.id, with: draft) } else { await model.createHabit(draft) }
            isSaving = false
            if ok { if let onDone { onDone() } else { dismiss() } }
        }
    }
}
