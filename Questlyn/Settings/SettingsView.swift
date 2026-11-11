import SwiftUI
import Domain
import Application

/// «Настройки» (макет Settings): внешность и здоровье героя, резервная копия, экспорт, тема, сброс данных.
struct SettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingReset = false
    @State private var confirmation = ""
    @AppStorage("appTheme") private var theme: AppTheme = .system
    @State private var exportURL: URL?
    @State private var isExporting = false

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

                Section("Календарь") {
                    NavigationLink {
                        CalendarSettingsView(model: model)
                    } label: {
                        LabeledContent {
                            Text(model.calendarPreferences.sendQuests ? "квесты → «Questlyn»" : "")
                        } label: {
                            Label("Календари", systemImage: "calendar")
                        }
                    }
                }
                .listRowBackground(QColor.sheet)

                Section("Оформление") {
                    Picker("Тема", selection: $theme) {
                        ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                    }
                }
                .listRowBackground(QColor.sheet)

                Section {
                    LabeledContent("Где хранятся", value: model.backupLocation?.title ?? "—")
                    LabeledContent("Последняя копия", value: model.backupFiles.first.map {
                        $0.date.formatted(.dateTime.day().month(.wide).hour().minute().locale(Locale(identifier: "ru_RU")))
                    } ?? "ещё нет")
                    Button {
                        Task { await model.backupNow() }
                    } label: {
                        Label(model.isBackingUp ? "Сохраняем копию…" : "Сделать копию сейчас", systemImage: "externaldrive.badge.icloud")
                    }
                    .disabled(model.isBackingUp)
                    NavigationLink {
                        BackupListView(model: model)
                    } label: {
                        Label("Восстановить из копии", systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(model.backupFiles.isEmpty)
                } header: {
                    Text("Резервная копия")
                } footer: {
                    Text("Копия всей базы сохраняется автоматически раз в сутки, хранятся семь последних — в приложении «Файлы» на iPhone. Чтобы копия пережила потерю телефона, сохраните её в iCloud Drive: «Восстановить из копии» → кнопка «Поделиться» у копии.")
                }
                .listRowBackground(QColor.sheet)

                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Поделиться файлом экспорта", systemImage: "square.and.arrow.up") }
                    } else {
                        Button {
                            isExporting = true
                            Task {
                                exportURL = await model.exportFile()
                                isExporting = false
                            }
                        } label: {
                            Label(isExporting ? "Готовим файл…" : "Экспорт данных (JSON)", systemImage: "doc.text")
                        }
                        .disabled(isExporting)
                    }
                } header: {
                    Text("Экспорт")
                } footer: {
                    Text("Все факты — квесты, привычки, активности, сон, настроение, отметки здоровья — и начисления в одном файле JSON. Уровни, HP и MP пересчитываются из них.")
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
                    NavigationLink("Компоненты оформления") { ComponentGallery() }
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
        .task { await model.refreshBackups(createIfNeeded: false) }
    }
}

/// Список копий и восстановление с подтверждением (7.1).
struct BackupListView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: BackupFile?

    var body: some View {
        List {
            Section {
                ForEach(model.backupFiles) { file in
                    HStack {
                        Button { selected = file } label: {
                            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                                Text(file.date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(Locale(identifier: "ru_RU"))))
                                    .font(QFont.text(15))
                                Text(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file))
                                    .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Восстановить эту копию")
                        ShareLink(item: file.url) {
                            Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(QColor.amberDeep)
                        .accessibilityLabel("Сохранить копию в iCloud Drive или отправить")
                    }
                    .foregroundStyle(QColor.ink)
                    .listRowBackground(QColor.sheet)
                }
            } footer: {
                Text("Нажмите на копию, чтобы восстановить её. Кнопка «Поделиться» → «Сохранить в Файлы» → iCloud Drive сохранит копию вне телефона.")
            }
        }
        .paperScreen()
        .navigationTitle("Копии")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Восстановить эту копию?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            Button("Отмена", role: .cancel) {}
            Button("Восстановить", role: .destructive) {
                guard let file = selected else { return }
                Task { if await model.restore(file) { dismiss() } }
            }
        } message: {
            Text("Все текущие данные заменятся данными копии. Перед этим лучше сделать копию сейчас.")
        }
    }
}

enum DomainInfo {
    static var ruleVersion: String { RuleVersion.current.rawValue }
}
