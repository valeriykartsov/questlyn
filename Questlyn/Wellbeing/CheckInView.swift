import SwiftUI
import Domain
import Application

/// «Как вы?» (макет 3.4): настроение и блок «Здоровье». Настроение не влияет на HP и прогресс.
struct CheckInView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CheckInDraft()
    @State private var isSaving = false

    private var vitals: VitalsState? { model.vitals }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: QSpacing.screen) {
                    VStack(alignment: .leading, spacing: QSpacing.xs) {
                        Text("Сейчас, \(Date.now.formatted(date: .omitted, time: .shortened))")
                            .font(QFont.text(13)).foregroundStyle(QColor.inkSecondary)
                        Text("Как вы сейчас?").font(QFont.title(26))
                    }
                    moodPicker
                    moodExtras
                    healthBlock
                    benefitBlock
                    if !model.todayHarms.isEmpty || !model.todayBenefits.isEmpty { todayList }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, QSpacing.screen)
                .onChange(of: draft.customBenefitTitle) { _, title in
                    // Ввод названия своего действия сразу ставит одну отметку.
                    if !title.trimmingCharacters(in: .whitespaces).isEmpty, (draft.benefits[.custom] ?? 0) == 0 { draft.benefits[.custom] = 1 }
                }
            }
            .paperScreen()
            .keyboardDismissal()
            .safeAreaInset(edge: .bottom) {
                Button("Отметить", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(draft.isEmpty || isSaving)
                    .padding(.horizontal, 20)
                    .padding(.vertical, QSpacing.m)
                    .background(QColor.paper)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(QColor.amber)
    }

    // MARK: Настроение

    private var moodPicker: some View {
        HStack(spacing: QSpacing.m) {
            ForEach(Mood.allCases, id: \.self) { mood in
                let isOn = draft.mood == mood
                Button {
                    draft.mood = isOn ? nil : mood
                } label: {
                    VStack(spacing: QSpacing.xs) {
                        Image(systemName: WeatherStyle.symbol(Weather.from(mood, on: model.today)))
                            .font(.system(size: 24))
                        Text(mood.title).font(QFont.text(15, weight: .semibold))
                        Text(Weather.from(mood, on: model.today).title.lowercased())
                            .font(QFont.text(12)).foregroundStyle(isOn ? QColor.sheet.opacity(0.8) : QColor.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92)
                    .foregroundStyle(isOn ? QColor.sheet : QColor.ink)
                    .background(isOn ? QColor.ink : QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.card))
                    .overlay(RoundedRectangle(cornerRadius: QRadius.card).strokeBorder(isOn ? QColor.ink : QColor.line))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mood.title) настроение")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private var moodExtras: some View {
        if draft.mood != nil {
            VStack(alignment: .leading, spacing: QSpacing.m) {
                TextField("Заметка", text: $draft.note, prompt: Text("Заметка · необязательно").foregroundStyle(QColor.placeholder), axis: .vertical)
                    .font(QFont.text(15))
                    .padding(QSpacing.l)
                    .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
                    .overlay(RoundedRectangle(cornerRadius: QRadius.control).strokeBorder(QColor.line))
                Toggle(isOn: $draft.isDaySummary) {
                    VStack(alignment: .leading, spacing: QSpacing.xxs) {
                        Text("Итог дня").font(QFont.text(15))
                        Text("Один на день: новый заменяет прежний").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                    }
                }
                .tint(QColor.forest)
            }
        }
    }

    // MARK: Здоровье

    private var healthBlock: some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                CapsHeader(title: "Здоровье сегодня")
                Spacer()
                Text("настроение на HP не влияет").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
            VStack(spacing: 0) {
                counter(.smoking, note: "−3% HP за каждую отметку")
                Divider().overlay(QColor.line)
                alcoholRow
                Divider().overlay(QColor.line)
                counter(.fastFood, note: "−5% HP")
                Divider().overlay(QColor.line)
                counter(.lateCaffeine, note: "−5% HP")
                ForEach(model.overview?.customHarmHabits ?? []) { habit in
                    Divider().overlay(QColor.line)
                    customCounter(habit)
                }
            }
            .padding(.horizontal, QSpacing.xl)
            .sheetCard()
            summary
        }
    }

    // MARK: Полезное (08, раздел 2.3)

    private var benefitBlock: some View {
        VStack(alignment: .leading, spacing: QSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                CapsHeader(title: "Полезное")
                Spacer()
                Text("+3% HP, до +10% в день").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(BenefitKind.allCases.filter { $0 != .custom }.enumerated()), id: \.element) { index, kind in
                    if index > 0 { Divider().overlay(QColor.line) }
                    benefitRow(title: kind.title, kind: kind)
                }
                Divider().overlay(QColor.line)
                HStack(spacing: QSpacing.l) {
                    TextField("Своё действие", text: $draft.customBenefitTitle,
                              prompt: Text("Своё действие").foregroundStyle(QColor.placeholder))
                        .font(QFont.text(15))
                    Stepper(value: Binding(get: { draft.benefits[.custom] ?? 0 }, set: { draft.benefits[.custom] = $0 }),
                            in: 0...WellbeingService.maxCount) {
                        Text("\(draft.benefits[.custom] ?? 0)").font(QFont.text(15, weight: .semibold)).monospacedDigit()
                    }
                    .fixedSize()
                    .accessibilityLabel("Своё действие")
                }
                .padding(.vertical, QSpacing.m)
            }
            .padding(.horizontal, QSpacing.xl)
            .sheetCard()
            if let vitals, benefitHeal > 0 {
                Text("HP +\(Int(benefitHeal.rounded())) · не выше \(Vitals.whole(vitals.maxHP))")
                    .font(QFont.text(13, weight: .bold)).foregroundStyle(QColor.forest)
            }
        }
    }

    private func benefitRow(title: String, kind: BenefitKind) -> some View {
        HStack(spacing: QSpacing.l) {
            Text(title).font(QFont.text(15))
            Spacer(minLength: 0)
            Stepper(value: Binding(get: { draft.benefits[kind] ?? 0 }, set: { draft.benefits[kind] = $0 }), in: 0...WellbeingService.maxCount) {
                Text("\(draft.benefits[kind] ?? 0)").font(QFont.text(15, weight: .semibold)).monospacedDigit()
            }
            .fixedSize()
            .accessibilityLabel(title)
        }
        .padding(.vertical, QSpacing.m)
    }

    /// Оценка восстановления: +3% за отметку с учётом уже отмеченного сегодня и предела +10%.
    private var benefitHeal: Double {
        guard let vitals else { return 0 }
        let count = draft.benefits.values.reduce(0, +)
        let used = Double(model.todayBenefits.count) * BenefitRules.healShare
        let share = min(Double(count) * BenefitRules.healShare, max(0, BenefitRules.dailyCapShare - used))
        return min(vitals.maxHP - vitals.hp, vitals.maxHP * share)
    }

    private func counter(_ kind: HarmKind, note: String) -> some View {
        stepperRow(title: kind.title, note: note, value: Binding(
            get: { draft.counts[kind] ?? 0 }, set: { draft.counts[kind] = $0 }
        ), damage: hpDamage(kind.damagePercent ?? 0, count: draft.counts[kind] ?? 0))
    }

    private func customCounter(_ habit: CustomHarmHabit) -> some View {
        stepperRow(title: habit.title, note: "−\(habit.damagePercent)% HP · своя", value: Binding(
            get: { draft.customCounts[habit.id] ?? 0 }, set: { draft.customCounts[habit.id] = $0 }
        ), damage: hpDamage(habit.damagePercent, count: draft.customCounts[habit.id] ?? 0))
    }

    private func stepperRow(title: String, note: String, value: Binding<Int>, damage: Int) -> some View {
        HStack(spacing: QSpacing.l) {
            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                Text(title).font(QFont.text(15))
                Text(note).font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
            Spacer(minLength: 0)
            if damage > 0 {
                Text("−\(damage)").font(QFont.text(13, weight: .bold)).foregroundStyle(QColor.hp).monospacedDigit()
            }
            Stepper(value: value, in: 0...WellbeingService.maxCount) {
                Text("\(value.wrappedValue)").font(QFont.text(15, weight: .semibold)).monospacedDigit()
            }
            .fixedSize()
            .accessibilityLabel(title)
        }
        .padding(.vertical, QSpacing.m)
    }

    private var alcoholRow: some View {
        VStack(alignment: .leading, spacing: QSpacing.s) {
            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                Text("Алкоголь").font(QFont.text(15))
                Text("дебаф INT на 24 ч · не HP").font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
            HStack(spacing: QSpacing.s) {
                alcoholOption(nil, title: "Нет", note: nil)
                ForEach(AlcoholDegree.allCases, id: \.self) { degree in
                    alcoholOption(degree, title: degree.title, note: "INT −\(degree.removedLevels(of: vitals?.intelligenceLevel ?? 0))")
                }
            }
        }
        .padding(.vertical, QSpacing.m)
    }

    private func alcoholOption(_ degree: AlcoholDegree?, title: String, note: String?) -> some View {
        let isOn = draft.alcohol == degree
        return Button { draft.alcohol = degree } label: {
            VStack(spacing: 0) {
                Text(title).font(QFont.text(14, weight: .semibold))
                if let note { Text(note).font(QFont.text(11)) }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(isOn ? QColor.sheet : QColor.ink)
            .background(isOn ? QColor.debuffINT : QColor.paper, in: RoundedRectangle(cornerRadius: QRadius.small))
            .overlay(RoundedRectangle(cornerRadius: QRadius.small).strokeBorder(isOn ? QColor.debuffINT : QColor.lineStrong))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Урон, как его посчитает проекция: доля от текущего MaxHP, по очереди.
    private func hpDamage(_ percent: Int, count: Int) -> Int {
        guard let max = vitals?.maxHP else { return 0 }
        return Int((max * Double(percent * count) / 100).rounded())
    }

    private var totalDamage: Double {
        guard let vitals else { return 0 }
        var percent = 0
        for kind in [HarmKind.smoking, .fastFood, .lateCaffeine] { percent += (kind.damagePercent ?? 0) * (draft.counts[kind] ?? 0) }
        for habit in model.overview?.customHarmHabits ?? [] { percent += habit.damagePercent * (draft.customCounts[habit.id] ?? 0) }
        return min(vitals.hp, vitals.maxHP * Double(percent) / 100)
    }

    @ViewBuilder private var summary: some View {
        if let vitals {
            VStack(alignment: .leading, spacing: QSpacing.s) {
                if totalDamage > 0 {
                    Text("HP \(Vitals.whole(vitals.hp)) → \(Vitals.whole(vitals.hp - totalDamage))")
                        .font(QFont.text(15, weight: .bold)).foregroundStyle(QColor.hp).monospacedDigit()
                }
                if let degree = draft.alcohol {
                    let removed = degree.removedLevels(of: vitals.intelligenceLevel)
                    let until = Date.now.addingTimeInterval(Hangover.duration).formatted(date: .omitted, time: .shortened)
                    Text("Похмелье: INT \(vitals.intelligenceLevel) → \(max(0, vitals.intelligenceLevel - removed)) до \(until) завтра · MaxMP −\(removed * 5)")
                        .font(QFont.text(13, weight: .semibold)).foregroundStyle(QColor.debuffINT)
                }
                Text("XP и ранг не меняются. Ошибочную отметку можно удалить — урон вернётся.")
                    .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
        }
    }

    // MARK: Сегодня отмечено

    private var todayList: some View {
        VStack(alignment: .leading, spacing: QSpacing.s) {
            CapsHeader(title: "Отмечено сегодня")
            VStack(spacing: 0) {
                ForEach(model.todayHarms) { harm in
                    HStack {
                        Text(harm.at.formatted(date: .omitted, time: .shortened))
                            .font(QFont.text(12, weight: .semibold)).foregroundStyle(QColor.inkSecondary).monospacedDigit()
                        Text(harm.title).font(QFont.text(14))
                        Spacer()
                        Button(role: .destructive) {
                            Task { await model.deleteHarm(harm.id) }
                        } label: {
                            Image(systemName: "trash").font(.system(size: 14)).frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(QColor.hp)
                        .accessibilityLabel("Удалить отметку «\(harm.title)»")
                    }
                    .padding(.vertical, QSpacing.xs)
                }
                ForEach(model.todayBenefits) { benefit in
                    HStack {
                        Text(benefit.at.formatted(date: .omitted, time: .shortened))
                            .font(QFont.text(12, weight: .semibold)).foregroundStyle(QColor.inkSecondary).monospacedDigit()
                        Text(benefit.title).font(QFont.text(14))
                        Text("+HP").font(QFont.text(12, weight: .bold)).foregroundStyle(QColor.forest)
                        Spacer()
                        Button(role: .destructive) {
                            Task { await model.deleteBenefit(benefit.id) }
                        } label: {
                            Image(systemName: "trash").font(.system(size: 14)).frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(QColor.hp)
                        .accessibilityLabel("Удалить отметку «\(benefit.title)»")
                    }
                    .padding(.vertical, QSpacing.xs)
                }
            }
            .padding(.horizontal, QSpacing.xl)
            .sheetCard()
        }
    }

    private func save() {
        isSaving = true
        Task {
            if await model.checkIn(draft) { dismiss() }
            isSaving = false
        }
    }
}

enum WeatherStyle {
    static func symbol(_ weather: Weather) -> String {
        switch weather {
        case .clear: "sun.max"
        case .cloudy: "cloud"
        case .rain: "cloud.rain"
        case .snow: "cloud.snow"
        }
    }
}

/// Погода по последней отметке и кнопка «Как вы?» (макет TodayV2).
struct WeatherCard: View {
    let model: AppModel
    let checkIn: () -> Void

    var body: some View {
        HStack(spacing: QSpacing.l) {
            Image(systemName: WeatherStyle.symbol(model.weather))
                .font(.system(size: 22))
                .foregroundStyle(QColor.amber)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                Text(model.weather.title).font(QFont.text(15, weight: .semibold))
                Text(model.lastMood.map { "по отметке \($0.at.formatted(date: .omitted, time: .shortened))" } ?? "отметок сегодня нет")
                    .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
            }
            Spacer()
            Button("Как вы?", action: checkIn)
                .font(QFont.text(14, weight: .semibold))
                .padding(.horizontal, QSpacing.xl)
                .frame(height: 36)
                .foregroundStyle(QColor.sheet)
                .background(QColor.ink, in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(.horizontal, QSpacing.xl)
        .padding(.vertical, QSpacing.l)
        .sheetCard()
    }
}
