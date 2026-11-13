import SwiftUI
import UIKit
import Domain

/// «Настройки › Уведомления» (макет 12D.1): единый раздел для всех напоминаний.
struct NotificationSettingsView: View {
    let model: AppModel
    @Environment(\.openURL) private var openURL

    private var settings: NotificationSettings { model.notificationSettings }

    var body: some View {
        Form {
            Section {
                switch model.notificationsAllowed {
                case true:
                    Label("Уведомления разрешены в настройках iPhone", systemImage: "checkmark.circle")
                        .foregroundStyle(QColor.forest)
                case false:
                    VStack(alignment: .leading, spacing: QSpacing.s) {
                        Label("Уведомления запрещены в настройках iPhone", systemImage: "bell.slash")
                            .foregroundStyle(QColor.hp)
                        Button("Открыть настройки iPhone") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                default:
                    Text("iPhone спросит разрешение, когда вы включите первое уведомление.")
                        .foregroundStyle(QColor.inkSecondary)
                }
            }
            .font(QFont.text(14))
            .listRowBackground(QColor.sheet)

            Section("Квесты") {
                toggle("Квест со временем начала", \.quests)
                if settings.quests {
                    Picker("Напомнить", selection: binding(\.questLeadMinutes)) {
                        ForEach(NotificationSettings.questLeadOptions, id: \.self) { minutes in
                            Text(minutes == 0 ? "в момент начала" : "за \(minutes) мин").tag(minutes)
                        }
                    }
                }
            }
            .listRowBackground(QColor.sheet)

            Section {
                toggle("В своё время", \.habitsOwnTime, note: "у ежедневных, где задано время")
                toggle("Напоминание о привычках", \.habitsReminder, note: "если остались неотмеченные")
                if settings.habitsReminder { timePicker("Время", \.habitsReminderTime) }
            } header: {
                Text("Ежедневные квесты")
            }
            .listRowBackground(QColor.sheet)

            Section("Сон") {
                toggle("Внести сон утром", \.sleep, note: "через \(NotificationSettings.sleepDelayMinutes) мин после подъёма (\(model.vitalSettings.sleepWindow.end)), если ночи нет")
            }
            .listRowBackground(QColor.sheet)

            Section {
                toggle("Итог дня вечером", \.mood, note: "если «Итога дня» ещё нет")
                if settings.mood { timePicker("Время", \.moodTime) }
            } header: {
                Text("Настроение")
            } footer: {
                Text("Напоминания ставятся на 7 дней вперёд и обновляются при каждом открытии приложения.")
            }
            .listRowBackground(QColor.sheet)
        }
        .scrollContentBackground(.hidden)
        .paperScreen()
        .navigationTitle("Уведомления")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refreshNotificationStatus() }
    }

    private func binding<Value>(_ path: WritableKeyPath<NotificationSettings, Value>) -> Binding<Value> {
        Binding { model.notificationSettings[keyPath: path] } set: { value in
            Task { await model.changeNotifications { $0[keyPath: path] = value } }
        }
    }

    private func toggle(_ title: String, _ path: WritableKeyPath<NotificationSettings, Bool>, note: String? = nil) -> some View {
        Toggle(isOn: binding(path)) {
            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                Text(title).font(QFont.text(15))
                if let note { Text(note).font(QFont.text(12)).foregroundStyle(QColor.inkSecondary) }
            }
        }
        .tint(QColor.forest)
    }

    private func timePicker(_ title: String, _ path: WritableKeyPath<NotificationSettings, LocalTime>) -> some View {
        DatePicker(title, selection: Binding {
            Calendar.current.date(bySettingHour: model.notificationSettings[keyPath: path].hour,
                                  minute: model.notificationSettings[keyPath: path].minute, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            guard let time = LocalTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0) else { return }
            Task { await model.changeNotifications { $0[keyPath: path] = time } }
        }, displayedComponents: .hourAndMinute)
        .environment(\.locale, Locale(identifier: "ru_RU"))
    }
}
