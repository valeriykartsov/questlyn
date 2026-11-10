/// Уровень атрибута из XP (07, раздел 3): переход с L на L+1 стоит `20 + 5·L` XP.
public enum LevelCurve {
    /// Стоимость перехода с уровня `level` на `level + 1`, в XP.
    public static func cost(fromLevel level: Int) -> Int {
        precondition(level >= 0)
        return 20 + 5 * level
    }

    /// Сколько всего XP нужно для уровня `level`: Σ (20 + 5·i), i = 0…L−1 = 20L + 5L(L−1)/2.
    public static func totalXP(forLevel level: Int) -> Int {
        precondition(level >= 0)
        return 20 * level + 5 * level * (level - 1) / 2
    }

    /// Уровень по накопленному XP. Отрицательный XP считается нулём.
    public static func level(for xp: CentiXP) -> Int {
        var level = 0
        while xp.value >= totalXP(forLevel: level + 1) * 100 {
            level += 1
        }
        return level
    }
}
