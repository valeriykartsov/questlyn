import SwiftUI
import Domain
import Application

/// «Новая активность» (макет 8.1, утверждён 10.11.2026).
struct ActivityFormView: View {
    let model: AppModel
    var onDone: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var templateId = ActivityTemplate.all[1].id
    @State private var minutes = 40
    @State private var startedAt = Date.now
    @State private var skillId: UUID?
    @State private var questId: UUID?
    @State private var isSaving = false
    /// Привязка выбранного навыка к виду, если вид занят другим навыком, — с вопросом (8.6).
    @State private var pendingLink: (template: ActivityTemplate, skill: Skill, owner: Skill)?

    private let presets = [15, 30, 45, 60, 90]
    private var draft: ActivityDraft { ActivityDraft(templateId: templateId, durationMinutes: minutes, skillId: skillId, startedAt: startedAt) }
    private var selectedSkill: Skill? { model.skill(id: skillId) }
    private var isLinked: Bool { selectedSkill.map { $0.activityTemplateId == templateId } ?? false }
    private var openQuests: [TodayItem] { (model.overview?.journal ?? []).filter { !$0.isCompleted } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.l) {
                CapsHeader(title: "Тип активности")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: QSpacing.s), count: 3), spacing: QSpacing.s) {
                    ForEach(ActivityTemplate.all) { template in
                        let isOn = template.id == templateId
                        Button { templateId = template.id } label: {
                            VStack(alignment: .leading, spacing: QSpacing.xxs) {
                                Text(template.title).font(QFont.text(13, weight: .semibold)).multilineTextAlignment(.leading)
                                if let linked = model.linkedSkill(templateId: template.id) {
                                    Text("навык «\(linked.title)»").font(QFont.text(11, weight: .semibold)).foregroundStyle(QColor.forest)
                                } else {
                                    Text(template.attributes.map(\.code).joined(separator: " · ")).font(QFont.text(11)).foregroundStyle(QColor.inkSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .padding(.horizontal, QSpacing.m)
                            .background(QColor.sheet, in: RoundedRectangle(cornerRadius: QRadius.control))
                            .overlay(RoundedRectangle(cornerRadius: QRadius.control).strokeBorder(isOn ? QColor.ink : QColor.line, lineWidth: isOn ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }

                CapsHeader(title: "Длительность")
                DurationPicker(minutes: $minutes, presets: presets)

                VStack(spacing: 0) {
                    DatePicker("Когда", selection: $startedAt, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, Locale(identifier: "ru_RU"))
                        .font(QFont.text(15))
                        .padding(.horizontal, QSpacing.xl).frame(minHeight: 48)
                    Divider().overlay(QColor.line)
                    pickerRow("Навык") {
                        Picker("Навык", selection: $skillId) {
                            Text("Без навыка").tag(UUID?.none)
                            ForEach(model.activeProfessions) { profession in
                                let skills = model.skills.filter { $0.professionId == profession.id && $0.isActive }
                                if !skills.isEmpty { Section(profession.title) { ForEach(skills) { Text($0.title).tag(UUID?.some($0.id)) } } }
                            }
                        }
                    }
                    if isLinked {
                        Text("подставлен из привязки").font(QFont.text(12, weight: .semibold)).foregroundStyle(QColor.forest)
                            .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, QSpacing.xl).padding(.bottom, QSpacing.s)
                    }
                    Divider().overlay(QColor.line)
                    Toggle(isOn: Binding(get: { isLinked }, set: setLink)) {
                        VStack(alignment: .leading, spacing: QSpacing.xxs) {
                            Text("Привязать к виду").font(QFont.text(15))
                            Text(selectedSkill.map { "«\($0.title)» ↔ «\(template.title)»" } ?? "сначала выберите навык")
                                .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                        }
                    }
                    .tint(QColor.forest)
                    .disabled(selectedSkill == nil)
                    .padding(.horizontal, QSpacing.xl).frame(minHeight: 56)
                    Divider().overlay(QColor.line)
                    pickerRow("Закрыть квест") {
                        Picker("Закрыть квест", selection: $questId) {
                            Text("Не выбран").tag(UUID?.none)
                            ForEach(openQuests) { Text($0.quest.title).tag(UUID?.some($0.quest.id)) }
                        }
                    }
                }
                .sheetCard()

                RewardPreview(model: model, draft: draft, questFocus: questId.flatMap { id in openQuests.first { $0.quest.id == id }?.quest.priority })

                Button("Записать", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSaving)
            }
            .padding(QSpacing.screen)
        }
        .tint(QColor.amber)
        .paperScreen()
        .navigationTitle("Новая активность")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onDone == nil { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
        }
        .alert(pendingLink.map { "Перенести «\($0.template.title)» с навыка «\($0.owner.title)»?" } ?? "",
                            isPresented: Binding(get: { pendingLink != nil }, set: { if !$0 { pendingLink = nil } })) {
            Button("Перенести") {
                guard let link = pendingLink else { return }
                Task { await model.linkActivity(templateId: link.template.id, skillId: link.skill.id) }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("У вида активности может быть только один навык.")
        }
        .onAppear { applyLinkedSkill() }
        .onChange(of: templateId) { _, _ in applyLinkedSkill() }
        .onChange(of: questId) { _, id in
            // Квест с навыком подставляет свой навык.
            if let id, let quest = openQuests.first(where: { $0.quest.id == id })?.quest, let skill = quest.skillId { skillId = skill }
        }
    }

    private var template: ActivityTemplate { ActivityTemplate.template(id: templateId) ?? ActivityTemplate.all[0] }

    /// Вид с привязанным навыком подставляет его; квест с навыком важнее — его навык не перебиваем.
    private func applyLinkedSkill() {
        if let id = questId, openQuests.first(where: { $0.quest.id == id })?.quest.skillId != nil { return }
        if let linked = model.linkedSkill(templateId: templateId) { skillId = linked.id }
    }

    private func setLink(_ on: Bool) {
        guard let skill = selectedSkill else { return }
        guard on else { Task { await model.linkActivity(templateId: nil, skillId: skill.id) }; return }
        if let owner = model.linkedSkill(templateId: templateId), owner.id != skill.id {
            pendingLink = (template, skill, owner)
        } else {
            Task { await model.linkActivity(templateId: templateId, skillId: skill.id) }
        }
    }

    private func pickerRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(QFont.text(15))
            Spacer()
            content().labelsHidden()
        }
        .padding(.horizontal, QSpacing.xl)
        .frame(minHeight: 48)
    }

    private func save() {
        isSaving = true
        Task {
            let ok: Bool
            if let questId {
                ok = await model.complete(questId: questId, with: draft) != nil
            } else {
                ok = await model.recordActivity(draft) != nil
            }
            isSaving = false
            if ok { if let onDone { onDone() } else { dismiss() } }
        }
    }
}

/// Длительность: −/+ по 5 минут и быстрые значения.
struct DurationPicker: View {
    @Binding var minutes: Int
    let presets: [Int]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                stepButton("−", label: "Меньше на 5 минут") { minutes = max(5, minutes - 5) }
                Spacer()
                Text(Format.minutes(minutes)).font(QFont.title(30)).monospacedDigit()
                Spacer()
                stepButton("+", label: "Больше на 5 минут") { minutes = min(ActivityRules.maxDurationMinutes, minutes + 5) }
            }
            HStack(spacing: QSpacing.s) {
                ForEach(presets, id: \.self) { value in
                    let isOn = value == minutes
                    Button("\(value)") { minutes = value }
                        .font(QFont.text(13, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .foregroundStyle(isOn ? QColor.sheet : QColor.ink)
                        .background(isOn ? QColor.ink : .clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(isOn ? .clear : QColor.lineStrong))
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, QSpacing.l)
        .padding(.vertical, 10)
        .sheetCard()
    }

    private func stepButton(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(QFont.text(20, weight: .semibold))
            .frame(width: 44, height: 44)
            .background(QColor.paper, in: RoundedRectangle(cornerRadius: QRadius.control))
            .overlay(RoundedRectangle(cornerRadius: QRadius.control).strokeBorder(QColor.lineStrong))
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }
}

/// Карточка «Награда» (макеты 8.1, 8.2).
struct RewardPreview: View {
    let model: AppModel
    let draft: ActivityDraft
    /// Если активность закрывает квест — его приоритет для строки FOC.
    var questFocus: QuestPriority?

    var body: some View {
        let preview = model.previewActivity(draft)
        VStack(alignment: .leading, spacing: QSpacing.s) {
            Text("НАГРАДА · \(Format.minutes(draft.durationMinutes).uppercased())")
                .font(QFont.text(12, weight: .semibold)).tracking(0.7)
            if let questFocus {
                Text("От квеста: **FOC +\(Format.number(5 * questFocus.multiplier))** — навык и атрибуты начислит активность.")
                    .font(QFont.text(14))
            }
            Text(preview.grants.isEmpty ? "Предел на сегодня исчерпан — XP не будет." : model.grantSummary(preview.grants))
                .font(QFont.text(14, weight: .semibold))
            if preview.credited < draft.durationMinutes, preview.credited > 0 {
                Text("В XP войдёт \(Format.minutes(preview.credited)): предел — 3 часа одного типа в день.").font(QFont.text(12))
            }
            Text("10 XP за час. Без навыка — атрибуты шаблона поровну. В XP идёт не больше 3 часов одного типа в день. Ману не тратит.")
                .font(QFont.text(12))
        }
        .foregroundStyle(QColor.warmInk)
        .padding(.horizontal, QSpacing.xl)
        .padding(.vertical, QSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QColor.warmFill, in: RoundedRectangle(cornerRadius: QRadius.card))
    }
}

/// «Выполнить с активностью» (макет 8.2): лист из карточки квеста.
struct QuestActivitySheet: View {
    let model: AppModel
    let quest: Quest
    let onComplete: (CompletionReport) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var templateId = ActivityTemplate.all[1].id
    @State private var minutes = 30
    @State private var isSaving = false

    private var draft: ActivityDraft { ActivityDraft(templateId: templateId, durationMinutes: minutes, skillId: quest.skillId, startedAt: .now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: QSpacing.l) {
                    VStack(alignment: .leading, spacing: QSpacing.xs) {
                        Text("Выполнить с активностью").font(QFont.title(22))
                        Text(subtitle).font(QFont.text(14)).foregroundStyle(QColor.inkSecondary)
                    }
                    HStack {
                        Text("Тип").font(QFont.text(15))
                        Spacer()
                        Picker("Тип", selection: $templateId) {
                            ForEach(ActivityTemplate.all) { Text($0.title).tag($0.id) }
                        }
                        .labelsHidden()
                    }
                    .padding(.horizontal, QSpacing.xl).frame(minHeight: 48).sheetCard()
                    DurationPicker(minutes: $minutes, presets: [15, 30, 45, 60, 90])
                    RewardPreview(model: model, draft: draft, questFocus: quest.priority)
                    Text("Навык и атрибуты начисляются один раз — от активности. Квест добавляет только FOC" + (quest.epicId == nil ? "." : " и шаг Epic."))
                        .font(QFont.text(12)).foregroundStyle(QColor.inkSecondary)
                    Button("Выполнить и записать") {
                        isSaving = true
                        Task {
                            if let report = await model.complete(questId: quest.id, with: draft) {
                                dismiss()
                                onComplete(report)
                            }
                            isSaving = false
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSaving)
                }
                .padding(QSpacing.screen)
            }
            .tint(QColor.amber)
            .paperScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private var subtitle: String {
        var text = quest.title
        if let epic = model.epic(id: quest.epicId) { text += " · шаг Epic «\(epic.epic.title)»" }
        if let skill = model.skill(id: quest.skillId) { text += " · навык «\(skill.title)»" }
        return text
    }
}
