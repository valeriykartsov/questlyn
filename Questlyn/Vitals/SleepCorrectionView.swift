import SwiftUI
import Domain
import Application

/// «Исправить сон» (8.1, макет 8.17): одна из последних 7 ночей, точный интервал отбоя и подъёма.
/// Исправление заменяет данные Apple Health и ручной ввод той ночи; удалить ночь нельзя.
struct SleepCorrectionView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var wakeDate: LocalDate
    @State private var bedtime = Date.now
    @State private var wake = Date.now
    @State private var isSaving = false

    init(model: AppModel, wakeDate: LocalDate? = nil) {
        self.model = model
        let today = model.today
        let candidate = wakeDate ?? today
        _wakeDate = State(initialValue: SleepRules.correctableWakeDates(today: today).contains(candidate) ? candidate : today)
    }

    private var timeZone: TimeZone { .current }
    private var window: SleepWindow { model.vitalSettings.sleepWindow }
    private var dates: [LocalDate] { SleepRules.correctableWakeDates(today: model.today) }

    /// Ночи последних 7 дней из проекции HP и MP.
    private var nights: [LocalDate: NightSummary] {
        var result: [LocalDate: NightSummary] = [:]
        for entry in model.vitals?.log ?? [] {
            if case let .night(summary) = entry.kind { result[summary.wakeDate] = summary }
        }
        return result
    }

    private var camps: [LocalDate: SleepCamp] {
        Dictionary(SleepCampBuilder.camps(from: model.vitals?.log ?? [], window: window, timeZone: timeZone).map { ($0.wakeDate, $0) },
                   uniquingKeysWith: { _, last in last })
    }

    private var minutes: Int { Int((wake.timeIntervalSince(bedtime) / 60).rounded()) }
    private var isValid: Bool { minutes > 0 && minutes <= 1440 && wake <= .now }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: QSpacing.l) {
                    CapsHeader(title: "Ночь · последние 7 дней")
                    nightPicker
                    legend
                    currentRecord
                    CapsHeader(title: "Точный интервал")
                    intervalPickers
                    resultCard
                    Text("Исправление заменит данные Apple Health за эту ночь и не перезапишется при следующей загрузке. Удалить ночь нельзя — только исправить.")
                        .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                        .padding(QSpacing.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(QColor.track, in: RoundedRectangle(cornerRadius: QRadius.card))
                    Button("Сохранить исправление", action: save)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!isValid || isSaving)
                }
                .padding(QSpacing.screen)
            }
            .paperScreen()
            .navigationTitle("Исправить сон")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
            .onAppear(perform: loadInterval)
            .onChange(of: wakeDate) { _, _ in loadInterval() }
        }
        .tint(QColor.amber)
    }

    // MARK: Выбор ночи

    private var nightPicker: some View {
        HStack(spacing: QSpacing.xs) {
            ForEach(dates, id: \.self) { date in
                let isOn = date == wakeDate
                Button { wakeDate = date } label: {
                    VStack(spacing: QSpacing.xxs) {
                        Text(date.weekday.shortTitle.lowercased()).font(QFont.text(11, weight: .medium))
                        Text("\(date.day)").font(QFont.text(16, weight: .bold)).monospacedDigit()
                        Circle().fill(dotColor(date, selected: isOn)).frame(width: 6, height: 6)
                            .overlay(Circle().strokeBorder(nights[date]?.session == nil ? QColor.inkSecondary : .clear, lineWidth: 1))
                    }
                    .foregroundStyle(isOn ? QColor.sheet : QColor.ink)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(isOn ? QColor.ink : QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
                    .overlay(RoundedRectangle(cornerRadius: QRadius.control).strokeBorder(isOn ? .clear : QColor.lineStrong))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ночь на \(Format.shortDay(date)), \(sourceTitle(nights[date]?.session?.source))")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private func dotColor(_ date: LocalDate, selected: Bool) -> Color {
        switch nights[date]?.session?.source {
        case .health: selected ? QColor.sheet : QColor.mp
        case .manual: selected ? QColor.sheet : QColor.amber
        case .corrected: selected ? QColor.sheet : QColor.forest
        case nil: .clear
        }
    }

    private var legend: some View {
        HStack(spacing: QSpacing.l) {
            legendItem(QColor.mp, "Apple Health")
            legendItem(QColor.amber, "вручную")
            legendItem(QColor.forest, "исправлено")
        }
        .font(QFont.text(11)).foregroundStyle(QColor.inkSecondary)
        .accessibilityHidden(true)
    }

    private func legendItem(_ color: Color, _ title: String) -> some View {
        HStack(spacing: QSpacing.xs) { Circle().fill(color).frame(width: 6, height: 6); Text(title) }
    }

    private func sourceTitle(_ source: SleepSource?) -> String {
        switch source {
        case .health: "Apple Health"
        case .manual: "вручную"
        case .corrected: "исправлено"
        case nil: "нет данных"
        }
    }

    // MARK: Текущая запись

    private var currentRecord: some View {
        let night = nights[wakeDate]
        let camp = camps[wakeDate]
        return VStack(alignment: .leading, spacing: QSpacing.xs) {
            Text("Сейчас · ночь на \(Format.shortDay(wakeDate).lowercased()) · \(sourceTitle(night?.session?.source))")
                .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            if let camp, camp.source != nil {
                Text("\(time(camp.start))–\(time(camp.end)) · \(WeekMapRenderer.duration(camp.minutes))")
                    .font(QFont.text(16, weight: .bold)).monospacedDigit()
            } else {
                Text("Нет данных · ночь нейтральная").font(QFont.text(16, weight: .bold))
            }
            if let replaced = night?.replaced {
                Text("Было: \(WeekMapRenderer.duration(replaced.durationMinutes)), \(sourceTitle(replaced.source))")
                    .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
        }
        .padding(QSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheetCard()
    }

    // MARK: Интервал

    private var intervalPickers: some View {
        let wakeDay = VitalsCalculator.date(wakeDate, LocalTime(hour: 0, minute: 0)!, timeZone: timeZone)
        let earliest = wakeDay.addingTimeInterval(-6 * 3600)
        let latest = min(Date.now, wakeDay.addingTimeInterval(86400 - 60))
        return VStack(spacing: 0) {
            DatePicker("Отбой", selection: $bedtime, in: earliest...latest, displayedComponents: [.date, .hourAndMinute])
                .padding(.horizontal, QSpacing.xl).frame(minHeight: 52)
            Divider().overlay(QColor.line)
            DatePicker("Подъём", selection: $wake, in: earliest...latest, displayedComponents: [.date, .hourAndMinute])
                .padding(.horizontal, QSpacing.xl).frame(minHeight: 52)
        }
        .font(QFont.text(15))
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .sheetCard()
    }

    private var resultCard: some View {
        let deviation = SleepRules.bedtimeDeviation(startedAt: bedtime, wakeDate: wakeDate, window: window, timeZone: timeZone)
        let onTime = SleepRules.regimeFactor(deviationMinutes: deviation) >= 1
        return VStack(alignment: .leading, spacing: QSpacing.s) {
            HStack {
                Text(isValid ? WeekMapRenderer.duration(minutes) : "Проверьте интервал").font(QFont.text(15, weight: .bold))
                Spacer()
                if isValid {
                    Text(onTime ? "режим соблюдён" : "отбой позже режима").font(QFont.text(13, weight: .semibold))
                        .foregroundStyle(onTime ? QColor.forest : QColor.amberDeep)
                }
            }
            Text(isValid
                 ? "HP и MP пересчитаются с этой ночи — так же, как для ночи из Apple Health. XP, уровни и ранг сон не меняет."
                 : "Подъём должен быть позже отбоя и не позже текущего времени.")
                .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
        }
        .padding(QSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheetCard()
    }

    // MARK: Действия

    /// Начальный интервал — текущая запись ночи или окно сна из настроек.
    private func loadInterval() {
        if let camp = camps[wakeDate], camp.source != nil {
            bedtime = camp.start
            wake = min(camp.end, .now)
        } else {
            let startDay = window.start > window.end ? wakeDate.adding(days: -1) : wakeDate
            bedtime = VitalsCalculator.date(startDay, window.start, timeZone: timeZone)
            wake = min(VitalsCalculator.date(wakeDate, window.end, timeZone: timeZone), .now)
        }
    }

    private func save() {
        isSaving = true
        Task {
            if await model.correctSleep(wakeDate: wakeDate, startedAt: bedtime, endedAt: wake) { dismiss() }
            isSaving = false
        }
    }

    private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}
