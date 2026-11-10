import SwiftUI
import Domain
import Application

/// HP и MP героя (макеты TodayV2 и HeroV2). Только состояние: XP и ранг не меняются.
struct VitalsCard: View {
    let vitals: VitalsState
    /// Подписи «STR + END · сон» — на экране «Герой».
    var showsSources = false
    var askSleep: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: QSpacing.l) {
            HStack(alignment: .top, spacing: QSpacing.xl) {
                meter("HP", title: "здоровье", value: vitals.hp, max: vitals.maxHP, color: QColor.hp, source: "STR + END · сон")
                meter("MP", title: "мана", value: vitals.mp, max: vitals.maxMP, color: QColor.mp, source: "INT + MNT + CHR · сон")
            }
            if let status = statusText {
                Text(status)
                    .font(QFont.text(12))
                    .foregroundStyle(QColor.amberDeep)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let askSleep {
                Button(action: askSleep) {
                    Label("Как спали? Внести сон", systemImage: "moon.zzz")
                        .font(QFont.text(13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(QColor.amberDeep)
            }
        }
        .padding(QSpacing.xl)
        .sheetCard()
    }

    private var statusText: String? {
        switch (vitals.isWounded, vitals.isExhausted) {
        case (true, true): "Ранен и истощён. Квесты засчитываются как обычно — хорошая ночь вернёт силы."
        case (true, false): "Ранен: HP ниже 30%. Прогресс не страдает — сон восстановит здоровье."
        case (false, true): "Истощён: мана на нуле. Квесты засчитываются полностью, сон вернёт ману."
        case (false, false): nil
        }
    }

    private func meter(_ code: String, title: String, value: Double, max: Double, color: Color, source: String) -> some View {
        VStack(alignment: .leading, spacing: QSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: QSpacing.xs) {
                Text(showsSources ? "\(code) · \(title)" : code)
                    .font(QFont.text(12, weight: .bold))
                    .foregroundStyle(color)
                Spacer(minLength: 0)
                Text("\(Vitals.whole(value)) / \(Vitals.whole(max))")
                    .font(QFont.text(13, weight: .semibold))
                    .monospacedDigit()
            }
            ProgressBar(fraction: max > 0 ? value / max : 0, color: color)
            if showsSources {
                Text(source).font(QFont.text(11)).foregroundStyle(QColor.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(Vitals.whole(value)) из \(Vitals.whole(max))")
    }
}

enum Vitals {
    /// На экране — целые; считаются с дробной частью (08, 3.1).
    static func whole(_ value: Double) -> Int { Int(value.rounded()) }

    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

    static func factor(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "ru_RU"))) }
}

/// «Утро» (макеты 3.2 и 3.3): итог ночи из Apple Health или вопрос «Как спали?».
struct MorningView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var duration: ManualSleepDuration = .h7to8
    @State private var bedtime: ManualBedtime = .onTime
    @State private var isSaving = false

    private var night: NightSummary? { model.vitals?.lastNight }
    private var asksManual: Bool { !(model.overview?.hasSleepToday ?? false) || night?.session?.source != .health }

    var body: some View {
        VStack(alignment: .leading, spacing: QSpacing.screen) {
            HStack {
                Text(Format.longDay(.now)).font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                Spacer()
                if asksManual { Button("Позже") { dismiss() }.font(QFont.text(15, weight: .medium)).foregroundStyle(QColor.amberDeep) }
            }
            if asksManual { manual } else { summary }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, QSpacing.screen)
        .paperScreen()
    }

    // MARK: Ручной ввод

    private var manual: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.screen) {
                VStack(alignment: .leading, spacing: QSpacing.s) {
                    Text("Как спали?").font(QFont.title(28))
                    Text(model.isHealthConnected
                         ? "В Apple Health нет данных о сне. Отметьте одним касанием — так герой восстановит HP и MP."
                         : "Отметьте одним касанием — так герой восстановит HP и MP.")
                        .font(QFont.text(15)).foregroundStyle(QColor.inkSecondary)
                }
                chips("Сколько", ManualSleepDuration.allCases, selected: duration, title: \.title) { duration = $0 }
                chips("Когда легли", ManualBedtime.allCases, selected: bedtime, title: \.title) { bedtime = $0 }
                if let night {
                    let q = SleepRules.durationFactor(minutes: duration.minutes) * SleepRules.regimeFactor(deviationMinutes: bedtime.deviationMinutes)
                    preview(night: night, quality: q)
                }
                Text("Если не ответить, ночь считается нейтральной (50%): нет данных — не значит плохой сон.")
                    .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                Button("Сохранить") {
                    isSaving = true
                    Task {
                        if await model.recordSleep(duration: duration, bedtime: bedtime) { dismiss() }
                        isSaving = false
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving)
            }
            .padding(.bottom, QSpacing.screen)
        }
    }

    private func chips<Option: Hashable>(_ caption: String, _ options: [Option], selected: Option, title: KeyPath<Option, String>,
                                         pick: @escaping (Option) -> Void) -> some View {
        VStack(alignment: .leading, spacing: QSpacing.s) {
            CapsHeader(title: caption)
            FlowChips(options: options, selected: selected, title: title, pick: pick)
        }
    }

    /// Что даст ночь: до → после, как в макете.
    private func preview(night: NightSummary, quality: Double) -> some View {
        let hpAfter = min(night.maxHP, night.hpBefore + SleepRules.hpRestoreShare * night.maxHP * quality)
        let mpAfter = min(night.maxMP, night.mpBefore + night.maxMP * quality)
        return VStack(spacing: QSpacing.m) {
            changeRow("HP", before: night.hpBefore, after: hpAfter, max: night.maxHP, color: QColor.hp,
                      note: "Ночь \(Vitals.percent(quality)) · +\(Vitals.whole(hpAfter - night.hpBefore))")
            changeRow("MP", before: night.mpBefore, after: mpAfter, max: night.maxMP, color: QColor.mp,
                      note: mpAfter >= night.maxMP ? "Полностью" : "+\(Vitals.whole(mpAfter - night.mpBefore))")
        }
        .padding(QSpacing.xl)
        .sheetCard()
    }

    // MARK: Итог из Apple Health

    private var summary: some View {
        VStack(alignment: .leading, spacing: QSpacing.screen) {
            HStack(spacing: QSpacing.s) {
                Image(systemName: "heart.fill").foregroundStyle(QColor.hp)
                Text("Apple Health").font(QFont.text(13, weight: .semibold)).foregroundStyle(QColor.inkSecondary)
            }
            Text("Доброе утро, герой").font(QFont.title(28))
            if let night, let session = night.session {
                VStack(spacing: QSpacing.m) {
                    InfoRow(label: "Сон", value: Format.minutes(session.durationMinutes),
                            note: "длительность · \(Vitals.factor(night.durationFactor ?? 1))")
                    if let start = session.startedAt {
                        InfoRow(label: "Отбой", value: start.formatted(date: .omitted, time: .shortened),
                                note: deviationNote(session.bedtimeDeviationMinutes, factor: night.regimeFactor ?? 1))
                    }
                    InfoRow(label: "Качество", value: Vitals.percent(night.quality),
                            note: "режим \(model.vitalSettings.sleepWindow.start)–\(model.vitalSettings.sleepWindow.end)")
                }
                .padding(QSpacing.xl)
                .sheetCard()
                VStack(spacing: QSpacing.m) {
                    changeRow("HP", before: night.hpBefore, after: night.hpAfter, max: night.maxHP, color: QColor.hp,
                              note: "+\(Vitals.whole(night.hpAfter - night.hpBefore)) · ночь давала до +\(Vitals.whole(SleepRules.hpRestoreShare * night.maxHP * night.quality))")
                    changeRow("MP", before: night.mpBefore, after: night.mpAfter, max: night.maxMP, color: QColor.mp,
                              note: night.mpAfter >= night.maxMP ? "Полностью" : "+\(Vitals.whole(night.mpAfter - night.mpBefore))")
                }
                .padding(QSpacing.xl)
                .sheetCard()
                if (night.regimeFactor ?? 1) < 1 {
                    Text("Лечь в \(model.vitalSettings.sleepWindow.start) — и завтра восстановление будет полным.")
                        .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                }
            }
            Spacer(minLength: 0)
            Button("В путь") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.bottom, QSpacing.l)
        }
    }

    private func deviationNote(_ minutes: Int?, factor: Double) -> String {
        guard let minutes, minutes > 0 else { return "по режиму · 1,0" }
        return "±\(minutes) мин · \(Vitals.factor(factor))"
    }

    private func changeRow(_ code: String, before: Double, after: Double, max: Double, color: Color, note: String) -> some View {
        VStack(alignment: .leading, spacing: QSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(code).font(QFont.text(12, weight: .bold)).foregroundStyle(color)
                Spacer()
                Text("\(Vitals.whole(before)) → \(Vitals.whole(after)) / \(Vitals.whole(max))")
                    .font(QFont.text(15, weight: .bold)).monospacedDigit()
            }
            ProgressBar(fraction: max > 0 ? after / max : 0, color: color)
            Text(note).font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
        }
    }
}

/// Кнопки-капсулы, переносятся на новую строку.
struct FlowChips<Option: Hashable>: View {
    let options: [Option]
    let selected: Option
    let title: KeyPath<Option, String>
    let pick: (Option) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: QSpacing.m)], alignment: .leading, spacing: QSpacing.m) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selected
                Button { pick(option) } label: {
                    Text(option[keyPath: title])
                        .font(QFont.text(14, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(isOn ? QColor.sheet : QColor.ink)
                        .background(isOn ? QColor.ink : QColor.sheet, in: Capsule())
                        .overlay(Capsule().strokeBorder(isOn ? QColor.ink : QColor.lineStrong))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// «Настройки → Здоровье героя» (макет 5.5): окно сна, норма шагов, Apple Health.
struct HealthSettingsView: View {
    let model: AppModel
    @State private var settings: VitalSettings
    @State private var isConnecting = false

    init(model: AppModel) {
        self.model = model
        _settings = State(initialValue: model.vitalSettings)
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Отбой", selection: time(\.sleepWindow.start), displayedComponents: .hourAndMinute)
                DatePicker("Подъём", selection: time(\.sleepWindow.end), displayedComponents: .hourAndMinute)
            } header: {
                Text("Режим сна")
            } footer: {
                Text("Отбой позже начала окна на 30+ минут снижает восстановление. Без данных о сне ночь считается нейтральной в конце окна.")
            }
            .listRowBackground(QColor.sheet)

            Section {
                Stepper(value: $settings.stepGoal, in: VitalSettings.stepGoalRange, step: VitalSettings.stepGoalStep) {
                    LabeledContent("Норма шагов в день", value: settings.stepGoal.formatted(.number.locale(Locale(identifier: "ru_RU"))))
                }
            } header: {
                Text("Активность")
            } footer: {
                Text("Меньше нормы за день — сидячий день, −5% HP в 23:59. Нет данных о шагах — нет урона.")
            }
            .listRowBackground(QColor.sheet)

            Section {
                if model.isHealthConnected {
                    Label("Подключено: сон и шаги", systemImage: "checkmark.circle.fill").foregroundStyle(QColor.forest)
                } else {
                    Button {
                        isConnecting = true
                        Task {
                            await model.connectHealth()
                            isConnecting = false
                        }
                    } label: {
                        Label("Подключить Apple Health", systemImage: "heart.text.square")
                    }
                    .disabled(isConnecting || !model.isHealthAvailable)
                }
            } header: {
                Text("Apple Health · только чтение")
            } footer: {
                Text("Sleep Analysis — восстановление HP и MP, шаги — норма активности. Данные не покидают устройство. Доступ можно изменить в приложении «Здоровье».")
            }
            .listRowBackground(QColor.sheet)
        }
        .paperScreen()
        .navigationTitle("Здоровье героя")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings) { _, new in
            Task { await model.updateVitalSettings(new) }
        }
    }

    /// Привязка LocalTime к DatePicker.
    private func time(_ path: WritableKeyPath<VitalSettings, LocalTime>) -> Binding<Date> {
        Binding {
            VitalsCalculator.date(LocalDate(.now, timeZone: .current), settings[keyPath: path], timeZone: .current)
        } set: { date in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            if let value = LocalTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0) { settings[keyPath: path] = value }
        }
    }
}
