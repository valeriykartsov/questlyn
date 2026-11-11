import SwiftUI
import Domain

/// «Ритм дня» (9.3, макет 9.3): рабочее время — «Фарм», окно сна — «Привал», остальное — «Приключение».
struct DayRhythmSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                DayRhythmBar(model: model, day: model.today).frame(height: 26)
                HStack(spacing: QSpacing.l) {
                    legend(MovementMode.farm)
                    legend(MovementMode.rest)
                    legend(MovementMode.adventure)
                }
                .font(QFont.text(12))
            } header: {
                Text("Сутки героя")
            }
            .listRowBackground(QColor.sheet)

            Section {
                Toggle("Учитывать рабочее время", isOn: $model.workSchedule.isEnabled.animation())
                    .tint(QColor.forest)
                if model.workSchedule.isEnabled {
                    DatePicker("С", selection: time(\.start), displayedComponents: .hourAndMinute)
                    DatePicker("До", selection: time(\.end), displayedComponents: .hourAndMinute)
                    VStack(alignment: .leading, spacing: QSpacing.s) {
                        Text("Дни").font(QFont.text(15))
                        HStack(spacing: QSpacing.xs) {
                            ForEach(Weekday.allCases, id: \.self) { day in
                                let isOn = model.workSchedule.weekdays.contains(day)
                                Button(day.shortTitle) {
                                    if isOn { model.workSchedule.weekdays.remove(day) } else { model.workSchedule.weekdays.insert(day) }
                                }
                                .font(QFont.text(13, weight: .semibold))
                                .foregroundStyle(isOn ? QColor.sheet : QColor.ink)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(isOn ? QColor.ink : Color.clear, in: RoundedRectangle(cornerRadius: QRadius.small))
                                .overlay(RoundedRectangle(cornerRadius: QRadius.small).strokeBorder(isOn ? .clear : QColor.lineStrong))
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(isOn ? .isSelected : [])
                            }
                        }
                    }
                    .padding(.vertical, QSpacing.xs)
                }
            } header: {
                Text("Фарм · рабочее время")
            } footer: {
                Text("Только отображение: вид движения героя на картах, цвет дороги и фон «Пути». XP, HP и MP не меняются. «Привал» — окно сна из «Здоровья героя».")
            }
            .listRowBackground(QColor.sheet)
        }
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .tint(QColor.amber)
        .paperScreen()
        .navigationTitle("Ритм дня")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func legend(_ mode: MovementMode) -> some View {
        HStack(spacing: QSpacing.xs) {
            RoundedRectangle(cornerRadius: 3).fill(DayRhythmBar.color(mode)).frame(width: 10, height: 10)
            Text(mode.title)
        }
    }

    private func time(_ path: WritableKeyPath<WorkSchedule, LocalTime>) -> Binding<Date> {
        Binding {
            VitalsCalculator.date(model.today, model.workSchedule[keyPath: path], timeZone: .current)
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            if let value = LocalTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0) { model.workSchedule[keyPath: path] = value }
        }
    }
}

/// Полоса суток: зоны «Привал», «Фарм», «Приключение» по часам.
struct DayRhythmBar: View {
    let model: AppModel
    let day: LocalDate

    static func color(_ mode: MovementMode) -> Color {
        switch mode {
        case .farm: QColor.warmFill
        case .rest: Color(hex: 0x1E2742)
        case .adventure: Color(light: 0xDCEBE2, dark: 0x1F3A30)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(segments, id: \.start) { segment in
                    Self.color(segment.mode).frame(width: proxy.size.width * CGFloat(segment.length) / 96)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: QRadius.small))
        .overlay(RoundedRectangle(cornerRadius: QRadius.small).strokeBorder(QColor.line))
        .accessibilityElement()
        .accessibilityLabel(segments.map { "\($0.mode.title) \($0.start / 4):00" }.joined(separator: ", "))
    }

    /// Сутки по 15 минут, соседние одинаковые — один отрезок.
    private var segments: [(start: Int, length: Int, mode: MovementMode)] {
        var result: [(start: Int, length: Int, mode: MovementMode)] = []
        for quarter in 0..<96 {
            let moment = VitalsCalculator.date(day, LocalTime(hour: quarter / 4, minute: quarter % 4 * 15)!, timeZone: .current)
            let mode = model.movementMode(at: moment)
            if let last = result.last, last.mode == mode { result[result.count - 1].length += 1 }
            else { result.append((quarter, 1, mode)) }
        }
        return result
    }
}
