import SwiftUI
import Domain
import Application

/// Смена профессий и названия класса (02): уровни атрибутов сохраняются, навыки убранной профессии — неактивны.
struct ProfessionEditorView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var setup: ProfessionSetup
    @State private var isSaving = false

    init(model: AppModel) {
        self.model = model
        _setup = State(initialValue: ProfessionSetup(
            choices: model.activeProfessions.map { ProfessionChoice(catalogItemId: $0.catalogItemId, title: $0.title, attributes: $0.attributes) },
            classTitle: model.hero?.classTitle ?? ""
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: QSpacing.l) {
                    CapsHeader(title: "Профессии")
                    ProfessionPickerStep(setup: setup)
                    CapsHeader(title: "Атрибуты профессий")
                    ProfessionAttributesStep(setup: setup)
                    CapsHeader(title: "Класс")
                    ClassStep(setup: setup, showsBonus: false)
                    Text("Уровни атрибутов сохранятся. Навыки убранной профессии станут неактивными и вернутся, если выбрать её снова.")
                        .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                }
                .padding(QSpacing.screen)
            }
            .paperScreen()
            .navigationTitle("Профессии и класс")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        isSaving = true
                        Task {
                            let title = setup.classTitle.trimmingCharacters(in: .whitespaces).isEmpty ? setup.defaultClassTitle : setup.classTitle
                            if await model.updateProfessions(setup.choices, classTitle: title) { dismiss() }
                            isSaving = false
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(setup.choices.isEmpty || isSaving)
                }
            }
        }
        .tint(QColor.amber)
    }
}
