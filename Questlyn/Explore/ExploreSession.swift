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
    var companionSkill: CompanionSkill? { companion.map { CompanionSkill.of($0) } }

    // MARK: 16 (18.11.2026): зал Чёрной башни и пираты

    /// Герой в зале башни.
    var inTower: Int?
    var encounterPirate: Int?
    @ObservationIgnored private var pirateRandom = ExploreRandom(0x9149_7E00)

    /// Непокорённая Чёрная башня рядом — «Войти в башню».
    var enterableTower: IslandTower? {
        guard sailing == nil, !inFight, inTower == nil, inCave == nil else { return nil }
        return island.towers.first { !conqueredTowers.contains($0.id) && $0.position.distance(to: heroTile) <= 2.5 }
    }

    func enterTower() {
        guard let tower = enterableTower else { return }
        inTower = tower.id
        toast = tower.isFinal ? "Финальная башня: босс ждёт у дальней стены" : "Чёрная башня «\(tower.title)»: босс у дальней стены"
    }

    /// Выйти из зала — герой снова у башни.
    func leaveTower() { inTower = nil }

    /// Пираты (16.2): с пушками — бой залпами, без пушек — абордаж.
    func startPirate(_ id: Int) {
        encounterPirate = id
        encounterNPC = nil
        encounterTower = nil
        var fight: Encounter
        if upgrades.contains(.cannons) {
            fight = Encounter(tier: .colleague, hero: hero, heroHP: hp, heroMP: mp, seed: seed &+ UInt64(steps * 19 + id),
                              guardian: .init(title: "Пираты", hp: ExploreRules.pirateHP, damageShare: ExploreRules.pirateDamageShare))
            fight.opponentName = "Пираты"
        } else {
            fight = Encounter(tier: .colleague, hero: hero, heroHP: hp, heroMP: mp, seed: seed &+ UInt64(steps * 19 + id))
            fight.opponentName = "Пираты — абордаж"
        }
        fight.damageTakenFactor = damageTakenFactor * (upgrades.contains(.hull) ? ExploreRules.hullDamageFactor : 1)
        fight.cooldownFactor = cooldownFactor
        if let companion { fight.companionAssist(tier: companion.tier) }
        encounter = fight
    }

    // MARK: 15F (17.11.2026): поручения Epic и главный квест «Путь по главам»

    var monsterWins = 0
    /// Взятые поручения: id → номер текущего шага; базовое число побед на начало шага.
    var errandStep: [Int: Int] = [:]
    var errandBaseline: [Int: Int] = [:]
    var errandsDone: Set<Int> = []
    var chaptersRewarded: Set<Int> = []
    var walkCompleted = false

    /// Взять поручение доски при входе в город.
    func takeErrand(cityId: Int) {
        guard let errand = island.errands.first(where: { $0.cityId == cityId }), errandStep[errand.id] == nil else { return }
        errandStep[errand.id] = 0
        errandBaseline[errand.id] = monsterWins
        toast = "Поручение Epic «\(errand.epicTitle)» · шаг 1: \(errandText(errand.steps[0]))"
    }

    func errandText(_ step: IslandErrand.Step) -> String {
        switch step.kind {
        case let .reachVillage(id): "дойти до деревни «\(island.villages.first { $0.id == id }?.name ?? "")»"
        case let .defeat(count): "победить \(count) монстров"
        case let .bring(chest): "принести к доске предмет из сундука «\(island.chests.first { $0.id == chest }?.title ?? "")»"
        case .tower: "взять Чёрную башню"
        }
    }

    /// Прогресс шага: сделано / нужно.
    func errandProgress(_ errand: IslandErrand) -> (done: Int, total: Int) {
        guard let index = errandStep[errand.id], errand.steps.indices.contains(index) else { return (1, 1) }
        switch errand.steps[index].kind {
        case let .reachVillage(id): return (visitedVillages.contains(id) ? 1 : 0, 1)
        case let .defeat(count): return (min(count, monsterWins - (errandBaseline[errand.id] ?? 0)), count)
        case let .bring(chest): return ((openedChests.contains(chest) ? 1 : 0) + (openedChests.contains(chest) && island.safeCity(at: heroTile)?.id == errand.cityId ? 1 : 0), 2)
        case let .tower(id): return (conqueredTowers.contains(id) ? 1 : 0, 1)
        }
    }

    /// Награда растёт: +15% HP и MP → доска → предмет → финал: 2 доски.
    private func errandReward(_ step: Int, final: Bool) -> String {
        if final { planks += ExploreRules.errandFinalPlanks; return "+\(ExploreRules.errandFinalPlanks) доски" }
        switch step {
        case 0:
            hp = min(maxHP, hp + maxHP * ExploreRules.errandHealShare)
            mp = min(maxMP, mp + maxMP * ExploreRules.errandHealShare)
            return "+\(Int(ExploreRules.errandHealShare * 100))% HP и MP"
        case 1:
            planks += ExploreRules.errandPlanks
            return "+\(ExploreRules.errandPlanks) доска"
        default:
            let item = ExploreItem.allCases[(step + steps) % ExploreItem.allCases.count]
            return addItem(item) ? item.title : "сумка полна"
        }
    }

    /// Шаги поручений и главного квеста — проверяются на каждом шаге героя.
    func settleErrands() {
        for errand in island.errands where errandStep[errand.id] != nil && !errandsDone.contains(errand.id) {
            let state = errandProgress(errand)
            guard state.done >= state.total, let index = errandStep[errand.id] else { continue }
            let final = index == errand.steps.count - 1
            let reward = errandReward(index, final: final)
            if final {
                errandsDone.insert(errand.id)
                toast = "Поручение «\(errand.epicTitle)» выполнено · \(reward)"
            } else {
                errandStep[errand.id] = index + 1
                errandBaseline[errand.id] = monsterWins
                toast = "Шаг «\(errand.steps[index].title)» · \(reward) · дальше: \(errandText(errand.steps[index + 1]))"
            }
        }
        settleMainQuest()
    }

    struct MainStep: Identifiable {
        let id: Int
        let title: String
        let detail: String
        let done: Bool
    }

    /// Главный квест «Путь по главам» (15F.2): корабль → главный город каждой главы и его поручение → финальная башня.
    var mainSteps: [MainStep] {
        var result: [MainStep] = []
        var previousDone = true
        func add(_ title: String, _ detail: String, _ done: Bool) {
            let ok = previousDone && done
            result.append(MainStep(id: result.count, title: title, detail: detail, done: ok))
            previousDone = ok
        }
        if hasShipQuest { add("Корабль", "Победить монстров стартового острова · \(shipQuestKills)/\(ExploreRules.shipQuestKills)", shipReady) }
        for region in island.regions {
            let title = island.regions.count > 1 ? "Глава «\(region.title)»" : "Остров"
            guard let city = island.mainCity(of: region) else { add(title, "Городов нет — глава пройдена", true); continue }
            let errand = island.errands.first { $0.cityId == city.id }
            let task = island.tasks.first { $0.cityId == city.id }
            let boardDone = errand.map { errandsDone.contains($0.id) } ?? task.map { doneTasks.contains($0.id) } ?? true
            var detail = "Главный город «\(city.name)»"
            if let errand { detail += errandStep[errand.id].map { " · поручение \($0 + (errandsDone.contains(errand.id) ? 1 : 0))/\(errand.steps.count)" } ?? " · поручение" }
            else if task != nil { detail += " · задание доски" }
            add(title, detail, visitedCities.contains(city.id) && boardDone)
        }
        if let tower = finalTower { add("Финальная башня", "Босс на последнем острове", conqueredTowers.contains(tower.id)) }
        return result
    }

    var mainCurrent: MainStep? { mainSteps.first { !$0.done } }

    private func settleMainQuest() {
        let steps = mainSteps
        let offset = hasShipQuest ? 1 : 0
        for (k, _) in island.regions.enumerated() where steps.indices.contains(k + offset) && steps[k + offset].done && !chaptersRewarded.contains(k) {
            chaptersRewarded.insert(k)
            planks += ExploreRules.chapterPlanks
            hp = maxHP
            mp = maxMP
            toast = "★ \(steps[k + offset].title) пройдена · +\(ExploreRules.chapterPlanks) доски, HP и MP полностью"
        }
        if !walkCompleted, let last = steps.last, last.done, finalTower != nil {
            walkCompleted = true
            toast = "🏆 Прогулка пройдена"
        }
    }

    // MARK: 15E (17.11.2026): один корабль, экипаж, доски и верфь, море

    /// Корабль получен (квест: 10 монстров на стартовом острове). Один остров — корабль не нужен.
    var shipReady = false
    var shipQuestKills = 0
    var hasShipQuest: Bool { !island.ships.isEmpty }
    var planks = 0
    var upgrades: Set<ShipUpgrade> = []
    /// Экипаж — до 2 спутников; на палубе не видны, их умения работают.
    var crew: [IslandNPC] = []
    var lootedWrecks: Set<Int> = []
    var traderGifts: Set<Int> = []
    var serpentDefeated = false
    var encounterSerpent = false
    @ObservationIgnored var serpentRamAt = Date.distantPast
    /// Где корабль стоял перед отплытием — туда он вернётся, если герой проиграет в море.
    var mooredAt: TilePoint?
    var shipyardOpen = false
    var crewOpen = false
    var traderOpen: IslandTrader?
    let currentTiles: Set<TilePoint>
    /// Города с верфью: столица и города, чья территория ближе 3 клеток к воде.
    let shipyardCities: Set<Int>

    var bagCap: Int { ExploreRules.bagCap + (upgrades.contains(.hold) ? ExploreRules.holdBagBonus : 0) }
    /// Умения спутника и экипажа вместе; одинаковые не складываются.
    var skills: [CompanionSkill] { ([companion] + crew.map(Optional.some)).compactMap { $0.map(CompanionSkill.of) } }
    func has(_ skill: CompanionSkill) -> Bool { skills.contains(skill) }

    var inStorm: Bool { sailing != nil && island.storms.contains { $0.contains(heroTile) } }
    var onCurrent: Bool { sailing != nil && currentTiles.contains(heroTile) }
    var nearbyShipyard: Bool {
        guard shipReady, sailing == nil, !inFight, let city = island.safeCity(at: heroTile) else { return false }
        return shipyardCities.contains(city.id)
    }
    /// У корабля (на берегу рядом) — окно «Экипаж».
    var nearShip: Bool { shipReady && sailing == nil && !inFight && ships.first.map { $0.distance(to: heroTile) <= ExploreRules.boardRadius + 1 } == true }
    var nearbyTrader: IslandTrader? {
        guard sailing != nil, !inFight else { return nil }
        return island.traders.first { $0.position.distance(to: heroTile) <= 2.5 }
    }

    func buy(_ upgrade: ShipUpgrade) {
        guard !upgrades.contains(upgrade), planks >= upgrade.planks else { return }
        planks -= upgrade.planks
        upgrades.insert(upgrade)
        toast = "Верфь: \(upgrade.title) — \(upgrade.summary)"
    }

    /// Назначить спутника в экипаж (есть свободное место).
    func assignCrew() {
        guard let companion, crew.count < ExploreRules.crewCap else { return }
        crew.append(companion)
        self.companion = nil
        toast = "\(companion.title) теперь в экипаже · \(CompanionSkill.of(companion).summary)"
    }

    /// Поменять спутника и члена экипажа местами.
    func swapCrew(_ index: Int) {
        guard crew.indices.contains(index), let companion else { return }
        let member = crew[index]
        crew[index] = companion
        self.companion = member
        toast = "\(member.title) идёт с тобой, \(companion.title) — на корабле"
    }

    func takeGift(_ trader: IslandTrader) {
        guard !traderGifts.contains(trader.id) else { return }
        traderGifts.insert(trader.id)
        planks += 1
        toast = "Встречный корабль: доска в подарок"
    }

    func loot(_ wreck: IslandWreck) {
        guard !lootedWrecks.contains(wreck.id) else { return }
        lootedWrecks.insert(wreck.id)
        planks += wreck.planks
        var text = "Обломки: +\(wreck.planks) \(wreck.planks == 1 ? "доска" : "доски")"
        if let item = wreck.item { text += addItem(item) ? " · \(item.title)" : " · сумка полна" }
        toast = text
    }

    /// Победа над монстром стартового острова — шаг квеста «Корабль».
    func registerWin(_ npcId: Int?) {
        if let npcId, island.npcs.first(where: { $0.id == npcId })?.monster != nil { monsterWins += 1 }
        guard hasShipQuest, !shipReady, let npcId, let npc = island.npcs.first(where: { $0.id == npcId }), npc.monster != nil,
              island.regions.first?.contains(npc.home) == true else { return }
        shipQuestKills += 1
        if shipQuestKills >= ExploreRules.shipQuestKills {
            shipReady = true
            toast = "⛵ Корабль готов — у причала стартового острова"
        }
    }

    /// Поражение: герой очнётся на острове, где пришвартован корабль; проигрыш в море — корабль вернётся к причалу.
    func defeatRespawn() -> TilePoint {
        if let index = sailing {
            if let mooredAt { ships[index] = mooredAt }
            sailing = nil
        }
        guard shipReady, let ship = ships.first, let landing = island.landing(near: ship) else { return island.start }
        return landing
    }

    /// Морской змей (15E.1): с пушками — бой; без пушек — таран раз в 2 с.
    func startSerpent() {
        guard let serpent = island.serpent, !serpentDefeated else { return }
        encounterSerpent = true
        encounterNPC = nil
        encounterTower = nil
        var fight = Encounter(tier: .regular, hero: hero, heroHP: hp, heroMP: mp, seed: seed &+ UInt64(steps * 13),
                              guardian: .init(title: serpent.title, hp: serpent.hp, damageShare: ExploreRules.serpentDamageShare))
        fight.opponentName = "Морской змей"
        fight.damageTakenFactor = damageTakenFactor * (upgrades.contains(.hull) ? ExploreRules.hullDamageFactor : 1)
        fight.cooldownFactor = cooldownFactor
        if let companion { fight.companionAssist(tier: companion.tier) }
        encounter = fight
    }

    func serpentRam() {
        guard Date.now.timeIntervalSince(serpentRamAt) >= ExploreRules.serpentRamSeconds else { return }
        serpentRamAt = .now
        let damage = maxHP * ExploreRules.serpentRamShare * (upgrades.contains(.hull) ? ExploreRules.hullDamageFactor : 1)
        hp = max(1, hp - damage)
        toast = "Змей бьёт по кораблю: −\(Int(damage.rounded())) HP · нужны пушки (верфь)"
    }
    /// Навыки в бою (15H): «Уговорить» убран — в бою только монстры и стражи, людей уговаривают в диалоге.
    var fightSkills: [ExploreSkill] { hero.skills.filter { $0.ability != .persuade } }

    // MARK: 15H (17.11.2026): диалог с мирными NPC, монстры, умения легенд

    /// Мирный NPC рядом — кнопка «Поговорить» (сцена обновляет каждый кадр).
    var talkCandidate: Int?
    /// Открытый диалог — игра на паузе.
    var talkNPC: IslandNPC?
    /// После неудачи — повтор не раньше этого времени.
    var talkRetryAt: [Int: Date] = [:]
    @ObservationIgnored private var talkRandom = ExploreRandom(0x7A1C)
    /// Легенды, ставшие спутниками за прогулку — в итоги.
    var recruitedLegends: [IslandNPC] = []

    func canTalk(_ npc: IslandNPC) -> Bool {
        npc.isPeaceful && npc.id != companion?.id && (talkRetryAt[npc.id] ?? .distantPast) <= .now
    }

    func talkChance(_ npc: IslandNPC, help: Bool) -> Double { npc.talkChance(charisma: hero.level(.charisma), help: help) }

    /// Ответ в диалоге: удалось — спутник; нет — повтор через минуту.
    func talk(_ npc: IslandNPC, help: Bool) {
        guard canTalk(npc), !help || mp >= npc.talkHelpMP else { return }
        if help { mp -= npc.talkHelpMP }
        if talkRandom.unit() < talkChance(npc, help: help) {
            persuaded += 1
            companion = npc
            if npc.legend != nil { recruitedLegends.append(npc) }
            toast = "\(npc.title) теперь спутник · \(CompanionSkill.of(npc).summary)"
        } else {
            talkRetryAt[npc.id] = .now + ExploreRules.talkRetrySeconds
            toast = "Не удалось уговорить — попробуй через минуту"
        }
        talkNPC = nil
    }

    /// Мастер-легенда: HP и MP героя +10%.
    var maxHP: Double { hero.maxHP * (has(.legend(.master)) ? ExploreRules.masterVitalsFactor : 1) }
    var maxMP: Double { hero.maxMP * (has(.legend(.master)) ? ExploreRules.masterVitalsFactor : 1) }

    /// Бой с монстром: имя, ночь, умения легенды-спутника.
    private func prepare(_ fight: inout Encounter, _ npc: IslandNPC) {
        fight.opponentName = npc.title
        fight.heroDamageFactor = has(.legend(.warrior)) ? ExploreRules.warriorDamageFactor : 1
        fight.firstStrikeFactor = has(.legend(.assassin)) ? ExploreRules.assassinFirstStrike : 1
    }
    private func prepare(_ fight: inout ActiveFight, _ npc: IslandNPC) {
        fight.opponentName = npc.title
        fight.heroDamageFactor = has(.legend(.warrior)) ? ExploreRules.warriorDamageFactor : 1
        fight.firstStrikeFactor = has(.legend(.assassin)) ? ExploreRules.assassinFirstStrike : 1
    }
    /// Ночью монстры сильнее (правило 15D.3 перешло на монстров).
    func nightFight(_ npc: IslandNPC) -> Bool { isNight && npc.monster != nil }

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
        guard (storage[item] ?? 0) > 0, bagCount < bagCap else { return }
        storage[item, default: 0] -= 1
        bag[item, default: 0] += 1
    }

    /// Монстр повержен (15H) — предмет в сумку.
    private func nightReward(_ npcId: Int?) {
        guard let npcId, let npc = island.npcs.first(where: { $0.id == npcId }), npc.monster != nil else { return }
        let item = ExploreItem.allCases[(npcId + steps) % ExploreItem.allCases.count]
        toast = "\(npc.title) повержен" + (addItem(item) ? " · \(item.title)" : " · сумка полна")
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
        hp = min(maxHP, hp + maxHP * ExploreRules.treasureRestoreShare)
        mp = min(maxMP, mp + maxMP * ExploreRules.treasureRestoreShare)
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
                                  companion: companion?.tier, night: nightFight(npc))
        activeFight?.damageTakenFactor = damageTakenFactor
        activeFight?.cooldownFactor = cooldownFactor
        if var fight = activeFight { prepare(&fight, npc); activeFight = fight }
        toast = "\(npc.title) — бей и отходи; дальше \(Self.cells(npc.tier.chaseRadius)) — сбежал"
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
                registerWin(activeNPC)
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
            hp = (maxHP * ExploreRules.defeatHPShare).rounded()
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
    var isFrozen: Bool { encounter != nil && inTower != nil || isPaused || isWorldMapOpen || merchantOpen != nil || showsAtlas || talkNPC != nil || shipyardOpen || crewOpen || traderOpen != nil }
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
        let image = ExploreRenderer.isoMinimap(island, opened: openedChests, lit: litCampfires, ships: ships, treasure: treasureFound ? nil : treasureSpot)
        minimapCache = (key, image)
        return image
    }

    /// Карта мира с туманом: перерисовывается, когда открыто ещё ~1% суши, — окно карты открывается сразу, без пустого кадра.
    @ObservationIgnored private var worldMapCache: (key: Int, image: CGImage?)?
    var worldMapImage: CGImage? {
        let key = exploredLand / max(1, landCount / 100)
        if let worldMapCache, worldMapCache.key == key { return worldMapCache.image }
        let image = ExploreRenderer.worldMap(island, explored: explored)
        worldMapCache = (key, image)
        return image
    }

    /// Дорога под героем (пешком).
    var roadHere: IslandRoad? { sailing == nil ? island.road(at: heroTile) : nil }
    var zoneHere: ClimateZone { island.zone(at: heroTile) }
    var weatherHere: Weather { island.weather(at: heroTile) }
    var clockText: String { String(format: "%02d:%02d", Int(clockHour) % 24, Int(clockHour * 60) % 60) }

    func addItem(_ item: ExploreItem) -> Bool {
        guard bagCount < bagCap else { return false }
        bag[item, default: 0] += 1
        return true
    }

    func useItem(_ item: ExploreItem) {
        guard (bag[item] ?? 0) > 0, !inFight else { return }
        bag[item, default: 0] -= 1
        switch item {
        case .potionHP: hp = min(maxHP, hp + maxHP * ExploreRules.potionShare)
        case .potionMP: mp = min(maxMP, mp + maxMP * ExploreRules.potionShare)
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
            hp = min(maxHP, hp + maxHP * ExploreRules.taskRewardShare)
            mp = min(maxMP, mp + maxMP * ExploreRules.taskRewardShare)
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
        guard sailing == nil, encounter == nil, shipReady else { return nil }
        return ships.indices.min { ships[$0].distance(to: heroTile) < ships[$1].distance(to: heroTile) }
            .flatMap { ships[$0].distance(to: heroTile) <= ExploreRules.boardRadius ? $0 : nil }
    }

    /// Клетка суши рядом с кораблём — «Сойти на берег» доступна.
    var landingTile: TilePoint? {
        guard sailing != nil else { return nil }
        return island.landing(near: heroTile)
    }

    init(input: ExploreInput, hero: ExploreHero, attempt: Int, appearance: HeroAppearance?, accent: UInt32, mode: ExploreMode = .turnBased,
         prebuilt: Island? = nil) {
        self.mode = mode
        self.input = input
        self.hero = hero
        self.seed = input.seed(attempt: attempt)
        // 16.3: большой мир (до 6 месяцев) строится в фоне и приходит готовым.
        let island = prebuilt ?? IslandGenerator.generate(input, seed: seed)
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
        currentTiles = Set(island.currents.flatMap(\.tiles))
        shipyardCities = Set(island.cities.filter { city in
            city.isCapital || (-(city.radius + ExploreRules.shipyardCoast)...(city.radius + ExploreRules.shipyardCoast)).contains { dy in
                (-(city.radius + ExploreRules.shipyardCoast)...(city.radius + ExploreRules.shipyardCoast)).contains { dx in
                    let point = TilePoint(city.center.x + dx, city.center.y + dy)
                    return island.terrain(at: point) == .water && island.cities.contains { $0.id == city.id }
                        && hypot(Double(dx), Double(dy)) <= Double(city.radius + ExploreRules.shipyardCoast)
                }
            }
        }.map(\.id))
        if island.ships.isEmpty { shipReady = false }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: .now)
        clockHour = Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
        if let region = island.region(at: island.start) { visitedRegions.insert(region.id) }
        explore(around: island.start, radius: hero.vision)
    }

    static let mapCooldown: TimeInterval = 10

    func canUseOnMap(_ skill: ExploreSkill) -> Bool {
        guard skill.ability == .dash || skill.ability == .scout, !inFight, sailing == nil else { return false }
        if let until = mapCooldownUntil[skill.ability], until > .now { return false }
        return mp >= (skill.ability.mpShare * maxMP).rounded()
    }

    /// Рывок — ускорение ×2 на 3·m с; Разведка — обзор 15 клеток на 10 с (09, раздел 6).
    func useOnMap(_ skill: ExploreSkill) {
        guard canUseOnMap(skill) else { return }
        mp -= (skill.ability.mpShare * maxMP).rounded()
        mapCooldownUntil[skill.ability] = .now + Self.mapCooldown
        switch skill.ability {
        case .dash: dashUntil = .now + 3 * skill.power
        case .scout: scoutUntil = .now + 10
        default: break
        }
    }

    var speed: Double {
        if sailing != nil {
            // 15E: паруса, течение привычки, шторм.
            return hero.walkSpeed * ExploreRules.sailSpeedFactor * (upgrades.contains(.sails) ? ExploreRules.sailsSpeedFactor : 1)
                * (onCurrent ? ExploreRules.currentSpeedFactor : 1) * (inStorm ? ExploreRules.stormSpeedFactor : 1)
        }
        // По дороге быстрее — по её износу (15A.2).
        let swamp = island.isSwamp(heroTile) ? ExploreRules.swampSpeedFactor : 1
        let baller = has(.legend(.baller)) ? ExploreRules.ballerSpeedFactor : 1
        return hero.walkSpeed * ((dashUntil ?? .distantPast) > .now ? 2 : 1) * (roadHere?.wear.speedFactor ?? 1) * (1 + buff(.walk)) * swamp * baller
    }
    /// Обзор: Разведка и факел — 15 клеток; маяк +3; ночью ×0,7 (14.5).
    var vision: Double {
        let now = Date.now
        if (scoutUntil ?? .distantPast) > now || (torchUntil ?? .distantPast) > now { return ExploreRules.torchVision }
        var value = hero.vision + ((lighthouseUntil ?? .distantPast) > now ? ExploreRules.lighthouseVisionBonus : 0) + buff(.custom) + (has(.scout) ? ExploreRules.scoutCompanionVision : 0)
            + (has(.legend(.archer)) ? ExploreRules.archerVision : 0)
            + (sailing != nil && upgrades.contains(.mast) ? ExploreRules.mastSeaVision : 0)
        if isNight { value *= ExploreRules.nightVisionFactor }
        return value
    }

    func startEncounter(npc: IslandNPC) {
        encounterNPC = npc.id
        encounterTower = nil
        var fight = Encounter(tier: npc.tier, hero: hero, heroHP: hp, heroMP: mp, seed: seed &+ UInt64(steps * 31 + npc.id), night: nightFight(npc))
        prepare(&fight, npc)
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
            registerWin(encounterNPC)
            if encounterPirate != nil {
                planks += ExploreRules.piratePlanks
                var text = "🏴‍☠️ Пираты отбиты · +\(ExploreRules.piratePlanks) доски"
                if pirateRandom.unit() < ExploreRules.pirateItemChance {
                    let item = ExploreItem.allCases[pirateRandom.int(ExploreItem.allCases.count)]
                    text += addItem(item) ? " · \(item.title)" : " · сумка полна"
                }
                toast = text
            }
            if encounterSerpent, let serpent = island.serpent {
                serpentDefeated = true
                planks += ExploreRules.serpentPlanks
                let item = ExploreItem.allCases[steps % ExploreItem.allCases.count]
                toast = "🐉 Морской змей «\(serpent.title)» повержен · +\(ExploreRules.serpentPlanks) доски" + (addItem(item) ? " · \(item.title)" : "")
            }
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
            hp = (maxHP * ExploreRules.defeatHPShare).rounded()
        case nil: break
        }
        self.encounter = nil
        encounterTower = nil
        encounterSerpent = false
        encounterPirate = nil
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
