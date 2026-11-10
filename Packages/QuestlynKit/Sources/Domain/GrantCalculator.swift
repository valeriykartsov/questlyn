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
        ruleVersion: RuleVersion = .current
    ) -> [ProgressGrant] {
        let k = priority.multiplierInHalves
        let priorityNote = priorityText(priority)
        func grant(_ target: GrantTarget, _ amount: CentiXP, _ reason: String) -> ProgressGrant {
            ProgressGrant(
                sourceType: .questCompletion, sourceId: completionId, ruleVersion: ruleVersion,
                target: target, amount: amount, reason: reason, createdAt: createdAt
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
