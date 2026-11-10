/// Правила класса (07, раздел 3).
public enum ClassRules {
    /// Доли распределения XP по атрибутам профессии, в процентах: 1 → 100; 2 → 70/30; 3 → 50/30/20.
    public static func sharesInPercent(attributeCount: Int) -> [Int] {
        switch attributeCount {
        case 1: [100]
        case 2: [70, 30]
        case 3: [50, 30, 20]
        default: []
        }
    }

    /// Class Multiplier в четвертях: m = 1 + 0,25 · (n − 1), n — в скольких профессиях класса есть атрибут.
    public static func multiplierInQuarters(professionCount n: Int) -> Int {
        n <= 0 ? 4 : 4 + (n - 1)
    }

    /// Атрибуты класса — объединение атрибутов активных профессий.
    public static func classAttributes(of professions: [Profession]) -> Set<Attribute> {
        Set(professions.filter(\.isActive).flatMap(\.attributes))
    }

    /// Снимок состава профессии навыка на момент выполнения (03, `classSnapshot`).
    public static func snapshot(skillProfession: Profession, activeProfessions: [Profession]) -> ClassSnapshot {
        let active = activeProfessions.filter(\.isActive)
        let entries = skillProfession.attributes.map { attribute in
            let n = active.filter { $0.attributes.contains(attribute) }.count
            return ClassSnapshot.Entry(attribute: attribute, multiplierInQuarters: multiplierInQuarters(professionCount: max(n, 1)))
        }
        return ClassSnapshot(professionId: skillProfession.id, entries: entries)
    }
}
