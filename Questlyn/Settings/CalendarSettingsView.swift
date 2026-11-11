import SwiftUI
import Domain
import Application

/// «Настройки › Календари» (макет 8.15): показ, привязка к профессии или навыку, отправка квестов.
struct CalendarSettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            if !model.isCalendarAuthorized {
                Section {
                    Button("Подключить Apple Calendar") { Task { await model.connectCalendar() } }
                } footer: {
                    Text("Нужен доступ к календарю: события читаются, а квесты записываются в отдельный календарь «Questlyn».")
                }
                .listRowBackground(QColor.sheet)
            }

            Section {
                ForEach(model.deviceCalendars) { calendar in
                    calendarRow(calendar)
                }
            } header: {
                Text("Показывать и привязать")
            } footer: {
                Text("Привязка задаёт цвет и подпись событий в календаре. XP за события не начисляется — событие ≠ выполненное действие.")
            }
            .listRowBackground(QColor.sheet)

            Section {
                Toggle(isOn: Binding(get: { model.calendarPreferences.sendQuests },
                                     set: { on in model.updateCalendarPreferences { $0.sendQuests = on } })) {
                    VStack(alignment: .leading, spacing: QSpacing.xxs) {
                        Text("Отправлять квесты с датой").font(QFont.text(15))
                        Text("в календарь «Questlyn» · создаётся сам").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                    }
                }
                .tint(QColor.forest)
                .disabled(!model.isCalendarAuthorized)
            } header: {
                Text("Квесты в Apple Calendar")
            } footer: {
                Text("Квест с датой — событие на весь день, с датой и временем — на 30 минут. Изменение и удаление квеста меняют и событие, выполненный отмечается «✓». Если выключить — события квестов удалятся.")
            }
            .listRowBackground(QColor.sheet)
        }
        .paperScreen()
        .navigationTitle("Календари")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.loadAgenda(from: model.today, through: model.today) }
    }

    private func calendarRow(_ calendar: DeviceCalendar) -> some View {
        let isShown = !model.calendarPreferences.hidden.contains(calendar.id)
        let link = model.calendarPreferences.links[calendar.id]
        return VStack(alignment: .leading, spacing: QSpacing.s) {
            Toggle(isOn: Binding(get: { isShown }, set: { on in
                model.updateCalendarPreferences { if on { $0.hidden.remove(calendar.id) } else { $0.hidden.insert(calendar.id) } }
            })) {
                HStack(spacing: QSpacing.m) {
                    Circle().fill(Color(hex: calendar.color)).frame(width: 12, height: 12)
                    Text(calendar.title).font(QFont.text(15))
                }
            }
            .tint(QColor.forest)
            if isShown {
                Picker("Привязка", selection: Binding(get: { linkTag(link) }, set: { tag in
                    model.updateCalendarPreferences { $0.links[calendar.id] = parse(tag) }
                })) {
                    Text("без привязки").tag("none")
                    ForEach(model.activeProfessions) { profession in
                        Text(profession.title).tag("p:\(profession.id)")
                        ForEach(model.skills.filter { $0.professionId == profession.id }) { skill in
                            Text("\(profession.title) · «\(skill.title)»").tag("s:\(skill.id)")
                        }
                    }
                }
                .font(QFont.text(13))
            }
        }
        .padding(.vertical, QSpacing.xxs)
    }

    private func linkTag(_ link: CalendarLink?) -> String {
        if let skill = link?.skillId { return "s:\(skill)" }
        if let profession = link?.professionId { return "p:\(profession)" }
        return "none"
    }

    private func parse(_ tag: String) -> CalendarLink? {
        if tag.hasPrefix("s:"), let id = UUID(uuidString: String(tag.dropFirst(2))) { return CalendarLink(skillId: id) }
        if tag.hasPrefix("p:"), let id = UUID(uuidString: String(tag.dropFirst(2))) { return CalendarLink(professionId: id) }
        return nil
    }
}
