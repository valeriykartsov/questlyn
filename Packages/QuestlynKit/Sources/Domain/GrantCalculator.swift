import Foundation

/// Начисления за выполнение квеста по Rule Set v1.1 (07, разделы 2–4).
public enum GrantCalculator {
    /// Базовые значения для среднего приоритета, в XP.
    public static let questFocusXP = 5
    public static let questSkillXP = 10
    public static let questAttributeXP = 10

    /// - Parameters:
    ///   - skill: навык квеста, если есть; профессия навыка — в `snapshot`.
    ///   - skillProfessionTitle: для текста причины.
    public static func questCompletionGrants(
        completionId: UUID,
        priority: QuestPriority,
        skill: Skill?,
        skillProfessionTitle: String?,
        snapshot: ClassSnapshot,
        createdAt: Date,
        effectiveDate: LocalDate? = nil,
        ruleVersion: RuleVersion = .current
    ) -> [ProgressGrant] {
        let k = priority.multiplierInHalves
        let priorityNote = priorityText(priority)
        func grant(_ target: GrantTarget, _ amount: CentiXP, _ reason: String) -> ProgressGrant {
            ProgressGrant(
                sourceType: .questCompletion, sourceId: completionId, ruleVersion: ruleVersion,
                target: target, amount: amount, reason: reason, createdAt: createdAt, effectiveDate: effectiveDate
            )
        }

        // FOC +5 × k — за любой обычный квест (07, раздел 4).
        var grants = [grant(
            .attribute(.focus),
            CentiXP.roundedHalfUp(numerator: questFocusXP * 100 * k, denominator: 2),
            "Обычный квест · \(priorityNote)"
        )]

        guard let skill else { return grants }

        // Навык +10 × k.
        let professionNote = skillProfessionTitle.map { "Навык профессии «\($0)»" } ?? "Навык"
        grants.append(grant(
            .skill(skill.id),
            CentiXP.roundedHalfUp(numerator: questSkillXP * 100 * k, denominator: 2),
            "\(professionNote) · \(priorityNote)"
        ))

        // Атрибуты: 10 × k × доля × Class Multiplier.
        let shares = ClassRules.sharesInPercent(attributeCount: snapshot.entries.count)
        let roles = ["Основной", "Вторичный", "Третичный"]
        for (index, entry) in snapshot.entries.enumerated() where index < shares.count {
            let share = shares[index]
            // centi = 10 · 100 · (k/2) · (share/100) · (m/4) = 10 · k · share · m / 8
            let amount = CentiXP.roundedHalfUp(
                numerator: questAttributeXP * k * share * entry.multiplierInQuarters,
                denominator: 8
            )
            var reason = "\(roles[index]) атрибут профессии · \(share)%"
            if entry.multiplierInQuarters != 4 {
                reason += " · ×\(multiplierText(entry.multiplierInQuarters)) за повтор в классе"
            }
            if priority != .medium { reason += " · \(priorityNote)" }
            grants.append(grant(.attribute(entry.attribute), amount, reason))
        }
        return grants
    }

    /// Базовые значения награды привычки (D1: без приоритета).
    public static let habitSkillXP = 5
    public static let habitAttributeXP = 5

    /// Отметка Daily или Weekly: только при связанном навыке — +5 навыку и 5 атрибутам по долям профессии.
    /// FOC привычки не дают (07, раздел 4).
    public static func habitOccurrenceGrants(
        occurrenceId: UUID,
        skill: Skill?,
        skillProfessionTitle: String?,
        snapshot: ClassSnapshot,
        createdAt: Date,
        effectiveDate: LocalDate? = nil,
        ruleVersion: RuleVersion = .current
    ) -> [ProgressGrant] {
        guard let skill else { return [] }
        func grant(_ target: GrantTarget, _ amount: CentiXP, _ reason: String) -> ProgressGrant {
            ProgressGrant(sourceType: .habitOccurrence, sourceId: occurrenceId, ruleVersion: ruleVersion,
                          target: target, amount: amount, reason: reason, createdAt: createdAt, effectiveDate: effectiveDate)
        }
        let professionNote = skillProfessionTitle.map { "Привычка · навык профессии «\($0)»" } ?? "Привычка"
        var grants = [grant(.skill(skill.id), .xp(habitSkillXP), professionNote)]
        let shares = ClassRules.sharesInPercent(attributeCount: snapshot.entries.count)
        let roles = ["Основной", "Вторичный", "Третичный"]
        for (index, entry) in snapshot.entries.enumerated() where index < shares.count {
            // centi = 5 · 100 · (share/100) · (m/4) = 5 · share · m / 4
            let amount = CentiXP.roundedHalfUp(numerator: habitAttributeXP * shares[index] * entry.multiplierInQuarters, denominator: 4)
            var reason = "Привычка · \(roles[index].lowercased()) атрибут профессии · \(shares[index])%"
            if entry.multiplierInQuarters != 4 { reason += " · ×\(multiplierText(entry.multiplierInQuarters)) за повтор в классе" }
            grants.append(grant(.attribute(entry.attribute), amount, reason))
        }
        return grants
    }

    /// Стартовый бонус (02, 07): основной атрибут каждой профессии +1 уровень, совпадения складываются.
    /// Начисление — XP до нужного уровня: +1 → 20 XP, +2 → 45 XP.
    public static func onboardingBonusGrants(
        heroId: UUID, professions: [Profession], createdAt: Date, effectiveDate: LocalDate, ruleVersion: RuleVersion = .current
    ) -> [ProgressGrant] {
        var levels: [Attribute: [String]] = [:]
        for profession in professions where profession.isActive {
            if let primary = profession.attributes.first { levels[primary, default: []].append(profession.title) }
        }
        return Attribute.allCases.compactMap { attribute in
            guard let titles = levels[attribute] else { return nil }
            let names = titles.map { "«\($0)»" }.joined(separator: ", ")
            return ProgressGrant(
                sourceType: .onboardingBonus, sourceId: heroId, ruleVersion: ruleVersion, target: .attribute(attribute),
                amount: .xp(LevelCurve.totalXP(forLevel: titles.count)),
                reason: "Стартовый бонус: основной атрибут профессии \(names) · +\(titles.count) ур.",
                createdAt: createdAt, effectiveDate: effectiveDate
            )
        }
    }

    static func priorityText(_ priority: QuestPriority) -> String {
        switch priority {
        case .low: "низкий приоритет ×0,5"
        case .medium: "средний приоритет"
        case .high: "высокий приоритет ×1,5"
        }
    }

    static func multiplierText(_ quarters: Int) -> String {
        switch quarters {
        case 5: "1,25"
        case 6: "1,5"
        default: String(format: "%.2f", Double(quarters) / 4).replacingOccurrences(of: ".", with: ",")
        }
    }
}
