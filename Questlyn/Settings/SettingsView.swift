import SwiftUI
import Domain
import Application

/// «Настройки» (макет Settings): внешность и здоровье героя, сброс данных; тема и бэкап — этап 7.
struct SettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingReset = false
    @State private var confirmation = ""

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        AppearanceEditorView(model: model)
                    } label: {
                        LabeledContent {
                            Text(model.hero?.appearance.outfit.title ?? "")
                        } label: {
                            Label("Внешность и образ", systemImage: "person.crop.square")
                        }
                    }
                    NavigationLink {
                        HealthSettingsView(model: model)
                    } label: {
                        LabeledContent {
                            Text("\(model.vitalSettings.sleepWindow.start)–\(model.vitalSettings.sleepWindow.end)")
                        } label: {
                            Label("Здоровье героя", systemImage: "heart")
                        }
                    }
                } header: {
                    Text("Герой")
                } footer: {
                    Text("Внешность не влияет на прогресс. Режим сна и норма шагов задают восстановление HP и MP.")
                }
                .listRowBackground(QColor.sheet)

                Section {
                    Button(role: .destructive) {
                        confirmation = ""
                        isConfirmingReset = true
                    } label: {
                        Label("Начать путь заново", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("Данные")
                } footer: {
                    Text("Удаляет героя, профессии, навыки, квесты, привычки, Epic и весь прогресс. Отменить нельзя: резервного копирования пока нет.")
                }
                .listRowBackground(QColor.sheet)

                Section("О приложении") {
                    LabeledContent("Questlyn", value: version)
                    LabeledContent("Правила", value: "Rule Set v\(DomainInfo.ruleVersion)")
                }
                .listRowBackground(QColor.sheet)
            }
            .paperScreen()
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .alert("Сбросить все данные?", isPresented: $isConfirmingReset) {
                TextField(ResetService.confirmationWord, text: $confirmation)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Отмена", role: .cancel) {}
                Button("Сбросить", role: .destructive) {
                    let word = confirmation
                    Task {
                        if await model.resetEverything(confirmation: word) { dismiss() }
                    }
                }
            } message: {
                Text("Герой и весь прогресс будут удалены навсегда. Введите «\(ResetService.confirmationWord)», чтобы подтвердить.")
            }
        }
        .tint(QColor.amber)
    }
}

enum DomainInfo {
    static var ruleVersion: String { RuleVersion.current.rawValue }
}
