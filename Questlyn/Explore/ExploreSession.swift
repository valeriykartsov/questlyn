import Foundation
import CoreGraphics
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
    /// Земля кусками (15A.5): данные для отрисовки готовятся один раз.
    let ground: ExploreGround

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

    // MARK: Этап 15A

    /// Открытые клетки мира — для карты мира (15A.3).
    var explored: [Bool]
    private(set) var exploredLand = 0
    let landCount: Int
    /// Карта мира открыта — игра на паузе.
    var isWorldMapOpen = false
    // MARK: 15D (17.11.2026)

    /// Хранилище торговцев — общее на прогулку.
    var storage: [ExploreItem: Int] = [:]
    var storageCount: Int { storage.values.reduce(0, +) }
    /// Открытое окно торговца — игра на паузе.
    var merchantOpen: IslandMerchant?
    var nearbyMerchant: IslandMerchant? {
        guard sailing == nil, !inFight, inCave == nil else { return nil }
        return island.merchants.first { $0.position.distance(to: heroTile) <= 1.5 }
    }
    var companionSkill: CompanionSkill? { companion.map { CompanionSkill($0.tier) } }

    /// Обмен: отдать 2 предмета (можно одинаковых) — получить 1.
    @discardableResult
    func trade(give: [ExploreItem], get: ExploreItem) -> Bool {
        guard give.count == ExploreRules.tradeGive else { return false }
        let need = Dictionary(grouping: give, by: { $0 }).mapValues(\.count)
        guard need.allSatisfy({ (bag[$0.key] ?? 0) >= $0.value }) else { return false }
        for (item, count) in need { bag[item, default: 0] -= count }
        bag[get, default: 0] += 1
        toast = "Обмен: \(give.map(\.title).joined(separator: " + ")) → \(get.title)"
        return true
    }

    func deposit(_ item: ExploreItem) {
        guard (bag[item] ?? 0) > 0, storageCount < ExploreRules.storageCap else { return }
        bag[item, default: 0] -= 1
        storage[item, default: 0] += 1
    }

    func withdraw(_ item: ExploreItem) {
        guard (storage[item] ?? 0) > 0, bagCount < ExploreRules.bagCap else { return }
        storage[item, default: 0] -= 1
        bag[item, default: 0] += 1
    }

    /// Ночной NPC повержен — предмет в сумку.
    private func nightReward(_ npcId: Int?) {
        guard let npcId, let npc = island.npcs.first(where: { $0.id == npcId }), npc.isNight else { return }
        let item = ExploreItem.allCases[(npcId + steps) % ExploreItem.allCases.count]
        toast = "Ночной \(npc.tier.title.lowercased()) повержен" + (addItem(item) ? " · \(item.title)" : " · сумка полна")
    }

    // MARK: 15C (17.11.2026)

    var fragmentsFound: Set<Int> = []
    var fragmentsTotal: Int { island.chests.filter { $0.fragment != nil }.count }
    /// Место клада — после того как собраны все обрывки.
    var treasureSpot: TilePoint?
    var treasureFound = false
    var usedLookouts: Set<Int> = []
    var visitedCaves: Set<Int> = []
    /// Сколько тайников открыто в каждой пещере: «id-номер».
    var openedCaveChests: Set<String> = []
    /// Герой в пещере: её номер и откуда вошёл (через выход — идёт в обратную сторону).
    var inCave: Int?
    var enteredFromExit = false
    var showsAtlas = false

    func findFragment(_ fragment: Int, in chest: IslandChest) {
        fragmentsFound.insert(fragment)
        guard let treasure = island.treasure else { return }
        if fragmentsFound.count >= fragmentsTotal {
            let region = island.region(at: chest.position)?.id ?? 0
            treasureSpot = treasure.spots[region] ?? treasure.spots.values.first
            toast = "Карта собрана: клад «\(treasure.title)» отмечен крестиком"
        } else {
            toast = (toast.map { $0 + " · " } ?? "") + "обрывок карты \(fragmentsFound.count)/\(fragmentsTotal)"
        }
    }

    func openTreasure() {
        guard let treasure = island.treasure, !treasureFound else { return }
        treasureFound = true
        var found: [String] = []
        for k in 0..<ExploreRules.treasureItems {
            let item = ExploreItem.allCases[(k * 3 + steps) % ExploreItem.allCases.count]
            if addItem(item) { found.append(item.title) }
        }
        hp = min(hero.maxHP, hp + hero.maxHP * ExploreRules.treasureRestoreShare)
        mp = min(hero.maxMP, mp + hero.maxMP * ExploreRules.treasureRestoreShare)
        toast = "Клад «\(treasure.title)»: \(found.isEmpty ? "сумка полна" : found.joined(separator: ", ")) · +50% HP и MP"
    }

    func useLookout(_ lookout: IslandLookout) {
        guard !usedLookouts.contains(lookout.id) else { return }
        usedLookouts.insert(lookout.id)
        explore(around: lookout.position, radius: ExploreRules.lookoutRadius)
        scoutUntil = .now + 10
        toast = "Подзорная труба: открыто \(Int(ExploreRules.lookoutRadius)) клеток вокруг"
    }

    /// Пещера, у входа или выхода которой стоит герой.
    var enterableCave: IslandCave? {
        guard sailing == nil, !inFight, inCave == nil else { return nil }
        return island.caves.first { $0.entrance.distance(to: heroTile) <= 1.5 || $0.exit.distance(to: heroTile) <= 1.5 }
    }

    func enterCave() {
        guard let cave = enterableCave else { return }
        enteredFromExit = cave.exit.distance(to: heroTile) < cave.entrance.distance(to: heroTile)
        visitedCaves.insert(cave.id)
        inCave = cave.id
        toast = "Пещера: темно — обзор \(Int(ExploreRules.caveVision)) клетки, с факелом \(Int(ExploreRules.caveTorchVision))"
    }

    /// Выйти из пещеры: на другом конце.
    func leaveCave() -> TilePoint? {
        guard let id = inCave, let cave = island.caves.first(where: { $0.id == id }) else { return nil }
        inCave = nil
        let target = enteredFromExit ? cave.entrance : cave.exit
        heroTile = target
        return target
    }

    // MARK: 15B и 15G (17.11.2026)

    /// Баффы монументов полезного: вид → сила 0…1, до конца прогулки.
    var buffs: [ExploreBuff: Double] = [:]
    /// Открытая карточка памятника Epic.
    var monumentCard: IslandMonument?
    var finalTower: IslandTower? { island.towers.first(where: \.isFinal) }
    var isArchipelagoPassed: Bool { finalTower.map { conqueredTowers.contains($0.id) } ?? false }
    func buff(_ kind: ExploreBuff) -> Double { (buffs[kind] ?? 0) * kind.maximum }
    /// Подойти к монументу: бафф до конца прогулки (заменяет, если сильнее).
    func visit(_ shrine: IslandShrine) {
        guard shrine.strength > (buffs[shrine.buff] ?? 0) else { return }
        buffs[shrine.buff] = shrine.strength
        toast = "Монумент «\(shrine.buff.title)»: \(shrine.buff.effect(shrine.strength)) до конца прогулки"
    }
    /// Множители боя от баффов: растяжка — меньше урона, отдых — короче перезарядка.
    var damageTakenFactor: Double { 1 - buff(.stretch) }
    var cooldownFactor: Double { 1 - buff(.nap) }

    // MARK: Режим игры (16.11.2026)

    let mode: ExploreMode
    /// Джойстик: направление на экране (−1…1, y вниз); сцена читает каждый кадр.
    @ObservationIgnored var stick = CGVector.zero
    /// Активный бой на карте и его противник.
    var activeFight: ActiveFight?
    var activeNPC: Int?
    var activeTower: Int?
    /// Расстояние до противника, клеток (сцена обновляет каждый кадр).
    var activeDistance: Double = .infinity
    var inFight: Bool { encounter != nil || activeFight != nil }

    func startActive(npc: IslandNPC) {
        activeNPC = npc.id
        activeTower = nil
        activeFight = ActiveFight(tier: npc.tier, hero: hero, heroHP: hp, heroMP: mp, seed: seed &+ UInt64(steps * 31 + npc.id),
                                  companion: companion?.tier, night: npc.isNight)
        activeFight?.damageTakenFactor = damageTakenFactor
        activeFight?.cooldownFactor = cooldownFactor
        toast = "Встреча · \(npc.tier.title) — бей и отходи; дальше \(Self.cells(npc.tier.chaseRadius)) — сбежал"
    }

    func startActiveGuardian(_ tower: IslandTower) {
        activeTower = tower.id
        activeNPC = nil
        activeFight = ActiveFight(tier: .regular, hero: hero, heroHP: hp, heroMP: mp, seed: seed &+ UInt64(steps * 17 + tower.id),
                                  guardian: .init(title: tower.title, hp: tower.guardianHP, damageShare: tower.guardianDamageShare),
                                  companion: companion?.tier)
        activeFight?.damageTakenFactor = damageTakenFactor
        activeFight?.cooldownFactor = cooldownFactor
        toast = "Страж башни «\(tower.title)» — дальше \(Self.cells(ExploreRules.guardianLeash)) от башни — сбежал"
    }

    static func cells(_ value: Double) -> String {
        let text = value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "ru_RU")))
        return "\(text) клетки"
    }

    /// «Удар» в активном бою.
    func activeStrike() { activeFight?.strike(distance: activeDistance); syncActive() }

    /// Способность: в бою — по противнику (Рывок ещё и ускоряет), без боя — как на карте.
    func activeUse(_ skill: ExploreSkill) {
        guard activeFight != nil else { useOnMap(skill); return }
        guard activeFight?.use(skill, distance: activeDistance) == true else { return }
        if skill.ability == .dash { dashUntil = .now + 3 * skill.power }
        syncActive()
    }

    func syncActive() {
        guard let activeFight else { return }
        hp = activeFight.heroHP
        mp = activeFight.heroMP
    }

    /// Итог активного боя — как у пошаговой встречи.
    func finishActive() -> EncounterOutcome? {
        guard let fight = activeFight else { return nil }
        hp = fight.heroHP
        mp = fight.heroMP
        let outcome = fight.outcome
        switch outcome {
        case .won:
            wins += 1
            if let id = activeTower, let tower = island.towers.first(where: { $0.id == id }) {
                conqueredTowers.insert(id)
                let item = ExploreItem.allCases[(id + steps) % ExploreItem.allCases.count]
                toast = tower.isFinal ? "🏆 Архипелаг пройден — босс повержен"
                    : "Сундук «Epic: \(tower.title)»" + (addItem(item) ? " · \(item.title)" : " · сумка полна")
            } else {
                toast = "\(fight.opponentTitle) повержен"
                nightReward(activeNPC)
            }
        case .persuaded:
            persuaded += 1
            if let id = activeNPC, let npc = island.npcs.first(where: { $0.id == id }) { companion = npc }
            toast = "\(fight.tier.title) теперь спутник"
        case .fled:
            escapes += 1
            toast = "Вы оторвались"
        case .lost:
            defeats += 1
            hp = (hero.maxHP * ExploreRules.defeatHPShare).rounded()
            toast = "Вы без сил — очнулись в городе"
        case nil: break
        }
        activeFight = nil
        activeDistance = .infinity
        return outcome
    }

    /// Пауза кнопкой (16.11.2026).
    var isPaused = false
    /// Время стоит: пауза или открыта карта мира.
    var isFrozen: Bool { isPaused || isWorldMapOpen || merchantOpen != nil || showsAtlas }
    var exploredShare: Double { landCount == 0 ? 0 : Double(exploredLand) / Double(landCount) }

    /// Открыть клетки в радиусе обзора.
    func explore(around point: TilePoint, radius: Double) {
        let side = island.side, r = Int(radius.rounded(.up))
        for y in max(0, point.y - r)...min(side - 1, point.y + r) {
            for x in max(0, point.x - r)...min(side - 1, point.x + r) {
                let index = y * side + x
                guard !explored[index], hypot(Double(x - point.x), Double(y - point.y)) <= radius else { continue }
                explored[index] = true
                if island.terrain[index] != .water { exploredLand += 1 }
            }
        }
    }

    /// Мини-карта: перерисовывается только когда меняются сундуки, костры или корабли.
    @ObservationIgnored private var minimapCache: (key: String, image: CGImage?)?
    var minimapImage: CGImage? {
        let ships = ships.indices.filter { $0 != sailing }.map { self.ships[$0] }
        let key = "\(openedChests.count)-\(litCampfires.count)-\(ships.map { "\($0.x),\($0.y)" })-\(treasureSpot.map { "\($0.x),\($0.y)" } ?? "")-\(treasureFound)"
        if let minimapCache, minimapCache.key == key { return minimapCache.image }
        let image = ExploreRenderer.minimap(island, opened: openedChests, lit: litCampfires, ships: ships, treasure: treasureFound ? nil : treasureSpot)
        minimapCache = (key, image)
        return image
    }

    /// Дорога под героем (пешком).
    var roadHere: IslandRoad? { sailing == nil ? island.road(at: heroTile) : nil }
    var zoneHere: ClimateZone { island.zone(at: heroTile) }
    var weatherHere: Weather { island.weather(at: heroTile) }
    var clockText: String { String(format: "%02d:%02d", Int(clockHour) % 24, Int(clockHour * 60) % 60) }

    func addItem(_ item: ExploreItem) -> Bool {
        guard bagCount < ExploreRules.bagCap else { return false }
        bag[item, default: 0] += 1
        return true
    }

    func useItem(_ item: ExploreItem) {
        guard (bag[item] ?? 0) > 0, !inFight else { return }
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
                              guardian: .init(title: tower.title, hp: tower.guardianHP, damageShare: tower.guardianDamageShare))
        fight.damageTakenFactor = damageTakenFactor
        fight.cooldownFactor = cooldownFactor
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

    init(input: ExploreInput, hero: ExploreHero, attempt: Int, appearance: HeroAppearance?, accent: UInt32, mode: ExploreMode = .turnBased) {
        self.mode = mode
        self.input = input
        self.hero = hero
        self.seed = input.seed(attempt: attempt)
        let island = IslandGenerator.generate(input, seed: seed)
        self.island = island
        ground = ExploreGround(island: island)
        explored = [Bool](repeating: false, count: island.side * island.side)
        landCount = island.terrain.reduce(0) { $0 + ($1 == .water ? 0 : 1) }
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
        explore(around: island.start, radius: hero.vision)
    }

    static let mapCooldown: TimeInterval = 10

    func canUseOnMap(_ skill: ExploreSkill) -> Bool {
        guard skill.ability == .dash || skill.ability == .scout, !inFight, sailing == nil else { return false }
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
        // По дороге быстрее — по её износу (15A.2).
        let swamp = island.isSwamp(heroTile) ? ExploreRules.swampSpeedFactor : 1
        return hero.walkSpeed * ((dashUntil ?? .distantPast) > .now ? 2 : 1) * (roadHere?.wear.speedFactor ?? 1) * (1 + buff(.walk)) * swamp
    }
    /// Обзор: Разведка и факел — 15 клеток; маяк +3; ночью ×0,7 (14.5).
    var vision: Double {
        let now = Date.now
        if (scoutUntil ?? .distantPast) > now || (torchUntil ?? .distantPast) > now { return ExploreRules.torchVision }
        var value = hero.vision + ((lighthouseUntil ?? .distantPast) > now ? ExploreRules.lighthouseVisionBonus : 0) + buff(.custom) + (companionSkill == .scout ? ExploreRules.scoutCompanionVision : 0)
        if isNight { value *= ExploreRules.nightVisionFactor }
        return value
    }

    func startEncounter(npc: IslandNPC) {
        encounterNPC = npc.id
        encounterTower = nil
        var fight = Encounter(tier: npc.tier, hero: hero, heroHP: hp, heroMP: mp, seed: seed &+ UInt64(steps * 31 + npc.id), night: npc.isNight)
        fight.damageTakenFactor = damageTakenFactor
        fight.cooldownFactor = cooldownFactor
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
            nightReward(encounterNPC)
            // Страж повержен — башня взята, сундук Epic: предмет в сумку.
            if let id = encounterTower, let tower = island.towers.first(where: { $0.id == id }) {
                conqueredTowers.insert(id)
                let item = ExploreItem.allCases[(id + steps) % ExploreItem.allCases.count]
                toast = tower.isFinal ? "🏆 Архипелаг пройден — босс повержен"
                    : "Сундук «Epic: \(tower.title)»" + (addItem(item) ? " · \(item.title)" : " · сумка полна")
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

/// Где хранится режим игры (настройки, 16.11.2026).
enum ExploreModeSetting {
    static let key = "exploreMode"
    static var current: ExploreMode {
        UserDefaults.standard.string(forKey: key).flatMap(ExploreMode.init(rawValue:)) ?? .turnBased
    }
}
