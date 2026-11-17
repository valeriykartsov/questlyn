import Foundation

// «Побродить», режим игры (16.11.2026, макеты ExploreActive, ExploreActiveRules).
// Активный бой — встреча прямо на карте в реальном времени. Урон и способности — как в пошаговой встрече,
// «ход» = 1,2 с. Правила — 09, раздел 4.1 (Рабочая гипотеза, утверждены пользователем как макет).

/// Режим игры: одна настройка на бой и перемещение.
public enum ExploreMode: String, Sendable, CaseIterable {
    case turnBased, active

    public var title: String {
        switch self {
        case .turnBased: "Пошаговый · касание"
        case .active: "Активный · джойстик"
        }
    }

    public var summary: String {
        switch self {
        case .turnBased: "Касание карты — идти туда. Встреча — окно с ходами: удар, способность, побег."
        case .active: "Джойстик — идти. Бой прямо на карте в реальном времени: кнопки удара и способностей с перезарядкой, отойти — сбежать."
        }
    }
}

extension ExploreRules {
    /// Один «ход» активного боя, с: удар героя и удар NPC — не чаще.
    public static let activeTurnSeconds = 1.2
    /// Дальность удара — героя и NPC, клеток.
    public static let activeRange = 1.5
    /// «Разведка» усиливает удар, если он в течение этого времени.
    public static let activeScoutWindow = 5.0
    /// Спутник бьёт вместе с героем, но не чаще раза в 3 «хода» (16.11.2026, по запросу пользователя).
    public static let activeCompanionInterval = 3.6
    /// Страж башни не уходит от неё дальше — отойти дальше значит сбежать.
    public static let guardianLeash = 4.0
}

/// Активный бой с NPC или стражем башни.
public struct ActiveFight: Sendable {
    /// Что случилось за кадр — для всплывающих чисел на карте.
    public enum Event: Hashable, Sendable {
        case heroDamaged(Int)
        case npcDamaged(Int)
        /// Удар спутника — вместе с ударом героя.
        case companionHit(Int)
        case note(String)
    }

    public let tier: NPCTier
    public let hero: ExploreHero
    public let guardian: Encounter.Guardian?
    public let companion: NPCTier?
    public private(set) var heroHP: Double
    public private(set) var heroMP: Double
    public private(set) var npcHP: Double
    public private(set) var outcome: EncounterOutcome?
    /// До готовности удара и способностей, с.
    public private(set) var strikeCooldown: Double = 0
    public private(set) var cooldowns: [ExploreAbility: Double] = [:]
    public private(set) var events: [Event] = []
    private var npcTimer = ExploreRules.activeTurnSeconds
    /// До готовности удара спутника, с.
    public private(set) var companionCooldown = 0.0
    private var focusLeft = 0.0
    private var distractLeft = 0.0
    private var scoutLeft = 0.0
    private var nextHitBonus = 1.0
    private var random: ExploreRandom
    /// Баффы монументов (15G.4): урон по герою и перезарядка — множители.
    public var damageTakenFactor = 1.0
    public var cooldownFactor = 1.0

    public let isNight: Bool

    public init(tier: NPCTier, hero: ExploreHero, heroHP: Double, heroMP: Double, seed: UInt64,
                guardian: Encounter.Guardian? = nil, companion: NPCTier? = nil, night: Bool = false) {
        self.isNight = night
        self.tier = tier
        self.hero = hero
        self.guardian = guardian
        self.companion = companion
        self.heroHP = heroHP
        self.heroMP = heroMP
        self.npcHP = guardian?.hp ?? tier.hp * (night ? ExploreRules.nightHPFactor : 1)
        self.random = ExploreRandom(seed)
    }

    public var npcMaxHP: Double { guardian?.hp ?? tier.hp * (isNight ? ExploreRules.nightHPFactor : 1) }
    public var opponentTitle: String { opponentName ?? (guardian == nil ? tier.title : "Страж башни") }
    /// 15H: имя противника (монстр) и бонусы спутника-легенды: урон героя и первый удар.
    public var opponentName: String?
    public var heroDamageFactor = 1.0
    public var firstStrikeFactor = 1.0
    private var struckOnce = false
    /// Отойти дальше — сбежать: радиус погони NPC или поводок стража.
    public var escapeDistance: Double {
        guardian == nil ? tier.chaseRadius + (isNight ? ExploreRules.nightChaseBonus : 0) : ExploreRules.guardianLeash
    }
    public func cost(_ ability: ExploreAbility) -> Double { (ability.mpShare * hero.maxMP).rounded() }
    /// Перезарядка способности: ходы × 1,2 с.
    public var abilityCooldown: Double { Double(hero.cooldown) * ExploreRules.activeTurnSeconds * cooldownFactor }

    public func isReady(_ skill: ExploreSkill) -> Bool {
        outcome == nil && (cooldowns[skill.ability] ?? 0) <= 0 && heroMP >= cost(skill.ability)
    }

    public func persuadeChance(power: Double) -> Double {
        let base = (0.30 + 0.05 * Double(hero.level(.charisma))) * power
        return min(0.85, max(0, base - 0.15 * Double(tier.rawValue - 1)))
    }

    /// Забрать события кадра.
    public mutating func drainEvents() -> [Event] {
        defer { events = [] }
        return events
    }

    /// Время идёт: перезарядки, удары NPC в радиусе, спутник. `distance` — между героем и противником, клеток.
    public mutating func tick(_ dt: Double, distance: Double) {
        guard outcome == nil else { return }
        strikeCooldown = max(0, strikeCooldown - dt)
        for key in cooldowns.keys { cooldowns[key] = max(0, (cooldowns[key] ?? 0) - dt) }
        focusLeft = max(0, focusLeft - dt)
        scoutLeft = max(0, scoutLeft - dt)
        if scoutLeft <= 0 { nextHitBonus = 1 }
        companionCooldown = max(0, companionCooldown - dt)
        if distractLeft > 0 { distractLeft = max(0, distractLeft - dt); return }
        npcTimer -= dt
        guard npcTimer <= 0 else { return }
        npcTimer = ExploreRules.activeTurnSeconds
        guard distance <= ExploreRules.activeRange else { return }
        var damage = (guardian?.damageShare ?? tier.damageShare) * hero.maxHP * random.spread(ExploreRules.hitSpread)
        if focusLeft > 0 { damage *= 0.5 }
        if isNight { damage *= ExploreRules.nightDamageFactor }
        damage = (damage * damageTakenFactor).rounded()
        heroHP = max(0, heroHP - damage)
        events.append(.heroDamaged(Int(damage)))
        if heroHP <= 0 { outcome = .lost; events.append(.note("Вы без сил — очнётесь в городе")) }
    }

    /// «Удар»: в радиусе и после перезарядки. false — не достать или ещё не готов.
    @discardableResult
    public mutating func strike(distance: Double) -> Bool {
        guard outcome == nil, strikeCooldown <= 0, distance <= ExploreRules.activeRange else { return false }
        strikeCooldown = ExploreRules.activeTurnSeconds
        hit(factor: 1)
        return true
    }

    /// Способность. Рывок здесь только тратит MP — ускорение на карте включает сцена.
    @discardableResult
    public mutating func use(_ skill: ExploreSkill, distance: Double) -> Bool {
        guard isReady(skill) else { return false }
        let needsTarget: Set<ExploreAbility> = [.powerStrike, .teamMove]
        if needsTarget.contains(skill.ability), distance > ExploreRules.activeRange { return false }
        heroMP -= cost(skill.ability)
        cooldowns[skill.ability] = abilityCooldown
        let power = skill.power, turn = ExploreRules.activeTurnSeconds
        switch skill.ability {
        case .powerStrike: hit(factor: 1 + power)
        case .teamMove:
            hit(factor: 1 + 0.5 * power)
            npcTimer += turn
        case .scout:
            nextHitBonus = 1 + 0.5 * power
            scoutLeft = ExploreRules.activeScoutWindow
            events.append(.note("Разведка: следующий удар ×\(String(format: "%.2g", nextHitBonus))"))
        case .focus:
            focusLeft = (2 * power).rounded(.down) * turn
            events.append(.note("Концентрация: урон вдвое меньше"))
        case .distract:
            distractLeft = (2 * power).rounded(.down) * turn
            events.append(.note("Отвлечь: \(opponentTitle) не бьёт"))
        case .dash:
            events.append(.note("Рывок — уходите"))
        case .persuade:
            if random.unit() < persuadeChance(power: power) {
                outcome = .persuaded
                events.append(.note("\(tier.title) согласился разойтись миром"))
            } else {
                events.append(.note("Уговорить не вышло"))
            }
        }
        return true
    }

    /// Герой отошёл дальше `escapeDistance`.
    public mutating func escape() {
        guard outcome == nil else { return }
        outcome = .fled
        events.append(.note("Вы оторвались"))
    }

    private mutating func hit(factor: Double) {
        let damage = (ExploreRules.strike(strength: hero.level(.strength)) * factor * nextHitBonus * heroDamageFactor * (struckOnce ? 1 : firstStrikeFactor) * random.spread(ExploreRules.hitSpread)).rounded()
        struckOnce = true
        nextHitBonus = 1
        scoutLeft = 0
        npcHP = max(0, npcHP - damage)
        events.append(.npcDamaged(Int(damage)))
        if npcHP <= 0 { win(); return }
        // Спутник бьёт вместе с героем, если его удар готов.
        if let companion, companionCooldown <= 0 {
            companionCooldown = ExploreRules.activeCompanionInterval
            let assist = ExploreRules.companionStrike(companion).rounded()
            npcHP = max(0, npcHP - assist)
            events.append(.companionHit(Int(assist)))
            if npcHP <= 0 { win() }
        }
    }

    private mutating func win() {
        outcome = .won
        events.append(.note("\(opponentTitle) повержен"))
    }
}
