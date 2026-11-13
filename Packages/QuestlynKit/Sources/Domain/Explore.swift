import Foundation

// «Побродить» (этап 8B): мини-игра на острове из событий за прошлые даты. Песочница — ничего не сохраняет.
// Все числа — в `ExploreRules` (Product/09_EXPLORE_RULES.md, Рабочая гипотеза).

// MARK: - Случайность по зерну

/// Детерминированный генератор: тот же диапазон и зерно — тот же остров и те же броски.
public struct ExploreRandom: Sendable {
    private var state: UInt64
    public init(_ seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    public mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
    /// 0..<1.
    public mutating func unit() -> Double { Double(next() % 1_000_000) / 1_000_000 }
    public mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(max(bound, 1))) }
    /// Разброс ±share вокруг 1.
    public mutating func spread(_ share: Double) -> Double { 1 + (unit() * 2 - 1) * share }
}

// MARK: - Правила (09)

public enum ExploreRules {
    public static let maxDays = 92
    public static let maxSkills = 3

    // Остров (09, раздел 1–2).
    public static func islandSize(days: Int) -> IslandSize {
        switch days {
        case ...14: .small
        case 15...42: .medium
        default: .large
        }
    }
    public static let citySafeRadius = 3
    public static let cityMinDistance = 8
    public static let villageMinDistance = 3
    public static let npcMinDistanceFromStart = 6
    public static let chestCap = 30
    /// Архипелаг (12B, 12.11.2026): вода между островами и по краю мира, клеток.
    public static let islandGap = 8
    public static let worldMargin = 3
    /// Сесть на корабль — в этом радиусе от него, клеток.
    public static let boardRadius = 2.0
    /// Гавань: NPC не живут ближе к кораблю (бродят ±5 клеток, погоня — до 3,5).
    public static let harbourRadius = 9.0
    /// Корабль быстрее шага вдвое; плавание не тратит HP и MP.
    public static let sailSpeedFactor = 2.0

    // Герой (09, раздел 4).
    public static func walkSpeed(endurance: Int) -> Double { min(4.5, 3 + 0.1 * Double(endurance)) }
    public static func strike(strength: Int) -> Double { 8 + 2 * Double(strength) }
    public static func vision(intelligence: Int) -> Double { min(12, 5 + 0.5 * Double(intelligence)) }
    public static let hitSpread = 0.2
    public static func escapeChance(mentality: Int, tier: NPCTier) -> Double {
        min(0.9, max(0.2, 0.5 + 0.04 * Double(mentality) - escapePenaltyPerTier * Double(tier.rawValue - 1)))
    }
    public static let escapePenaltyPerTier = 0.08
    public static func cooldown(focus: Int, discipline: Int) -> Int {
        let sum = focus + discipline
        return 3 - (sum >= 20 ? 2 : sum >= 10 ? 1 : 0)
    }

    // Восстановление (09, раздел 5).
    public static let cityRestorePerSecond = 0.10
    public static let campfireShare = 0.40
    public static let defeatHPShare = 0.5

    /// Множитель силы способности по XP навыка (09, раздел 6).
    public static func power(skillXP: Double) -> Double {
        switch skillXP {
        case ..<50: 1.0
        case ..<200: 1.25
        case ..<500: 1.5
        default: 2.0
        }
    }
}

public enum IslandSize: String, Sendable, CaseIterable {
    case small, medium, large

    public var tiles: Int { switch self { case .small: 48; case .medium: 72; case .large: 96 } }
    public var npcCap: Int { switch self { case .small: 15; case .medium: 25; case .large: 40 } }
    public var cityCap: Int { switch self { case .small: 6; case .medium: 10; case .large: 14 } }
    public var villageCap: Int { switch self { case .small: 10; case .medium: 20; case .large: 30 } }
    public var title: String { switch self { case .small: "Малый остров"; case .medium: "Средний остров"; case .large: "Большой остров" } }
}

/// Тип NPC по числу событий с этим человеком (09, раздел 3).
public enum NPCTier: Int, Sendable, CaseIterable, Comparable {
    case acquaintance = 1, colleague, regular

    public static func of(meetings: Int) -> NPCTier { meetings >= 5 ? .regular : meetings >= 2 ? .colleague : .acquaintance }
    public static func < (lhs: NPCTier, rhs: NPCTier) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String { switch self { case .acquaintance: "Знакомый"; case .colleague: "Коллега"; case .regular: "Постоянный" } }
    public var hp: Double { switch self { case .acquaintance: 20; case .colleague: 40; case .regular: 70 } }
    /// Урон за ход — доля HPmax героя.
    public var damageShare: Double { switch self { case .acquaintance: 0.06; case .colleague: 0.09; case .regular: 0.13 } }
    public var chaseRadius: Double { Double(rawValue) + 1.5 }
    public static let wanderSpeed = 1.5
    public static let chaseSpeed = 2.5
    /// После встречи NPC не преследует, секунд.
    public static let calmAfterEncounter = 10.0
}

// MARK: - Способности навыков (09, раздел 6)

public enum ExploreAbility: String, Sendable, CaseIterable {
    case powerStrike, dash, teamMove, scout, focus, persuade, distract

    public var title: String {
        switch self {
        case .powerStrike: "Мощный удар"
        case .dash: "Рывок"
        case .teamMove: "Командный приём"
        case .scout: "Разведка"
        case .focus: "Концентрация"
        case .persuade: "Уговорить"
        case .distract: "Отвлечь"
        }
    }

    public var summary: String {
        switch self {
        case .powerStrike: "сильный удар"
        case .dash: "побег без броска, на карте — ускорение"
        case .teamMove: "удар и NPC пропускает ход"
        case .scout: "следующий удар сильнее, на карте — обзор"
        case .focus: "урон по герою вдвое меньше"
        case .persuade: "NPC станет мирным"
        case .distract: "NPC пропускает ходы"
        }
    }

    /// Стоимость — доля MPmax.
    public var mpShare: Double {
        switch self {
        case .dash, .scout: 0.08
        case .teamMove: 0.12
        case .powerStrike, .focus, .persuade, .distract: 0.10
        }
    }

    /// По привязанному виду активности (8.6), иначе — по основному атрибуту профессии навыка.
    public static func of(activityTemplateId: String?, professionMain: Attribute?) -> ExploreAbility? {
        switch activityTemplateId {
        case "strength": return .powerStrike
        case "cardio", "walk": return .dash
        case "team-sport": return .teamMove
        case "study": return .scout
        case "deep-work", "meditation": return .focus
        case "social": return .persuade
        case "creative": return .distract
        default: break
        }
        switch professionMain {
        case .strength: return .powerStrike
        case .endurance: return .dash
        case .intelligence: return .scout
        case .mentality: return .focus
        case .charisma: return .persuade
        default: return nil
        }
    }
}

/// Навык, взятый в дорогу.
public struct ExploreSkill: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var ability: ExploreAbility
    /// Множитель силы по XP навыка.
    public var power: Double

    public init(id: UUID, title: String, ability: ExploreAbility, skillXP: Double) {
        self.id = id
        self.title = title
        self.ability = ability
        self.power = ExploreRules.power(skillXP: skillXP)
    }
}

/// Герой на старте прогулки: текущие уровни, HP и MP (песочница — настоящие не меняются).
public struct ExploreHero: Hashable, Sendable {
    public var levels: [Attribute: Int]
    public var hp: Double
    public var maxHP: Double
    public var mp: Double
    public var maxMP: Double
    public var rankLetter: String
    public var skills: [ExploreSkill]

    public init(levels: [Attribute: Int], hp: Double, maxHP: Double, mp: Double, maxMP: Double, rankLetter: String, skills: [ExploreSkill]) {
        self.levels = levels
        self.hp = hp
        self.maxHP = maxHP
        self.mp = mp
        self.maxMP = maxMP
        self.rankLetter = rankLetter
        self.skills = Array(skills.prefix(ExploreRules.maxSkills))
    }

    public func level(_ attribute: Attribute) -> Int { levels[attribute] ?? 0 }
    public var walkSpeed: Double { ExploreRules.walkSpeed(endurance: level(.endurance)) }
    public var vision: Double { ExploreRules.vision(intelligence: level(.intelligence)) }
    public var cooldown: Int { ExploreRules.cooldown(focus: level(.focus), discipline: level(.discipline)) }
}

// MARK: - Входные данные

public struct ExploreEvent: Hashable, Sendable {
    public var title: String
    public var start: Date
    public var minutes: Int
    /// Хеши адресов участников без самого пользователя (имена не хранятся).
    public var attendeeKeys: [String]

    public init(title: String, start: Date, minutes: Int, attendeeKeys: [String]) {
        self.title = title
        self.start = start
        self.minutes = minutes
        self.attendeeKeys = attendeeKeys
    }
}

public struct ExploreInput: Sendable {
    public var first: LocalDate
    public var last: LocalDate
    public var events: [ExploreEvent]
    /// Квесты диапазона: название, приоритет и дата (по ней — остров месяца; без даты — последний месяц).
    public var quests: [(title: String, priority: QuestPriority, date: LocalDate?)]
    /// Качество ночей диапазона (Q из 08), по дню пробуждения.
    public var nights: [LocalDate: Double]
    /// Последняя отметка настроения недели — по понедельнику недели.
    public var weekMoods: [LocalDate: Mood]
    public var hasCalendar: Bool
    /// Пояс для дат событий: по нему событие попадает на остров своего месяца.
    public var timeZone: TimeZone

    public init(first: LocalDate, last: LocalDate, events: [ExploreEvent], quests: [(title: String, priority: QuestPriority, date: LocalDate?)],
                nights: [LocalDate: Double], weekMoods: [LocalDate: Mood], hasCalendar: Bool, timeZone: TimeZone = .current) {
        self.timeZone = timeZone
        self.first = first
        self.last = last
        self.events = events
        self.quests = quests
        self.nights = nights
        self.weekMoods = weekMoods
        self.hasCalendar = hasCalendar
    }

    public var days: Int { first.days(until: last) + 1 }

    /// Только прошлые даты, не больше 92 дней (02, 11.11.2026).
    public static func isValidRange(first: LocalDate, last: LocalDate, today: LocalDate) -> Bool {
        first <= last && last < today && first.days(until: last) + 1 <= ExploreRules.maxDays
    }

    /// Месяцы диапазона (12B): каждый — отдельный остров, края обрезаны диапазоном.
    public var months: [(first: LocalDate, last: LocalDate)] {
        var result: [(first: LocalDate, last: LocalDate)] = []
        var day = first
        while day <= last {
            let nextMonth = day.month == 12 ? LocalDate(year: day.year + 1, month: 1, day: 1) : LocalDate(year: day.year, month: day.month + 1, day: 1)
            let end = min(last, nextMonth.adding(days: -1))
            result.append((day, end))
            day = end.adding(days: 1)
        }
        return result
    }

    /// Часть диапазона — данные одного месяца.
    func slice(first: LocalDate, last: LocalDate, isLastMonth: Bool) -> ExploreInput {
        ExploreInput(first: first, last: last,
                     events: events.filter { let day = LocalDate($0.start, timeZone: timeZone); return day >= first && day <= last },
                     quests: quests.filter { quest in quest.date.map { $0 >= first && $0 <= last } ?? isLastMonth },
                     nights: nights.filter { $0.key >= first && $0.key <= last },
                     weekMoods: weekMoods, hasCalendar: hasCalendar, timeZone: timeZone)
    }

    /// Зерно из диапазона; «Другой остров» прибавляет номер попытки.
    public func seed(attempt: Int) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in "\(first)|\(last)|\(attempt)".utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return hash
    }
}

// MARK: - Остров

public struct TilePoint: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    public func distance(to other: TilePoint) -> Double { hypot(Double(x - other.x), Double(y - other.y)) }
}

public enum Terrain: UInt8, Sendable { case water, sand, grass, forest }

public struct IslandCity: Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var center: TilePoint
    public var events: Int
    /// 3, 6 или 10 домов; у деревни — 1.
    public var houses: Int
    public var isCity: Bool
}

public struct IslandNPC: Hashable, Sendable, Identifiable {
    public var id: Int
    public var tier: NPCTier
    public var home: TilePoint
    public var meetings: Int
}

public struct IslandChest: Hashable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var position: TilePoint
}

public struct IslandCampfire: Hashable, Sendable, Identifiable {
    public var id: Int
    public var quality: Double
    public var position: TilePoint
}

/// Остров месяца в архипелаге (12B): квадрат `side`×`side` клеток от `origin`.
public struct IslandRegion: Hashable, Sendable, Identifiable {
    public var id: Int
    public var first: LocalDate
    public var last: LocalDate
    public var size: IslandSize
    public var origin: TilePoint
    public var side: Int

    public var days: Int { first.days(until: last) + 1 }
    public var center: TilePoint { TilePoint(origin.x + side / 2, origin.y + side / 2) }
    public func contains(_ point: TilePoint) -> Bool {
        point.x >= origin.x && point.y >= origin.y && point.x < origin.x + side && point.y < origin.y + side
    }
    public var monthTitle: String {
        ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"][first.month - 1]
    }
}

/// Корабль (12B): стоит на воде у берега; одна модель — фрегат.
public struct IslandShip: Hashable, Sendable, Identifiable {
    public var id: Int
    /// Остров, у которого корабль стоял в начале прогулки.
    public var region: Int
    public var position: TilePoint
}

public struct Island: Sendable {
    /// Размер самого большого острова.
    public var size: IslandSize
    /// Сторона мира в клетках: остров или весь архипелаг.
    public var side: Int
    public var terrain: [Terrain]
    public var cities: [IslandCity]
    public var villages: [IslandCity]
    public var npcs: [IslandNPC]
    public var chests: [IslandChest]
    public var campfires: [IslandCampfire]
    /// Погода полос с запада на восток — по неделям диапазона.
    public var weatherBands: [Weather]
    public var start: TilePoint
    /// Острова-месяцы (12B); у одного месяца — один остров на весь мир.
    public var regions: [IslandRegion] = []
    /// Корабли — только когда островов больше одного.
    public var ships: [IslandShip] = []

    init(size: IslandSize, side: Int? = nil, terrain: [Terrain], cities: [IslandCity], villages: [IslandCity], npcs: [IslandNPC],
         chests: [IslandChest], campfires: [IslandCampfire], weatherBands: [Weather], start: TilePoint) {
        self.size = size
        self.side = side ?? size.tiles
        self.terrain = terrain
        self.cities = cities
        self.villages = villages
        self.npcs = npcs
        self.chests = chests
        self.campfires = campfires
        self.weatherBands = weatherBands
        self.start = start
    }

    /// Остров месяца под клеткой суши.
    public func region(at point: TilePoint) -> IslandRegion? {
        guard isLand(point) else { return nil }
        return regions.first { $0.contains(point) }
    }

    /// Клетка суши рядом с кораблём — куда сойти на берег (сначала по сторонам, потом по диагонали).
    public func landing(near point: TilePoint) -> TilePoint? {
        let around = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
        return around.map { TilePoint(point.x + $0.0, point.y + $0.1) }.first { isLand($0) }
    }

    /// Путь корабля по воде (8 направлений, BFS; углы суши не срезает). nil — недостижимо.
    public func seaPath(from: TilePoint, to: TilePoint) -> [TilePoint]? {
        guard !isLand(from), !isLand(to), from.x >= 0, from.y >= 0, to.x >= 0, to.y >= 0,
              from.x < side, from.y < side, to.x < side, to.y < side else { return nil }
        if from == to { return [from] }
        var previous = [Int](repeating: -1, count: side * side)
        let startIndex = from.y * side + from.x, goalIndex = to.y * side + to.x
        previous[startIndex] = startIndex
        var queue = [startIndex], head = 0
        let steps = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
        while head < queue.count {
            let current = queue[head]; head += 1
            if current == goalIndex { break }
            let cx = current % side, cy = current / side
            for (dx, dy) in steps {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, ny >= 0, nx < side, ny < side else { continue }
                if dx != 0, dy != 0, isLand(TilePoint(cx + dx, cy)) || isLand(TilePoint(cx, cy + dy)) { continue }
                let next = ny * side + nx
                guard previous[next] == -1, terrain[next] == .water else { continue }
                previous[next] = current
                queue.append(next)
            }
        }
        guard previous[goalIndex] != -1 else { return nil }
        var result: [TilePoint] = []
        var index = goalIndex
        while index != startIndex { result.append(TilePoint(index % side, index / side)); index = previous[index] }
        result.append(from)
        return result.reversed()
    }

    public func terrain(at point: TilePoint) -> Terrain {
        guard point.x >= 0, point.y >= 0, point.x < side, point.y < side else { return .water }
        return terrain[point.y * side + point.x]
    }
    public func isLand(_ point: TilePoint) -> Bool { terrain(at: point) != .water }

    /// Безопасная зона: в радиусе от центра города (деревни — не безопасны).
    public func safeCity(at point: TilePoint) -> IslandCity? {
        cities.first { $0.center.distance(to: point) <= Double(ExploreRules.citySafeRadius) }
    }

    public func weather(atX x: Int) -> Weather {
        guard !weatherBands.isEmpty else { return .clear }
        return weatherBands[min(weatherBands.count - 1, max(0, x * weatherBands.count / side))]
    }

    /// Путь по суше (8 направлений, BFS). nil — недостижимо.
    public func path(from: TilePoint, to: TilePoint) -> [TilePoint]? {
        guard isLand(from), isLand(to) else { return nil }
        if from == to { return [from] }
        var previous = [Int](repeating: -1, count: side * side)
        let startIndex = from.y * side + from.x, goalIndex = to.y * side + to.x
        previous[startIndex] = startIndex
        var queue = [startIndex], head = 0
        let steps = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
        while head < queue.count {
            let current = queue[head]; head += 1
            if current == goalIndex { break }
            let cx = current % side, cy = current / side
            for (dx, dy) in steps {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, ny >= 0, nx < side, ny < side else { continue }
                // По диагонали — только если обе соседние клетки — суша (не срезаем углы через воду).
                if dx != 0, dy != 0, !(isLand(TilePoint(cx + dx, cy)) && isLand(TilePoint(cx, cy + dy))) { continue }
                let next = ny * side + nx
                guard previous[next] == -1, terrain[next] != .water else { continue }
                previous[next] = current
                queue.append(next)
            }
        }
        guard previous[goalIndex] != -1 else { return nil }
        var result: [TilePoint] = []
        var index = goalIndex
        while index != startIndex { result.append(TilePoint(index % side, index / side)); index = previous[index] }
        result.append(from)
        return result.reversed()
    }
}

public enum IslandGenerator {
    /// Архипелаг (12B): остров на каждый месяц диапазона, по порядку месяцев сверху вниз со сдвигом; старт — на острове
    /// последнего месяца. Один месяц — один остров, как раньше, без кораблей.
    public static func generate(_ input: ExploreInput, seed: UInt64) -> Island {
        let months = input.months
        let parts = months.enumerated().map { index, month in
            single(input.slice(first: month.first, last: month.last, isLastMonth: index == months.count - 1),
                   seed: index == 0 ? seed : seed &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15)
        }
        guard parts.count > 1 else {
            var island = parts[0]
            island.weatherBands = weatherBands(input)
            island.regions = [IslandRegion(id: 0, first: input.first, last: input.last, size: island.size, origin: TilePoint(0, 0), side: island.side)]
            return island
        }

        // Раскладка: следующий остров — то вправо-вниз (+x), то влево-вниз (+y) на экране изометрии; квадраты не пересекаются.
        let gap = ExploreRules.islandGap, margin = ExploreRules.worldMargin
        var origins = [TilePoint(0, 0)]
        for index in 1..<parts.count {
            let previous = origins[index - 1], before = parts[index - 1].side, shift = (before - parts[index].side) / 2
            origins.append(index % 2 == 1 ? TilePoint(previous.x + before + gap, previous.y + shift)
                                          : TilePoint(previous.x + shift, previous.y + before + gap))
        }
        let minX = origins.map(\.x).min() ?? 0, minY = origins.map(\.y).min() ?? 0
        origins = origins.map { TilePoint($0.x - minX + margin, $0.y - minY + margin) }
        let side = zip(origins, parts).map { max($0.x, $0.y) + $1.side }.max()! + margin

        var terrain = [Terrain](repeating: .water, count: side * side)
        var world = Island(size: parts.map(\.size).max { $0.tiles < $1.tiles } ?? .small, side: side, terrain: [],
                           cities: [], villages: [], npcs: [], chests: [], campfires: [], weatherBands: weatherBands(input), start: TilePoint(0, 0))
        func moved(_ point: TilePoint, _ origin: TilePoint) -> TilePoint { TilePoint(point.x + origin.x, point.y + origin.y) }
        for (index, part) in parts.enumerated() {
            let origin = origins[index]
            for y in 0..<part.side { for x in 0..<part.side {
                terrain[(y + origin.y) * side + x + origin.x] = part.terrain[y * part.side + x]
            } }
            for var city in part.cities {
                city.id = world.cities.count; city.center = moved(city.center, origin); world.cities.append(city)
            }
            for var village in part.villages {
                village.id = 1000 + world.villages.count; village.center = moved(village.center, origin); world.villages.append(village)
            }
            for var npc in part.npcs { npc.id = world.npcs.count; npc.home = moved(npc.home, origin); world.npcs.append(npc) }
            for var chest in part.chests { chest.id = world.chests.count; chest.position = moved(chest.position, origin); world.chests.append(chest) }
            for var fire in part.campfires { fire.id = world.campfires.count; fire.position = moved(fire.position, origin); world.campfires.append(fire) }
            world.regions.append(IslandRegion(id: index, first: months[index].first, last: months[index].last,
                                              size: part.size, origin: origin, side: part.side))
        }
        world.terrain = terrain
        world.start = moved(parts[parts.count - 1].start, origins[parts.count - 1])
        world.ships = ships(in: world)
        // У корабля, как у старта, NPC не стоят — высадка не начинается со встречи.
        world.npcs = world.npcs.filter { npc in
            world.ships.allSatisfy { $0.position.distance(to: npc.home) >= ExploreRules.harbourRadius }
        }
        for index in world.npcs.indices { world.npcs[index].id = index }
        return world
    }

    /// Корабль у каждого острова: вода открытого моря рядом с сушей, ближе всего к соседнему острову.
    static func ships(in island: Island) -> [IslandShip] {
        let side = island.side
        // Открытое море — связная вода от угла мира (озёра внутри островов не годятся).
        var sea = [Bool](repeating: false, count: side * side)
        var stack = [0]
        sea[0] = true
        while let current = stack.popLast() {
            let cx = current % side, cy = current / side
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, ny >= 0, nx < side, ny < side else { continue }
                let next = ny * side + nx
                if !sea[next], island.terrain[next] == .water { sea[next] = true; stack.append(next) }
            }
        }
        return island.regions.map { region in
            let neighbour = island.regions[region.id == island.regions.count - 1 ? region.id - 1 : region.id + 1].center
            var best = region.center, bestDistance = Double.infinity
            for y in max(0, region.origin.y - 2)..<min(side, region.origin.y + region.side + 2) {
                for x in max(0, region.origin.x - 2)..<min(side, region.origin.x + region.side + 2) where sea[y * side + x] {
                    let point = TilePoint(x, y)
                    let touchesLand = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { dx, dy in
                        let near = TilePoint(x + dx, y + dy)
                        return island.isLand(near) && region.contains(near)
                    }
                    guard touchesLand else { continue }
                    let distance = point.distance(to: neighbour)
                    if distance < bestDistance { bestDistance = distance; best = point }
                }
            }
            return IslandShip(id: region.id, region: region.id, position: best)
        }
    }

    /// Погода — полосы по неделям всего диапазона.
    static func weatherBands(_ input: ExploreInput) -> [Weather] {
        var bands: [Weather] = []
        var week = input.first.weekStart
        while week <= input.last {
            bands.append(Weather.from(input.weekMoods[week], on: week))
            week = week.adding(days: 7)
        }
        return bands
    }

    /// Один остров по данным одного месяца (или всего диапазона).
    static func single(_ input: ExploreInput, seed: UInt64) -> Island {
        var random = ExploreRandom(seed)
        let size = ExploreRules.islandSize(days: input.days)
        let side = size.tiles
        var terrain = landMask(side: side, random: &random)

        // Пляж — суша у воды, лес — пятна шума.
        let forestNoise = valueNoise(side: side, cell: 6, random: &random)
        for y in 0..<side { for x in 0..<side where terrain[y * side + x] != .water {
            let nearWater = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { dx, dy in
                let nx = x + dx, ny = y + dy
                return nx < 0 || ny < 0 || nx >= side || ny >= side || terrain[ny * side + nx] == .water
            }
            terrain[y * side + x] = nearWater ? .sand : (forestNoise[y * side + x] > 0.62 ? .forest : .grass)
        } }
        var island = Island(size: size, terrain: terrain, cities: [], villages: [], npcs: [], chests: [], campfires: [],
                            weatherBands: [], start: TilePoint(side / 2, side / 2))
        var occupied: [TilePoint] = []

        func freeSpot(minDistance: Double, from others: [TilePoint], avoid: [(TilePoint, Double)] = [], attempts: Int = 400) -> TilePoint? {
            for _ in 0..<attempts {
                let point = TilePoint(random.int(side), random.int(side))
                guard island.terrain(at: point) == .grass || island.terrain(at: point) == .forest else { continue }
                guard others.allSatisfy({ $0.distance(to: point) >= minDistance }),
                      avoid.allSatisfy({ $0.0.distance(to: point) >= $0.1 }) else { continue }
                return point
            }
            return nil
        }

        // Города и деревни: события по названию (02, ответ 9).
        let groups = Dictionary(grouping: input.events) { $0.title.trimmingCharacters(in: .whitespaces).lowercased() }
            .map { (name: $0.value[0].title.trimmingCharacters(in: .whitespaces), count: $0.value.count) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
        var cityCenters: [TilePoint] = []
        for group in groups.filter({ $0.count >= 2 }).prefix(size.cityCap) {
            guard let spot = freeSpot(minDistance: Double(ExploreRules.cityMinDistance), from: cityCenters) else { continue }
            cityCenters.append(spot)
            occupied.append(spot)
            let houses = group.count >= 10 ? 10 : group.count >= 5 ? 6 : 3
            island.cities.append(IslandCity(id: island.cities.count, name: group.name, center: spot, events: group.count, houses: houses, isCity: true))
        }
        for group in groups.filter({ $0.count == 1 }).prefix(size.villageCap) {
            guard let spot = freeSpot(minDistance: Double(ExploreRules.villageMinDistance), from: occupied) else { continue }
            occupied.append(spot)
            island.villages.append(IslandCity(id: 1000 + island.villages.count, name: group.name, center: spot, events: 1, houses: 1, isCity: false))
        }
        island.start = island.cities.first?.center ?? nearestLand(to: TilePoint(side / 2, side / 2), in: island)

        // NPC: уникальные участники, потолок по размеру — самые частые остаются.
        var meetings: [String: Int] = [:]
        for event in input.events { for key in Set(event.attendeeKeys) { meetings[key, default: 0] += 1 } }
        let people = meetings.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(size.npcCap)
        let safe = island.cities.map { ($0.center, Double(ExploreRules.citySafeRadius + 2)) }
        for (index, person) in people.enumerated() {
            guard let spot = freeSpot(minDistance: 2, from: island.npcs.map(\.home),
                                      avoid: safe + [(island.start, Double(ExploreRules.npcMinDistanceFromStart))]) else { continue }
            island.npcs.append(IslandNPC(id: index, tier: NPCTier.of(meetings: person.value), home: spot, meetings: person.value))
        }

        // Сундуки: квесты по приоритету, не больше 30.
        let order: [QuestPriority] = [.high, .medium, .low]
        let quests = input.quests.sorted { (order.firstIndex(of: $0.priority) ?? 1) < (order.firstIndex(of: $1.priority) ?? 1) }
        for quest in quests.prefix(ExploreRules.chestCap) {
            guard let spot = freeSpot(minDistance: 2, from: occupied) else { continue }
            occupied.append(spot)
            island.chests.append(IslandChest(id: island.chests.count, title: quest.title, position: spot))
        }

        // Костры: лучшая ночь каждой недели.
        let byWeek = Dictionary(grouping: input.nights) { $0.key.weekStart }
        for week in byWeek.keys.sorted() {
            guard let best = byWeek[week]?.map(\.value).max(), let spot = freeSpot(minDistance: 3, from: occupied) else { continue }
            occupied.append(spot)
            island.campfires.append(IslandCampfire(id: island.campfires.count, quality: best, position: spot))
        }

        island.weatherBands = weatherBands(input)
        return island
    }

    /// Суша — «капля»: расстояние до центра плюс шум; остаётся самая большая связная часть.
    static func landMask(side: Int, random: inout ExploreRandom) -> [Terrain] {
        let noise = valueNoise(side: side, cell: max(6, side / 6), random: &random)
        var land = [Terrain](repeating: .water, count: side * side)
        let center = Double(side - 1) / 2
        for y in 0..<side { for x in 0..<side {
            let dx = (Double(x) - center) / center, dy = (Double(y) - center) / center
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance + (noise[y * side + x] - 0.5) * 0.45 < 0.78 { land[y * side + x] = .grass }
        } }
        // Самая большая связная суша.
        var component = [Int](repeating: -1, count: side * side)
        var best = (id: -1, count: 0), id = 0
        for start in 0..<(side * side) where land[start] != .water && component[start] == -1 {
            var stack = [start], count = 0
            component[start] = id
            while let current = stack.popLast() {
                count += 1
                let cx = current % side, cy = current / side
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = cx + dx, ny = cy + dy
                    guard nx >= 0, ny >= 0, nx < side, ny < side else { continue }
                    let next = ny * side + nx
                    if land[next] != .water, component[next] == -1 { component[next] = id; stack.append(next) }
                }
            }
            if count > best.count { best = (id, count) }
            id += 1
        }
        return land.indices.map { component[$0] == best.id ? land[$0] : .water }
    }

    /// Шум значений: случайная решётка с шагом `cell`, билинейная интерполяция.
    static func valueNoise(side: Int, cell: Int, random: inout ExploreRandom) -> [Double] {
        let grid = side / cell + 2
        let lattice = (0..<(grid * grid)).map { _ in random.unit() }
        return (0..<(side * side)).map { index in
            let x = Double(index % side) / Double(cell), y = Double(index / side) / Double(cell)
            let x0 = Int(x), y0 = Int(y), fx = x - Double(x0), fy = y - Double(y0)
            func at(_ i: Int, _ j: Int) -> Double { lattice[min(j, grid - 1) * grid + min(i, grid - 1)] }
            let top = at(x0, y0) * (1 - fx) + at(x0 + 1, y0) * fx
            let bottom = at(x0, y0 + 1) * (1 - fx) + at(x0 + 1, y0 + 1) * fx
            return top * (1 - fy) + bottom * fy
        }
    }

    static func nearestLand(to point: TilePoint, in island: Island) -> TilePoint {
        var best = point, bestDistance = Double.infinity
        for y in 0..<island.side { for x in 0..<island.side where island.terrain[y * island.side + x] != .water {
            let distance = TilePoint(x, y).distance(to: point)
            if distance < bestDistance { bestDistance = distance; best = TilePoint(x, y) }
        } }
        return best
    }
}

// MARK: - Встреча (09, раздел 4)

public enum EncounterAction: Hashable, Sendable {
    case fight
    case ability(ExploreSkill)
    case flee
}

public enum EncounterOutcome: Hashable, Sendable { case won, persuaded, fled, lost }

/// Пошаговая встреча: ход героя, затем ход NPC.
public struct Encounter: Sendable {
    public let tier: NPCTier
    public let hero: ExploreHero
    public private(set) var heroHP: Double
    public private(set) var heroMP: Double
    public private(set) var npcHP: Double
    public private(set) var turn = 1
    public private(set) var outcome: EncounterOutcome?
    public private(set) var log: [String] = []
    /// Ходы до готовности способности.
    public private(set) var cooldowns: [ExploreAbility: Int] = [:]
    private var npcSkips = 0
    private var guardTurns = 0
    private var nextHitBonus = 1.0
    private var random: ExploreRandom

    public init(tier: NPCTier, hero: ExploreHero, heroHP: Double, heroMP: Double, seed: UInt64) {
        self.tier = tier
        self.hero = hero
        self.heroHP = heroHP
        self.heroMP = heroMP
        self.npcHP = tier.hp
        self.random = ExploreRandom(seed)
    }

    public var npcMaxHP: Double { tier.hp }
    public var strikeRange: ClosedRange<Int> {
        let base = ExploreRules.strike(strength: hero.level(.strength))
        return Int((base * (1 - ExploreRules.hitSpread)).rounded())...Int((base * (1 + ExploreRules.hitSpread)).rounded())
    }
    public var escapeChance: Double { ExploreRules.escapeChance(mentality: hero.level(.mentality), tier: tier) }

    public func persuadeChance(power: Double) -> Double {
        let base = (0.30 + 0.05 * Double(hero.level(.charisma))) * power
        return min(0.85, max(0, base - 0.15 * Double(tier.rawValue - 1)))
    }

    public func cost(_ ability: ExploreAbility) -> Double { (ability.mpShare * hero.maxMP).rounded() }

    public func isReady(_ skill: ExploreSkill) -> Bool {
        (cooldowns[skill.ability] ?? 0) == 0 && heroMP >= cost(skill.ability) && outcome == nil
    }

    public mutating func perform(_ action: EncounterAction) {
        guard outcome == nil else { return }
        for key in cooldowns.keys { cooldowns[key] = max(0, (cooldowns[key] ?? 0) - 1) }
        switch action {
        case .fight:
            hit(factor: 1, label: "Вы ударили")
        case .flee:
            if random.unit() < escapeChance {
                outcome = .fled
                log.append("Вы убежали")
                return
            }
            log.append("Убежать не вышло")
        case .ability(let skill):
            guard isReady(skill) else { return }
            heroMP -= cost(skill.ability)
            cooldowns[skill.ability] = hero.cooldown
            use(skill)
        }
        if npcHP <= 0 { outcome = .won; log.append("\(tier.title) повержен"); return }
        guard outcome == nil else { return }
        npcTurn()
        turn += 1
    }

    private mutating func hit(factor: Double, label: String) {
        let damage = (ExploreRules.strike(strength: hero.level(.strength)) * factor * nextHitBonus * random.spread(ExploreRules.hitSpread)).rounded()
        nextHitBonus = 1
        npcHP = max(0, npcHP - damage)
        log.append("\(label): −\(Int(damage))")
    }

    private mutating func use(_ skill: ExploreSkill) {
        let power = skill.power
        switch skill.ability {
        case .powerStrike: hit(factor: 1 + power, label: skill.ability.title)
        case .teamMove:
            hit(factor: 1 + 0.5 * power, label: skill.ability.title)
            npcSkips = max(npcSkips, 1)
        case .scout:
            nextHitBonus = 1 + 0.5 * power
            log.append("Разведка: следующий удар ×\(String(format: "%.2g", nextHitBonus))")
        case .focus:
            guardTurns = Int((2 * power).rounded(.down))
            log.append("Концентрация: \(guardTurns) хода урон вдвое меньше")
        case .distract:
            npcSkips = max(npcSkips, Int((2 * power).rounded(.down)))
            log.append("Отвлечь: NPC пропустит \(npcSkips) хода")
        case .dash:
            outcome = .fled
            log.append("Рывок — вы оторвались")
        case .persuade:
            if random.unit() < persuadeChance(power: power) {
                outcome = .persuaded
                log.append("\(tier.title) согласился разойтись миром")
            } else {
                log.append("Уговорить не вышло")
            }
        }
    }

    private mutating func npcTurn() {
        if npcSkips > 0 {
            npcSkips -= 1
            log.append("\(tier.title) пропускает ход")
            return
        }
        var damage = tier.damageShare * hero.maxHP * random.spread(ExploreRules.hitSpread)
        if guardTurns > 0 { damage *= 0.5; guardTurns -= 1 }
        damage = damage.rounded()
        heroHP = max(0, heroHP - damage)
        log.append("\(tier.title) ударил: −\(Int(damage)) HP")
        if heroHP <= 0 { outcome = .lost; log.append("Вы без сил — очнётесь в городе") }
    }
}
