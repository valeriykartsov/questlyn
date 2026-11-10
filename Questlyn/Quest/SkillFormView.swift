import SwiftUI
import Domain

/// «Новый навык» (макет SkillNew). Мастерство и форма — этап 3.
struct SkillFormView: View {
    let model: AppModel
    var onCreate: (Skill) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var professionId: UUID?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Навык") {
                    TextField("Например, Отчётность", text: $title)
                        .font(QFont.text(17))
                }
                .listRowBackground(QColor.sheet)
                Section {
                    Picker("Профессия", selection: $professionId) {
                        ForEach(model.activeProfessions) { profession in
                            VStack(alignment: .leading) {
                                Text(profession.title)
                                Text(profession.attributes.map(\.code).joined(separator: " · "))
                            }
                            .tag(UUID?.some(profession.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Профессия")
                } footer: {
                    Text("XP показывает объём практики, а не уровень мастерства.")
                }
                .listRowBackground(QColor.sheet)
            }
            .tint(QColor.amber)
            .paperScreen()
            .navigationTitle("Новый навык")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить", action: save)
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || professionId == nil || isSaving)
                }
            }
            .onAppear { professionId = professionId ?? model.activeProfessions.first?.id }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let professionId else { return }
        isSaving = true
        Task {
            if let skill = await model.createSkill(title: title, professionId: professionId) {
                onCreate(skill)
                dismiss()
            }
            isSaving = false
        }
    }
}
