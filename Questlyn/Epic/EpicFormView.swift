import SwiftUI
import Domain
import Application

/// «Новый Epic» (макет EpicNew): цель, описание, срок, шаги.
struct EpicFormView: View {
    let model: AppModel
    var onDone: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var details = ""
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now
    @State private var steps: [String] = ["", ""]
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                TextField("Большая цель", text: $title, prompt: Text("Большая цель").foregroundStyle(QColor.placeholder), axis: .vertical)
                    .font(QFont.text(17, weight: .semibold))
                TextField("Описание · необязательно", text: $details, prompt: Text("Описание · необязательно").foregroundStyle(QColor.placeholder), axis: .vertical)
                    .font(QFont.text(15)).lineLimit(2...6)
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
                ForEach(steps.indices, id: \.self) { index in
                    TextField("Шаг \(index + 1)", text: $steps[index], prompt: Text("Шаг \(index + 1)").foregroundStyle(QColor.placeholder))
                }
                .onDelete { steps.remove(atOffsets: $0) }
                Button("Добавить шаг") { steps.append("") }.foregroundStyle(QColor.amberDeep)
            } header: {
                Text("Шаги · можно добавить позже")
            } footer: {
                Text("Epic не даёт XP сам по себе. Награду приносят шаги — это обычные квесты со своим приоритетом. Завершение Epic — веха в истории героя.")
            }
            .listRowBackground(QColor.sheet)
        }
        .tint(QColor.amber)
        .paperScreen()
            .keyboardDismissal()
        .navigationTitle("Новый Epic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onDone == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Создать", action: save)
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            let ok = await model.createEpic(
                title: title, details: details,
                deadline: hasDeadline ? LocalDate(deadline, timeZone: .current) : nil,
                steps: steps.map { QuestDraft(title: $0) }
            )
            isSaving = false
            if ok { if let onDone { onDone() } else { dismiss() } }
        }
    }
}
