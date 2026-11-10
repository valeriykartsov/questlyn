import Foundation

/// Шаблон типа активности (02, 07; утверждён 10.11.2026). Тип задаёт атрибуты без навыка и предел 3 ч в день.
public struct ActivityTemplate: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let attributes: [Attribute]

    public static let all: [ActivityTemplate] = [
        .init(id: "strength", title: "Силовая тренировка", attributes: [.strength, .endurance]),
        .init(id: "cardio", title: "Бег и кардио", attributes: [.endurance]),
        .init(id: "team-sport", title: "Командный спорт", attributes: [.endurance, .strength, .charisma]),
        .init(id: "walk", title: "Прогулка", attributes: [.endurance]),
        .init(id: "study", title: "Учёба и чтение", attributes: [.intelligence]),
        .init(id: "deep-work", title: "Работа в фокусе", attributes: [.intelligence, .mentality]),
        .init(id: "social", title: "Общение и выступления", attributes: [.charisma]),
        .init(id: "meditation", title: "Медитация", attributes: [.mentality]),
        .init(id: "creative", title: "Творчество", attributes: [.intelligence, .charisma]),
    ]

    public static func template(id: String) -> ActivityTemplate? { all.first { $0.id == id } }
}

/// Факт: Activity. `id` — `sourceId` начислений. Удаление ставит `deletedAt` (история сохраняется).
public struct Activity: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var templateId: String
    public var skillId: UUID?
    public var durationMinutes: Int
    /// Сколько минут засчитано в XP с учётом предела 3 ч одного типа в день.
    public var creditedMinutes: Int
    public var localDate: LocalDate
    public var startedAt: Date
    public var timezoneId: String
    /// Квест, закрытый этой активностью: навык и атрибуты — от Activity, от квеста — только FOC (07).
    public var questCompletionId: UUID?
    public var classSnapshot: ClassSnapshot
    public var deletedAt: Date?

    public init(id: UUID = UUID(), templateId: String, skillId: UUID?, durationMinutes: Int, creditedMinutes: Int,
                localDate: LocalDate, startedAt: Date, timezoneId: String, questCompletionId: UUID? = nil,
                classSnapshot: ClassSnapshot, deletedAt: Date? = nil) {
        self.id = id
        self.templateId = templateId
        self.skillId = skillId
        self.durationMinutes = durationMinutes
        self.creditedMinutes = creditedMinutes
        self.localDate = localDate
        self.startedAt = startedAt
        self.timezoneId = timezoneId
        self.questCompletionId = questCompletionId
        self.classSnapshot = classSnapshot
        self.deletedAt = deletedAt
    }

    public var template: ActivityTemplate? { ActivityTemplate.template(id: templateId) }
}

public enum ActivityRules {
    public static let xpPerHour = 10
    /// Предел F3: не больше 3 часов одного типа в день.
    public static let dailyCapMinutes = 180
    public static let maxDurationMinutes = 24 * 60

    /// Минуты в XP: остаток дневного предела по этому типу.
    public static func creditedMinutes(duration: Int, alreadyCreditedToday: Int) -> Int {
        max(0, min(duration, dailyCapMinutes - alreadyCreditedToday))
    }
}

extension GrantCalculator {
    /// Activity (07, раздел 2): с навыком — навык +10 XP/ч и атрибуты профессии 10 XP/ч по долям с Class Multiplier;
    /// без навыка — 10 XP/ч поровну на атрибуты шаблона. FOC не даёт.
    public static func activityGrants(
        activityId: UUID, template: ActivityTemplate, creditedMinutes: Int, skill: Skill?, skillProfessionTitle: String?,
        snapshot: ClassSnapshot, createdAt: Date, effectiveDate: LocalDate, ruleVersion: RuleVersion = .current
    ) -> [ProgressGrant] {
        guard creditedMinutes > 0 else { return [] }
        func grant(_ target: GrantTarget, _ amount: CentiXP, _ reason: String) -> ProgressGrant {
            ProgressGrant(sourceType: .activity, sourceId: activityId, ruleVersion: ruleVersion, target: target, amount: amount,
                          reason: reason, createdAt: createdAt, effectiveDate: effectiveDate)
        }
        let minutes = creditedMinutes
        let base = "\(template.title) · \(minutes) мин"
        guard let skill else {
            let n = template.attributes.count
            return template.attributes.map { attribute in
                // centi = 10 · 100 · (мин/60) / n
                grant(.attribute(attribute), CentiXP.roundedHalfUp(numerator: ActivityRules.xpPerHour * 100 * minutes, denominator: 60 * n),
                      "\(base) · атрибут шаблона" + (n > 1 ? ", поровну на \(n)" : ""))
            }
        }
        var grants = [grant(.skill(skill.id), CentiXP.roundedHalfUp(numerator: ActivityRules.xpPerHour * 100 * minutes, denominator: 60),
                            skillProfessionTitle.map { "\(base) · навык профессии «\($0)»" } ?? base)]
        let shares = ClassRules.sharesInPercent(attributeCount: snapshot.entries.count)
        let roles = ["основной", "вторичный", "третичный"]
        for (index, entry) in snapshot.entries.enumerated() where index < shares.count {
            // centi = 10 · 100 · (мин/60) · (share/100) · (m/4) = 10 · мин · share · m / 240
            let amount = CentiXP.roundedHalfUp(numerator: ActivityRules.xpPerHour * minutes * shares[index] * entry.multiplierInQuarters, denominator: 240)
            var reason = "\(base) · \(roles[index]) атрибут профессии · \(shares[index])%"
            if entry.multiplierInQuarters != 4 { reason += " · ×\(multiplierText(entry.multiplierInQuarters)) за повтор в классе" }
            grants.append(grant(.attribute(entry.attribute), amount, reason))
        }
        return grants
    }
}
