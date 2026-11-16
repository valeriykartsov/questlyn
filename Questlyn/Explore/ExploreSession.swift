import Foundation
import Observation
import Domain

/// Состояние прогулки (8B): общее для сцены SpriteKit и экранов SwiftUI. Ничего не сохраняется (песочница).
@Observable
final class ExploreSession {
    let input: ExploreInput
    let island: Island
    let hero: ExploreHero
    let seed: UInt64
    let accent: UInt32
    let appearance: HeroAppearance?
    /// Время года текстур суши и осадки — выбор игрока (02, 12.11.2026).
    let season: Season
    let precipitation: Bool

    var hp: Double
    var mp: Double
    var heroTile: TilePoint
    var visitedCities: Set<Int> = []
    var openedChests: Set<Int> = []
    var litCampfires: Set<Int> = []
    /// Последний посещённый город — сюда герой возвращается после поражения.
    var lastCity: TilePoint
    var wins = 0
    var persuaded = 0
    var escapes = 0
    var defeats = 0
    var steps = 0
    let startedAt = Date.now

    /// Текущая встреча (сцена на паузе, пока она открыта).
    var encounter: Encounter?
    var encounterNPC: Int?
    /// Способности на карте: перезарядка до момента.
    var mapCooldownUntil: [ExploreAbility: Date] = [:]
    var dashUntil: Date?
    var scoutUntil: Date?
    /// Короткое сообщение поверх карты: «Сундук: …», «Костёр: +HP».
    var toast: String?
    /// Масштаб камеры: меньше — крупнее (9.7).
    var zoom: CGFloat = 0.5
    static let zoomRange: ClosedRange<CGFloat> = 0.3...1.0
    /// Призраки просроченных задач (9.6) — число, они только летают.
    var ghostCount = 0
    /// Ступень ауры ранга (10.3, 0 — без ауры): в «Побродить» — по решению 12.11.2026.
    var aura = 0
    /// 💧 или ✨ у героя (12D.5).
    var badge: HeroBadge?
    /// Корабли архипелага (12B): позиция меняется — корабль остаётся там, где сошёл герой.
    var ships: [TilePoint]
    /// Корабль, которым управляет герой; nil — герой на суше.
    var sailing: Int?
    /// Острова, на которые ступал герой.
    var visitedRegions: Set<Int> = []

    // MARK: Этап 14 (макеты ExploreFeatures, ExploreBag)

    /// Сумка: предметы из сундуков, всего не больше 6.
    var bag: [ExploreItem: Int] = [:]
    var bagCount: Int { bag.values.reduce(0, +) }
    /// Спутник — последний уговорённый NPC.
    var companion: IslandNPC?
    var readBottles: Set<Int> = []
    var conqueredTowers: Set<Int> = []
    var litLighthouses: Set<Int> = []
    var visitedVillages: Set<Int> = []
    /// Задания досок: взятые (по порядку взятия) и выполненные. Условия считаются за всю прогулку —
    /// задание может оказаться выполненным уже при взятии (16.11.2026).
    var takenTasks: [Int] = []
    var doneTasks: Set<Int> = []
    /// Открытое письмо из бутылки.
    var letter: IslandBottle?
    var torchUntil: Date?
    var compassUntil: Date?
    var lighthouseUntil: Date?
    /// Башня текущей встречи со стражем.
    var encounterTower: Int?
    /// Часы на острове: 24 ч = 12 мин; старт — текущее время суток.
    var clockHour: Double = 12

    var isNight: Bool { ExploreRules.isNight(hour: clockHour) }
    var clockText: String { String(format: "%02d:%02d", Int(clockHour) % 24, Int(clockHour * 60) % 60) }

    func addItem(_ item: ExploreItem) -> Bool {
        guard bagCount < ExploreRules.bagCap else { return false }
        bag[item, default: 0] += 1
        return true
    }

    func useItem(_ item: ExploreItem) {
        guard (bag[item] ?? 0) > 0, encounter == nil else { return }
        bag[item, default: 0] -= 1
        switch item {
        case .potionHP: hp = min(hero.maxHP, hp + hero.maxHP * ExploreRules.potionShare)
        case .potionMP: mp = min(hero.maxMP, mp + hero.maxMP * ExploreRules.potionShare)
        case .torch: torchUntil = .now + ExploreRules.torchSeconds
        case .compass: compassUntil = .now + ExploreRules.compassSeconds
        }
        toast = "\(item.title): \(item.note)"
    }

    /// Прогресс задания доски: сколько сделано из скольких.
    func progress(_ task: CityTask) -> (done: Int, total: Int) {
        if doneTasks.contains(task.id) { return (1, 1) }
        switch task.kind {
        case let .reachVillage(id): return (visitedVillages.contains(id) ? 1 : 0, 1)
        case let .openChests(count): return (min(count, openedChests.count), count)
        case .lightCampfire: return (min(1, litCampfires.count), 1)
        }
    }

    func taskTitle(_ task: CityTask) -> String {
        switch task.kind {
        case let .reachVillage(id): "Дойти до деревни «\(island.villages.first { $0.id == id }?.name ?? "")»"
        case let .openChests(count): "Открыть \(count) сундука"
        case .lightCampfire: "Зажечь костёр"
        }
    }

    /// Город задания — для списка.
    func cityName(_ task: CityTask) -> String { island.cities.first { $0.id == task.cityId }?.name ?? "" }

    /// Взять задание доски при первом входе в город; если условие уже выполнено — сразу награда.
    func takeTask(_ task: CityTask) {
        guard !takenTasks.contains(task.id) else { return }
        takenTasks.append(task.id)
        toast = "Доска «\(cityName(task))»: \(taskTitle(task))"
        settleTasks(justTaken: task.id)
    }

    /// Проверить взятые задания; выполненное — награда +25% HP и MP.
    func settleTasks(justTaken: Int? = nil) {
        for id in takenTasks where !doneTasks.contains(id) {
            guard let task = island.tasks.first(where: { $0.id == id }) else { continue }
            let state = progress(task)
            guard state.done >= state.total else { continue }
            doneTasks.insert(id)
            hp = min(hero.maxHP, hp + hero.maxHP * ExploreRules.taskRewardShare)
            mp = min(hero.maxMP, mp + hero.maxMP * ExploreRules.taskRewardShare)
            let reward = "+\(Int(ExploreRules.taskRewardShare * 100))% HP и MP"
            toast = id == justTaken ? "«\(taskTitle(task))» — уже выполнено: \(reward)" : "Задание выполнено: \(reward)"
        }
    }

    func startGuardian(_ tower: IslandTower) {
        encounterTower = tower.id
        encounterNPC = nil
        var fight = Encounter(tier: .regular, hero: hero, heroHP: hp, heroMP: mp, seed: seed &+ UInt64(steps * 17 + tower.id),
                              guardian: .init(title: tower.title, hp: tower.guardianHP))
        if let companion { fight.companionAssist(tier: companion.tier) }
        encounter = fight
    }

    /// Корабль в радиусе посадки — показывается «Сесть на корабль».
    var boardableShip: Int? {
        guard sailing == nil, encounter == nil else { return nil }
        return ships.indices.min { ships[$0].distance(to: heroTile) < ships[$1].distance(to: heroTile) }
            .flatMap { ships[$0].distance(to: heroTile) <= ExploreRules.boardRadius ? $0 : nil }
    }

    /// Клетка суши рядом с кораблём — «Сойти на берег» доступна.
    var landingTile: TilePoint? {
        guard sailing != nil else { return nil }
        return island.landing(near: heroTile)
    }

    init(input: ExploreInput, hero: ExploreHero, attempt: Int, appearance: HeroAppearance?, accent: UInt32,
         season: Season, precipitation: Bool) {
        self.season = season
        self.precipitation = precipitation
        self.input = input
        self.hero = hero
        self.seed = input.seed(attempt: attempt)
        self.island = IslandGenerator.generate(input, seed: seed)
        self.appearance = appearance
        self.accent = accent
        hp = hero.hp
        mp = hero.mp
        heroTile = island.start
        lastCity = island.start
        ships = island.ships.map(\.position)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: .now)
        clockHour = Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
        if let region = island.region(at: island.start) { visitedRegions.insert(region.id) }
    }

    static let mapCooldown: TimeInterval = 10

    func canUseOnMap(_ skill: ExploreSkill) -> Bool {
        guard skill.ability == .dash || skill.ability == .scout, encounter == nil, sailing == nil else { return false }
        if let until = mapCooldownUntil[skill.ability], until > .now { return false }
        return mp >= (skill.ability.mpShare * hero.maxMP).rounded()
    }

    /// Рывок — ускорение ×2 на 3·m с; Разведка — обзор 15 клеток на 10 с (09, раздел 6).
    func useOnMap(_ skill: ExploreSkill) {
        guard canUseOnMap(skill) else { return }
        mp -= (skill.ability.mpShare * hero.maxMP).rounded()
        mapCooldownUntil[skill.ability] = .now + Self.mapCooldown
        switch skill.ability {
        case .dash: dashUntil = .now + 3 * skill.power
        case .scout: scoutUntil = .now + 10
        default: break
        }
    }

    var speed: Double {
        if sailing != nil { return hero.walkSpeed * ExploreRules.sailSpeedFactor }
        return hero.walkSpeed * ((dashUntil ?? .distantPast) > .now ? 2 : 1)
    }
    /// Обзор: Разведка и факел — 15 клеток; маяк +3; ночью ×0,7 (14.5).
    var vision: Double {
        let now = Date.now
        if (scoutUntil ?? .distantPast) > now || (torchUntil ?? .distantPast) > now { return ExploreRules.torchVision }
        var value = hero.vision + ((lighthouseUntil ?? .distantPast) > now ? ExploreRules.lighthouseVisionBonus : 0)
        if isNight { value *= ExploreRules.nightVisionFactor }
        return value
    }

    func startEncounter(npc: IslandNPC) {
        encounterNPC = npc.id
        encounterTower = nil
        var fight = Encounter(tier: npc.tier, hero: hero, heroHP: hp, heroMP: mp, seed: seed &+ UInt64(steps * 31 + npc.id))
        if let companion { fight.companionAssist(tier: companion.tier) }
        encounter = fight
    }

    /// Итог встречи переносит HP и MP на карту; поражение — в последний город с половиной HP.
    func finishEncounter() -> EncounterOutcome? {
        guard let encounter else { return nil }
        let outcome = encounter.outcome
        hp = encounter.heroHP
        mp = encounter.heroMP
        switch outcome {
        case .won:
            wins += 1
            // Страж повержен — башня взята, сундук Epic: предмет в сумку.
            if let id = encounterTower, let tower = island.towers.first(where: { $0.id == id }) {
                conqueredTowers.insert(id)
                let item = ExploreItem.allCases[(id + steps) % ExploreItem.allCases.count]
                toast = "Сундук «Epic: \(tower.title)»" + (addItem(item) ? " · \(item.title)" : " · сумка полна")
            }
        case .persuaded:
            persuaded += 1
            // Уговорённый становится спутником (заменяет прежнего).
            if let id = encounterNPC, let npc = island.npcs.first(where: { $0.id == id }) { companion = npc }
        case .fled: escapes += 1
        case .lost:
            defeats += 1
            hp = (hero.maxHP * ExploreRules.defeatHPShare).rounded()
        case nil: break
        }
        self.encounter = nil
        encounterTower = nil
        return outcome
    }
}
