import SpriteKit
import Domain

/// Сцена острова (8B): изометрия, камера за героем, ходьба касанием по пути через сушу, NPC бродят и преследуют.
final class ExploreScene: SKScene {
    let session: ExploreSession
    /// Встреча началась — экран SwiftUI показывает окно встречи.
    var onEncounter: (() -> Void)?

    private var side: Int { session.island.side }
    private let heroNode = SKSpriteNode()

    /// Аура ранга под героем (10.3): пиксели кольца — передняя половина поверх ног, задняя и искры — за героем.
    private var auraScale: CGFloat { session.appearance == nil ? 1 : 2 }

    private func addAura(tier: Int) {
        guard let colors = AuraArt.colors(tier) else { return }
        func color(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        let shimmer = tier >= 5 && !UIAccessibility.isReduceMotionEnabled
        for point in AuraArt.pixels(tier: tier, rx: 9, ry: 3) {
            let dot = SKSpriteNode(color: color(point.spark ? colors.spark : colors.ring), size: CGSize(width: 1, height: 1))
            // В SpriteKit ось Y вверх: точки пикселей (вниз) переворачиваем.
            dot.position = CGPoint(x: point.x.rounded() * auraScale, y: (-point.y.rounded() + 1) * auraScale)
            dot.size = CGSize(width: auraScale, height: auraScale)
            dot.zPosition = !point.spark && point.y > 0 ? 0.01 : -0.01
            dot.alpha = point.spark ? 0.85 : 0.75
            if shimmer && point.spark {
                dot.run(.repeatForever(.sequence([.fadeAlpha(to: 0.2, duration: 0.6 + Double(abs(point.x)) / 20), .fadeAlpha(to: 0.95, duration: 0.6)])))
            }
            heroNode.addChild(dot)
        }
    }
    private let heroLabel = SKLabelNode()
    private let cameraNode = SKCameraNode()
    private let fogNode = SKSpriteNode()
    private var fogHole: Double = 0
    private var npcNodes: [SKSpriteNode] = []
    private var npcBadges: [SKShapeNode] = []
    private var chestNodes: [Int: SKSpriteNode] = [:]
    /// Фрегаты архипелага (12B).
    private var shipNodes: [SKSpriteNode] = []
    // Этап 14: бутылки, башни, маяки, ночь, компас.
    private var bottleNodes: [Int: SKSpriteNode] = [:]
    private var towerNodes: [Int: SKSpriteNode] = [:]
    private var lightNodes: [Int: SKSpriteNode] = [:]
    private let nightNode = SKSpriteNode(color: UIColor(red: 0.04, green: 0.06, blue: 0.16, alpha: 1), size: CGSize(width: 2400, height: 2400))
    private let compassNode = SKShapeNode()
    private var clockAccumulator: Double = 0
    /// Нос корабля на спрайте — слева; плывя вправо по экрану, корабль разворачивается.
    private var shipFacesRight = false
    private var fireNodes: [Int: SKSpriteNode] = [:]
    // Этап 15A: земля кусками, кадры шага, свет ночью, осадки по зоне.
    private var chunkNodes: [Int: SKSpriteNode] = [:]
    private var chunkLoading: Set<Int> = []
    private var chunkTicker: Double = 0
    private var heroFrames: [SKTexture] = []
    private var npcFrames: [[SKTexture]] = []
    private var shipFrames: [SKTexture] = []
    private var walkPhase: Double = 0
    private var glowNodes: [SKSpriteNode] = []
    private var heroGlow = SKSpriteNode()
    private var weatherNode: SKEmitterNode?
    private var weatherKind = ""
    private var weatherTicker: Double = 10
    private var wakeNode: SKEmitterNode?
    private var exploredTile = TilePoint(-1, -1)
    // Активный режим (16.11.2026): джойстик, бой на карте.
    private var stickMoving = false
    // 15B, 15G.
    private var shrineNodes: [Int: SKSpriteNode] = [:]
    private var monumentNodes: [Int: SKSpriteNode] = [:]
    /// Выпады (15G.3): узел → начало и направление.
    private var lunges: [ObjectIdentifier: (start: TimeInterval, dx: CGFloat, dy: CGFloat)] = [:]
    private var seenLog = 0
    // 15C.
    private var lookoutNodes: [Int: SKSpriteNode] = [:]
    private let treasureNode = SKSpriteNode()
    private var treasureShown = false
    /// Когда спутник последний раз ударил — короткий выпад.
    private var companionLunge: TimeInterval = -10
    private let fightBar = SKNode()
    private let fightBarFill = SKSpriteNode(color: UIColor(red: 0.66, green: 0.26, blue: 0.18, alpha: 1), size: CGSize(width: 20, height: 2.5))

    /// Позиции в клетках (дробные).
    private var heroPosition: (x: Double, y: Double)
    private var path: [TilePoint] = []
    private var lastTime: TimeInterval = 0
    private var bobPhase: Double = 0

    private struct NPCState {
        var x: Double
        var y: Double
        var target: (x: Double, y: Double)?
        var calmUntil: TimeInterval = 0
        var peaceful = false
        var chasing = false
    }
    private var npcs: [NPCState] = []
    /// Призраки просроченных задач (9.6): летают по острову и не нападают.
    private var ghostNodes: [SKSpriteNode] = []
    private var ghostStates: [(x: Double, y: Double, tx: Double, ty: Double)] = []
    private var random: ExploreRandom
    private var now: TimeInterval = 0
    private var restAccumulator: Double = 0

    init(session: ExploreSession, size: CGSize) {
        self.session = session
        heroPosition = (Double(session.heroTile.x), Double(session.heroTile.y))
        random = ExploreRandom(session.seed ^ 0x5EED)
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0x2B / 255, green: 0x58 / 255, blue: 0x84 / 255, alpha: 1)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func didMove(to view: SKView) {
        guard children.isEmpty else { return }
        let island = session.island
        loadChunks(synchronously: true)
        for city in island.cities + island.villages {
            let label = SKLabelNode(text: city.name)
            label.fontName = "HelveticaNeue-Bold"
            // Подписи — в масштабе персонажей (×0,5): мельче вместе с ними.
            label.fontSize = 4
            label.fontColor = city.isCity ? .white : UIColor(red: 0.12, green: 0.16, blue: 0.27, alpha: 1)
            label.position = point(Double(city.center.x), Double(city.center.y), lift: city.isCity ? 30 : 22)
            label.zPosition = 9_000
            let plate = SKShapeNode(rectOf: CGSize(width: label.frame.width + 5, height: 6.5), cornerRadius: 2)
            plate.fillColor = city.isCity ? UIColor(red: 0.12, green: 0.16, blue: 0.27, alpha: 0.9) : UIColor(white: 1, alpha: 0.85)
            plate.strokeColor = .clear
            plate.position = CGPoint(x: 0, y: 1.6)
            plate.zPosition = -1
            label.addChild(plate)
            addChild(label)
            if city.isCity {
                // Безопасная зона — пунктирный круг.
                let ring = SKShapeNode(ellipseOf: CGSize(width: Double(ExploreRules.citySafeRadius * 2) * Double(ExploreRenderer.tileW),
                                                          height: Double(ExploreRules.citySafeRadius * 2) * Double(ExploreRenderer.tileH)))
                ring.strokeColor = UIColor(white: 1, alpha: 0.7)
                ring.lineWidth = 1
                ring.fillColor = UIColor(white: 1, alpha: 0.06)
                ring.position = point(Double(city.center.x), Double(city.center.y))
                ring.zPosition = -9_000
                addChild(ring)
            }
        }
        // Подписи месяцев над островами архипелага — у северной кромки суши.
        if island.regions.count > 1 {
            for region in island.regions {
                var top = region.center, best = Int.max
                for y in region.origin.y..<(region.origin.y + region.side) {
                    for x in region.origin.x..<(region.origin.x + region.side) where island.isLand(TilePoint(x, y)) && x + y < best {
                        best = x + y; top = TilePoint(x, y)
                    }
                }
                let label = SKLabelNode(text: "\(region.monthTitle) · \(Format.dayCount(region.days))")
                label.fontName = "HelveticaNeue-Bold"
                label.fontSize = 7
                label.fontColor = UIColor(red: 0.12, green: 0.16, blue: 0.27, alpha: 1)
                label.position = point(Double(top.x), Double(top.y), lift: 16)
                label.zPosition = 9_200
                let plate = SKShapeNode(rectOf: CGSize(width: label.frame.width + 8, height: 10), cornerRadius: 3)
                plate.fillColor = UIColor(red: 1, green: 0.99, blue: 0.96, alpha: 0.94)
                plate.strokeColor = .clear
                plate.position = CGPoint(x: 0, y: 2.5)
                plate.zPosition = -1
                label.addChild(plate)
                addChild(label)
            }
        }
        // Корабль (15A.7): изометрия, 4 кадра паруса; курс влево — зеркало.
        shipFrames = (0..<4).compactMap { texture(ExploreSprites.ship(frame: $0).image) }
        let moored = texture(ExploreSprites.ship(frame: 0, sails: 1).image)
        for _ in session.ships {
            let node = SKSpriteNode(texture: moored)
            node.anchorPoint = CGPoint(x: 0.47, y: 0.12)
            node.setScale(Self.characterScale * 1.1)
            shipNodes.append(node)
            addChild(node)
        }
        for chest in island.chests {
            let node = sprite(ExploreRenderer.chest(opened: false))
            node.position = point(Double(chest.position.x), Double(chest.position.y))
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.zPosition = depth(Double(chest.position.x), Double(chest.position.y))
            chestNodes[chest.id] = node
            addChild(node)
        }
        for fire in island.campfires {
            let node = sprite(ExploreRenderer.campfire(lit: false))
            node.position = point(Double(fire.position.x), Double(fire.position.y))
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.zPosition = depth(Double(fire.position.x), Double(fire.position.y))
            fireNodes[fire.id] = node
            addChild(node)
        }
        for bottle in island.bottles {
            let node = sprite(ExploreRenderer.bottle())
            node.anchorPoint = CGPoint(x: 0.5, y: 0.2)
            node.position = point(Double(bottle.position.x), Double(bottle.position.y))
            node.zPosition = depth(Double(bottle.position.x), Double(bottle.position.y))
            node.run(.repeatForever(.sequence([.moveBy(x: 0, y: 1, duration: 0.8), .moveBy(x: 0, y: -1, duration: 0.8)])))
            bottleNodes[bottle.id] = node
            addChild(node)
        }
        for tower in island.towers {
            let node = sprite(tower.isFinal ? ExploreSprites.bossTower(conquered: false).image : ExploreRenderer.tower(conquered: false))
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.setScale(tower.isFinal ? 1.1 : 1.6)
            node.position = point(Double(tower.position.x), Double(tower.position.y))
            node.zPosition = depth(Double(tower.position.x), Double(tower.position.y))
            towerNodes[tower.id] = node
            addChild(node)
            addLabel(tower.isFinal ? "Финальная башня · босс" : "Чёрная башня · \(tower.title)", at: tower.position, lift: tower.isFinal ? 76 : 30, dark: true)
        }
        for light in island.lighthouses {
            let node = sprite(ExploreRenderer.lighthouse(lit: false))
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.setScale(1.4)
            node.position = point(Double(light.position.x), Double(light.position.y))
            node.zPosition = depth(Double(light.position.x), Double(light.position.y))
            lightNodes[light.id] = node
            addChild(node)
            addLabel("Маяк · \(light.title)", at: light.position, lift: 20, dark: false)
        }
        // 15B.2: памятники Epic — касание открывает карточку.
        for monument in island.monuments {
            let node = sprite(ExploreSprites.epicMonument(ruin: island.zone(at: monument.position) == .desert).image)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.08)
            node.position = point(Double(monument.position.x), Double(monument.position.y))
            node.zPosition = depth(Double(monument.position.x), Double(monument.position.y))
            monumentNodes[monument.id] = node
            addChild(node)
            addLabel("Epic · \(monument.epic.title)", at: monument.position, lift: 40, dark: false)
        }
        // 15G.4: монументы полезного.
        for shrine in island.shrines {
            let node = sprite(ExploreSprites.shrine(shrine.buff).image)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.1)
            node.position = point(Double(shrine.position.x), Double(shrine.position.y))
            node.zPosition = depth(Double(shrine.position.x), Double(shrine.position.y))
            shrineNodes[shrine.id] = node
            addChild(node)
            addLabel("\(shrine.buff.title) · \(shrine.marks)", at: shrine.position, lift: 32, dark: false)
        }
        // 15C: смотровые площадки, входы в пещеры.
        for lookout in island.lookouts {
            let node = sprite(ExploreSprites.lookout(used: false).image)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.08)
            node.position = point(Double(lookout.position.x), Double(lookout.position.y))
            node.zPosition = depth(Double(lookout.position.x), Double(lookout.position.y))
            lookoutNodes[lookout.id] = node
            addChild(node)
            addLabel("Смотровая площадка", at: lookout.position, lift: 34, dark: false)
        }
        for cave in island.caves {
            for end in [cave.entrance, cave.exit] {
                let node = sprite(ExploreSprites.caveEntrance().image)
                node.anchorPoint = CGPoint(x: 0.5, y: 0.1)
                node.position = point(Double(end.x), Double(end.y))
                node.zPosition = depth(Double(end.x), Double(end.y))
                addChild(node)
                addLabel("Пещера", at: end, lift: 30, dark: true)
            }
        }
        treasureNode.anchorPoint = CGPoint(x: 0.5, y: 0.2)
        treasureNode.isHidden = true
        addChild(treasureNode)
        // 15B.1: таблички секторов навыков.
        for sector in island.sectors {
            let gain = Int(sector.gain.rounded())
            addLabel(sector.isWaste ? "\(sector.title) · без роста" : "\(sector.title) · +\(gain) XP", at: sector.sign, lift: 12, dark: sector.isWaste)
        }
        // Доски заданий нарисованы на площадях городов (15A.7).
        // NPC (15A.7): одежда по типу, добавки по зоне, 4 кадра шага; кадры общие для одинаковых NPC.
        var framesCache: [String: [SKTexture]] = [:]
        let feet = CGFloat(ExploreCharacters.feetFromBottom) / CGFloat(ExploreCharacters.frameSize.height)
        for npc in island.npcs {
            let zone = island.zone(at: npc.home), variant = npc.id % 4
            let key = "\(npc.tier.rawValue)-\(zone.rawValue)-\(variant)"
            let frames = framesCache[key] ?? ExploreCharacters.npc(tier: npc.tier, zone: zone, variant: variant).compactMap { texture($0) }
            framesCache[key] = frames
            npcFrames.append(frames)
            let node = SKSpriteNode(texture: frames.first)
            node.anchorPoint = CGPoint(x: 0.5, y: feet)
            node.setScale(Self.characterScale / 2)
            addChild(node)
            npcNodes.append(node)
            let badge = SKShapeNode(rectOf: CGSize(width: 8, height: 8))
            badge.strokeColor = UIColor(red: 0.12, green: 0.16, blue: 0.27, alpha: 1)
            badge.lineWidth = 2
            badge.position = CGPoint(x: 0, y: 66)
            node.addChild(badge)
            npcBadges.append(badge)
            npcs.append(NPCState(x: Double(npc.home.x), y: Double(npc.home.y)))
        }
        for _ in 0..<session.ghostCount {
            let node = sprite(ExploreRenderer.ghost())
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.alpha = 0.85
            node.zPosition = 9_400
            addChild(node)
            ghostNodes.append(node)
            let start = randomLand()
            ghostStates.append((Double(start.x), Double(start.y), Double(start.x), Double(start.y)))
        }
        // Герой (15A.7): полный рисунок образа E 32×56 в том же размере на экране, тень и 4 кадра шага.
        if let appearance = session.appearance {
            heroFrames = ExploreCharacters.frames(ExploreCharacters.pixels(appearance, accent: session.accent), outline: false).compactMap { texture($0) }
            heroNode.texture = heroFrames.first
            heroNode.size = CGSize(width: ExploreCharacters.frameSize.width, height: ExploreCharacters.frameSize.height)
            heroNode.anchorPoint = CGPoint(x: 0.5, y: feet)
            heroNode.setScale(Self.characterScale / 2)
        } else {
            heroNode.color = UIColor(red: 0.18, green: 0.42, blue: 0.31, alpha: 1)
            heroNode.size = CGSize(width: 8, height: 14)
            heroNode.anchorPoint = CGPoint(x: 0.5, y: 0)
            heroNode.setScale(Self.characterScale)
        }
        // Дочерние узлы героя заданы в координатах спрайта 16×28 — при полном рисунке масштаб вдвое.
        let childScale: CGFloat = session.appearance == nil ? 1 : 2
        addChild(heroNode)
        addAura(tier: session.aura)
        // 💧 или ✨ напротив лица (12D.5): в координатах спрайта героя 16×28.
        if let badge = session.badge, let image = badge.image {
            let icon = SKSpriteNode(texture: SKTexture(cgImage: image))
            icon.texture?.filteringMode = .nearest
            icon.anchorPoint = CGPoint(x: 0, y: 1)
            icon.setScale(childScale)
            icon.position = CGPoint(x: 7 * childScale, y: 30 * childScale)
            icon.zPosition = 0.02
            heroNode.addChild(icon)
        }
        heroLabel.text = "\(session.hero.rankLetter) · Герой"
        heroLabel.fontName = "HelveticaNeue-Bold"
        heroLabel.fontSize = 6
        heroLabel.fontColor = UIColor(red: 0.12, green: 0.16, blue: 0.27, alpha: 1)
        heroLabel.position = CGPoint(x: 0, y: 34 * childScale)
        heroLabel.setScale(childScale)
        // Пометка ранга — поверх подписей городов.
        heroLabel.zPosition = 9_500
        let plate = SKShapeNode(rectOf: CGSize(width: heroLabel.frame.width + 8, height: 9), cornerRadius: 3)
        plate.fillColor = UIColor(red: 0xE2 / 255, green: 0xA0 / 255, blue: 0x4A / 255, alpha: 1)
        plate.strokeColor = .clear
        plate.position = CGPoint(x: 0, y: 2)
        plate.zPosition = -1
        heroLabel.addChild(plate)
        heroNode.addChild(heroLabel)

        camera = cameraNode
        cameraNode.setScale(session.zoom)
        addChild(cameraNode)
        // Ночь (14.5): тёмная пелена поверх острова, под туманом.
        nightNode.zPosition = 19_500
        nightNode.alpha = 0
        cameraNode.addChild(nightNode)
        // Компас: стрелка к ближайшему неоткрытому сундуку.
        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: 0, y: 10)); arrow.addLine(to: CGPoint(x: -6, y: -6)); arrow.addLine(to: CGPoint(x: 6, y: -6)); arrow.closeSubpath()
        compassNode.path = arrow
        compassNode.fillColor = UIColor(red: 0.18, green: 0.42, blue: 0.31, alpha: 1)
        compassNode.strokeColor = UIColor(white: 1, alpha: 0.9)
        compassNode.lineWidth = 1.5
        compassNode.zPosition = 21_000
        compassNode.isHidden = true
        cameraNode.addChild(compassNode)
        fogNode.zPosition = 20_000
        cameraNode.addChild(fogNode)
        addLights()
        updateWeather()
        updateFog()
        layoutDynamic()
    }

    /// Подпись объекта острова в масштабе персонажей.
    private func addLabel(_ text: String, at tile: TilePoint, lift: Double, dark: Bool) {
        let label = SKLabelNode(text: text)
        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 4
        label.fontColor = dark ? .white : UIColor(red: 0.12, green: 0.16, blue: 0.27, alpha: 1)
        label.position = point(Double(tile.x), Double(tile.y), lift: lift)
        label.zPosition = 9_000
        let plate = SKShapeNode(rectOf: CGSize(width: label.frame.width + 5, height: 6.5), cornerRadius: 2)
        plate.fillColor = dark ? UIColor(red: 0.1, green: 0.1, blue: 0.13, alpha: 0.92) : UIColor(white: 1, alpha: 0.85)
        plate.strokeColor = .clear
        plate.position = CGPoint(x: 0, y: 1.6)
        plate.zPosition = -1
        label.addChild(plate)
        addChild(label)
    }

    /// Персонажи мельче при прежнем масштабе карты (8C.9).
    static let characterScale: CGFloat = 0.5

    // MARK: Погода и свет (15A)

    /// Осадки по погоде острова-месяца и зоне под героем: дождь, снег в холодных зонах, песок в пустыне; ночью в умеренной — светлячки.
    private func updateWeather() {
        let zone = session.zoneHere, weather = session.weatherHere
        let kind: String
        if weather == .rain || weather == .snow { kind = zone.isCold ? "snow" : zone == .desert ? "sand" : "rain" }
        else if zone == .desert || (zone == .steppe && weather == .cloudy) { kind = "dust" }
        else if session.isNight && zone == .temperate { kind = "fireflies" }
        else { kind = "" }
        guard kind != weatherKind else { return }
        weatherKind = kind
        weatherNode?.removeFromParent()
        weatherNode = kind.isEmpty ? nil : emitter(kind)
        if let weatherNode { cameraNode.addChild(weatherNode) }
    }

    private func emitter(_ kind: String) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        let (w, h, color): (Int, Int, UInt32) = switch kind {
        case "snow": (2, 2, 0xF4F7F9)
        case "rain": (1, 5, 0xBFD3E6)
        case "fireflies": (2, 2, 0xF2D27A)
        default: (2, 1, 0xE8CF8E)
        }
        if let image = RGBACanvas(width: w, height: h, fill: color).image {
            emitter.particleTexture = SKTexture(cgImage: image)
            emitter.particleTexture?.filteringMode = .nearest
        }
        switch kind {
        case "snow":
            emitter.particleBirthRate = 60; emitter.particleLifetime = 6; emitter.particleSpeed = 40; emitter.particleSpeedRange = 20
            emitter.emissionAngle = -.pi / 2; emitter.emissionAngleRange = 0.6; emitter.particleAlpha = 0.9
            emitter.position = CGPoint(x: 0, y: 260); emitter.particlePositionRange = CGVector(dx: 520, dy: 40)
        case "rain":
            emitter.particleBirthRate = 160; emitter.particleLifetime = 1.4; emitter.particleSpeed = 320; emitter.particleSpeedRange = 60
            emitter.emissionAngle = -.pi / 2 - 0.25; emitter.emissionAngleRange = 0.05; emitter.particleAlpha = 0.6; emitter.particleRotation = 0.25
            emitter.position = CGPoint(x: 0, y: 260); emitter.particlePositionRange = CGVector(dx: 520, dy: 40)
        case "sand", "dust":
            emitter.particleBirthRate = kind == "sand" ? 120 : 25; emitter.particleLifetime = 4; emitter.particleSpeed = kind == "sand" ? 160 : 60
            emitter.particleSpeedRange = 40; emitter.emissionAngle = .pi - 0.1; emitter.emissionAngleRange = 0.2; emitter.particleAlpha = 0.55
            emitter.position = CGPoint(x: 300, y: 0); emitter.particlePositionRange = CGVector(dx: 40, dy: 600)
        default:
            emitter.particleBirthRate = 4; emitter.particleLifetime = 5; emitter.particleSpeed = 6; emitter.particleSpeedRange = 6
            emitter.emissionAngleRange = .pi * 2; emitter.particleAlpha = 0.9; emitter.particleAlphaSpeed = -0.15
            emitter.position = .zero; emitter.particlePositionRange = CGVector(dx: 400, dy: 600)
        }
        emitter.zPosition = 19_000
        emitter.advanceSimulationTime(4)
        return emitter
    }

    /// Тёплое пятно света ночью: радиальный градиент.
    private static let glowTexture: SKTexture? = {
        let size = 64
        var canvas = RGBACanvas(width: size, height: size, fill: nil)
        for y in 0..<size { for x in 0..<size {
            let d = hypot(Double(x) - 31.5, Double(y) - 31.5) / 32
            if d < 1 { canvas.setAlpha(x, y, 0xF2B35B, alpha: pow(1 - d, 1.8)) }
        } }
        return canvas.image.map { SKTexture(cgImage: $0) }
    }()

    private func glow(at position: CGPoint, size: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(texture: Self.glowTexture)
        node.size = CGSize(width: size, height: size * 0.6)
        node.position = position
        node.blendMode = .add
        node.zPosition = 19_600
        node.alpha = 0
        addChild(node)
        return node
    }

    /// Свет ночью: окна городов и деревень, факел героя; костры и маяки — когда зажжены.
    private func addLights() {
        for place in session.island.cities + session.island.villages {
            glowNodes.append(glow(at: point(Double(place.center.x), Double(place.center.y), lift: 6), size: place.isCity ? 150 : 60))
        }
        heroGlow = glow(at: .zero, size: 90)
    }

    private func sprite(_ image: CGImage?) -> SKSpriteNode {
        guard let image else { return SKSpriteNode(color: .clear, size: .zero) }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return SKSpriteNode(texture: texture)
    }

    // MARK: Активный режим (16.11.2026)

    /// Джойстик: направление на экране переводится в клетки изометрии; в воду (пешком) и на сушу (на корабле) не заходит.
    private func moveByStick(_ dt: Double) {
        let stick = session.stick
        let magnitude = min(1, hypot(stick.dx, stick.dy))
        guard magnitude > 0.15 else { stickMoving = false; return }
        // Экран: px = (x − y)·8, py = (x + y)·4 → клетки.
        var tx = Double(stick.dx) / 16 + Double(stick.dy) / 8, ty = Double(stick.dy) / 8 - Double(stick.dx) / 16
        let length = max(0.0001, hypot(tx, ty))
        tx /= length; ty /= length
        let step = session.speed * dt * magnitude
        let sailing = session.sailing != nil
        func passable(_ x: Double, _ y: Double) -> Bool {
            let tile = TilePoint(Int(x.rounded()), Int(y.rounded()))
            guard tile.x >= 0, tile.y >= 0, tile.x < side, tile.y < side else { return false }
            return sailing ? !session.island.isLand(tile) : session.island.isWalkable(tile)
        }
        let (x, y) = heroPosition
        if passable(x + tx * step, y + ty * step) { heroPosition = (x + tx * step, y + ty * step) }
        else if passable(x + tx * step, y) { heroPosition = (x + tx * step, y) }
        else if passable(x, y + ty * step) { heroPosition = (x, y + ty * step) }
        else { stickMoving = false; return }
        stickMoving = true
        if sailing, abs(tx - ty) > 0.05 { shipFacesRight = tx - ty > 0 }
        walkPhase += dt * session.speed * 2.2
        let tile = TilePoint(Int(heroPosition.x.rounded()), Int(heroPosition.y.rounded()))
        if tile != session.heroTile { session.heroTile = tile; session.steps += 1 }
    }

    /// Где противник активного боя.
    private func activeTarget() -> (x: Double, y: Double)? {
        guard session.activeFight != nil else { return nil }
        if let id = session.activeNPC, npcs.indices.contains(id) { return (npcs[id].x, npcs[id].y) }
        if let id = session.activeTower, let tower = session.island.towers.first(where: { $0.id == id }) {
            return (Double(tower.position.x), Double(tower.position.y))
        }
        return nil
    }

    /// Активный бой: время идёт, расстояние до противника, побег, всплывающие числа, итог.
    private func updateActiveFight(_ dt: Double) {
        guard var fight = session.activeFight else { fightBar.isHidden = true; return }
        let target: (x: Double, y: Double)
        if let id = session.activeNPC, npcs.indices.contains(id) { target = (npcs[id].x, npcs[id].y) }
        else if let id = session.activeTower, let tower = session.island.towers.first(where: { $0.id == id }) {
            target = (Double(tower.position.x), Double(tower.position.y))
        } else { session.activeFight = nil; return }
        let distance = hypot(heroPosition.x - target.x, heroPosition.y - target.y)
        session.activeDistance = distance
        fight.tick(dt, distance: distance)
        if distance > fight.escapeDistance { fight.escape() }
        for event in fight.drainEvents() {
            switch event {
            case let .heroDamaged(value):
                floater("−\(value)", at: heroPosition, color: UIColor(red: 0.66, green: 0.26, blue: 0.18, alpha: 1))
                animateHit(by: opponentNode(), on: heroNode, from: target, to: heroPosition, color: .red)
            case let .npcDamaged(value):
                floater("−\(value)", at: target, color: UIColor(red: 0.95, green: 0.82, blue: 0.48, alpha: 1))
                animateHit(by: heroNode, on: opponentNode(), from: heroPosition, to: target, color: .white)
            case let .companionHit(value):
                companionLunge = now
                if let id = session.companion?.id, npcNodes.indices.contains(id), npcs.indices.contains(id) {
                    animateHit(by: npcNodes[id], on: opponentNode(), from: (npcs[id].x, npcs[id].y), to: target, color: .white, arc: false)
                }
                floater("−\(value) ♥", at: (target.x + 0.4, target.y - 0.4), color: UIColor(red: 0.55, green: 0.85, blue: 0.6, alpha: 1))
            case let .note(text): session.toast = text
            }
        }
        session.activeFight = fight
        session.syncActive()
        // Полоска HP противника.
        if fightBar.parent == nil {
            let back = SKSpriteNode(color: UIColor(red: 0.12, green: 0.16, blue: 0.27, alpha: 0.85), size: CGSize(width: 21, height: 3.5))
            fightBar.addChild(back)
            fightBarFill.anchorPoint = CGPoint(x: 0, y: 0.5)
            fightBarFill.position = CGPoint(x: -10, y: 0)
            fightBarFill.zPosition = 0.1
            fightBar.addChild(fightBarFill)
            fightBar.zPosition = 9_300
            addChild(fightBar)
        }
        fightBar.isHidden = false
        fightBar.position = point(target.x, target.y, lift: session.activeTower != nil ? 50 : 30)
        fightBarFill.xScale = CGFloat(max(0, fight.npcHP / fight.npcMaxHP))
        guard fight.outcome != nil else { return }
        let npcId = session.activeNPC, towerId = session.activeTower
        let outcome = session.finishActive()
        fightBar.isHidden = true
        if let towerId {
            if outcome == .won {
                towerNodes[towerId]?.texture = texture(session.island.towers.first { $0.id == towerId }?.isFinal == true
                    ? ExploreSprites.bossTower(conquered: true).image : ExploreRenderer.tower(conquered: true))
                if let node = towerNodes[towerId] { flash(node) }
            } else if outcome == .lost {
                let home = session.lastCity; heroPosition = (Double(home.x), Double(home.y)); session.heroTile = home
            }
            return
        }
        guard let npcId, npcs.indices.contains(npcId) else { return }
        switch outcome {
        case .won, .persuaded: npcs[npcId].peaceful = true
        case .fled: npcs[npcId].calmUntil = now + NPCTier.calmAfterEncounter
        case .lost:
            npcs[npcId].calmUntil = now + NPCTier.calmAfterEncounter
            let home = session.lastCity
            heroPosition = (Double(home.x), Double(home.y))
            session.heroTile = home
        case nil: break
        }
    }

    // MARK: Анимация удара (15G.3)

    /// Узел противника текущего боя (активного или пошагового).
    private func opponentNode() -> SKSpriteNode? {
        if let id = session.activeNPC ?? session.encounterNPC, npcNodes.indices.contains(id) { return npcNodes[id] }
        if let id = session.activeTower ?? session.encounterTower { return towerNodes[id] }
        return nil
    }

    /// Выпад атакующего к цели, дуга удара и вспышка цели. Без «Уменьшения движения» — только вспышка.
    private func animateHit(by attacker: SKSpriteNode?, on target: SKSpriteNode?, from: (x: Double, y: Double), to: (x: Double, y: Double),
                            color: UIColor, arc: Bool = true) {
        let a = point(from.x, from.y), b = point(to.x, to.y)
        let length = max(0.01, hypot(b.x - a.x, b.y - a.y))
        if let attacker, !UIAccessibility.isReduceMotionEnabled, towerNodes.values.contains(attacker) == false {
            lunges[ObjectIdentifier(attacker)] = (now, (b.x - a.x) / length, (b.y - a.y) / length)
        }
        if arc, let target {
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: 7, startAngle: -.pi / 3, endAngle: .pi / 2.2, clockwise: false)
            let slash = SKShapeNode(path: path)
            slash.strokeColor = color == .red ? UIColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1) : UIColor(white: 1, alpha: 0.95)
            slash.lineWidth = 1.6
            slash.position = CGPoint(x: target.position.x, y: target.position.y + 9)
            slash.zPosition = 9_850
            if (b.x - a.x) < 0 { slash.xScale = -1 }
            addChild(slash)
            slash.run(.sequence([.group([.fadeOut(withDuration: 0.25), .scale(by: 1.3, duration: 0.25)]), .removeFromParent()]))
        }
        target?.run(.sequence([.colorize(with: color, colorBlendFactor: 0.85, duration: 0.05), .wait(forDuration: 0.08),
                               .colorize(withColorBlendFactor: 0, duration: 0.15)]))
    }

    /// Смещение выпада: 6 точек к цели и обратно за 0,25 с.
    private func lungeOffset(_ node: SKNode) -> CGPoint {
        guard let lunge = lunges[ObjectIdentifier(node)] else { return .zero }
        let t = (now - lunge.start) / 0.25
        guard t < 1 else { lunges[ObjectIdentifier(node)] = nil; return .zero }
        let k = CGFloat(sin(t * .pi)) * 6
        return CGPoint(x: lunge.dx * k, y: lunge.dy * k)
    }

    /// Пошаговая встреча: новые строки журнала → анимация на карте.
    private func watchEncounter(_ encounter: Encounter) {
        if encounter.log.count < seenLog { seenLog = 0 }
        let fresh = encounter.log.dropFirst(seenLog)
        seenLog = encounter.log.count
        let hero = (x: heroPosition.x, y: heroPosition.y)
        let target: (x: Double, y: Double)
        if let id = session.encounterNPC, npcs.indices.contains(id) { target = (npcs[id].x, npcs[id].y) }
        else if let id = session.encounterTower, let tower = session.island.towers.first(where: { $0.id == id }) { target = (Double(tower.position.x), Double(tower.position.y)) }
        else { return }
        for line in fresh {
            let number = line.split(separator: "−").last.map { String($0.prefix { $0.isNumber }) } ?? ""
            if line.hasPrefix("Спутник ударил") {
                floater("−\(number) ♥", at: (target.x + 0.4, target.y - 0.4), color: UIColor(red: 0.55, green: 0.85, blue: 0.6, alpha: 1))
            } else if line.contains("ударил: −") {
                floater("−\(number)", at: hero, color: UIColor(red: 0.66, green: 0.26, blue: 0.18, alpha: 1))
                animateHit(by: opponentNode(), on: heroNode, from: target, to: hero, color: .red)
            } else if line.contains(": −") {
                floater("−\(number)", at: target, color: UIColor(red: 0.95, green: 0.82, blue: 0.48, alpha: 1))
                animateHit(by: heroNode, on: opponentNode(), from: hero, to: target, color: .white)
            }
        }
    }

    /// Всплывающее число урона.
    private func floater(_ text: String, at tile: (x: Double, y: Double), color: UIColor) {
        let label = SKLabelNode(text: text)
        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 7
        label.fontColor = color
        label.position = point(tile.x, tile.y, lift: 18)
        label.zPosition = 9_900
        addChild(label)
        label.run(.sequence([.group([.moveBy(x: 0, y: 10, duration: 0.7), .fadeOut(withDuration: 0.7)]), .removeFromParent()]))
    }

    // MARK: Земля кусками (15A.5)

    /// Подгрузить куски вокруг камеры, убрать дальние; новые рисуются в фоне.
    private func loadChunks(synchronously: Bool) {
        let ground = session.ground
        let k = Double(ExploreGround.chunk)
        let center = (x: heroPosition.x, y: heroPosition.y)
        // Видимая область в клетках: экран × масштаб камеры, с запасом.
        let span = Double(max(size.width, size.height)) * Double(max(session.zoom, cameraNode.xScale)) / Double(ExploreRenderer.tileH) + 2 * k
        let reach = Int((span / k).rounded(.up)) / 2 + 1
        let ccx = Int(center.x / k), ccy = Int(center.y / k)
        var wanted = Set<Int>()
        for cy in (ccy - reach)...(ccy + reach) { for cx in (ccx - reach)...(ccx + reach) {
            guard cx >= 0, cy >= 0, cx < ground.chunksPerSide, cy < ground.chunksPerSide else { continue }
            wanted.insert(cy * ground.chunksPerSide + cx)
        } }
        for (key, node) in chunkNodes where !wanted.contains(key) {
            let cx = key % ground.chunksPerSide, cy = key / ground.chunksPerSide
            if abs(cx - ccx) > reach + 1 || abs(cy - ccy) > reach + 1 { node.removeFromParent(); chunkNodes[key] = nil }
        }
        let missing = wanted.filter { chunkNodes[$0] == nil && !chunkLoading.contains($0) }
            .sorted { abs($0 % ground.chunksPerSide - ccx) + abs($0 / ground.chunksPerSide - ccy) < abs($1 % ground.chunksPerSide - ccx) + abs($1 / ground.chunksPerSide - ccy) }
        for key in missing {
            let cx = key % ground.chunksPerSide, cy = key / ground.chunksPerSide
            if synchronously {
                install(ground.render(cx: cx, cy: cy), key: key)
                continue
            }
            chunkLoading.insert(key)
            Task { [weak self] in
                let chunk = await Task.detached(priority: .userInitiated) { ground.render(cx: cx, cy: cy) }.value
                self?.chunkLoading.remove(key)
                self?.install(chunk, key: key)
            }
        }
    }

    private func install(_ chunk: ExploreGround.Chunk?, key: Int) {
        // Пустой кусок (глубокая вода) — узел-заглушка, чтобы не рисовать снова.
        let node: SKSpriteNode
        if let chunk, let image = chunk.image {
            let texture = SKTexture(cgImage: image)
            texture.filteringMode = .nearest
            node = SKSpriteNode(texture: texture)
            node.anchorPoint = CGPoint(x: 0, y: 1)
            node.position = CGPoint(x: chunk.left, y: -chunk.top)
        } else {
            node = SKSpriteNode()
        }
        let chunks = session.ground.chunksPerSide
        node.zPosition = -10_000 + CGFloat(key % chunks + key / chunks)
        chunkNodes[key] = node
        addChild(node)
    }

    /// След «V» за кораблём на ходу.
    private func updateWake() {
        let moving = session.sailing != nil && (!path.isEmpty || stickMoving)
        if moving, wakeNode == nil {
            let emitter = SKEmitterNode()
            if let image = RGBACanvas(width: 2, height: 1, fill: 0xE6F0F4).image {
                emitter.particleTexture = SKTexture(cgImage: image)
                emitter.particleTexture?.filteringMode = .nearest
            }
            emitter.particleBirthRate = 40
            emitter.particleLifetime = 1.6
            emitter.particleAlpha = 0.85
            emitter.particleAlphaSpeed = -0.5
            emitter.particleSpeed = 6
            emitter.particleSpeedRange = 4
            emitter.emissionAngleRange = .pi * 2
            emitter.particlePositionRange = CGVector(dx: 6, dy: 3)
            emitter.targetNode = self
            emitter.zPosition = -5_000
            addChild(emitter)
            wakeNode = emitter
        } else if !moving, let wake = wakeNode {
            wake.particleBirthRate = 0
            wake.run(.sequence([.wait(forDuration: 1.7), .removeFromParent()]))
            wakeNode = nil
        }
        wakeNode?.position = point(heroPosition.x, heroPosition.y)
    }

    // MARK: Координаты

    private func point(_ x: Double, _ y: Double, lift: Double = 0) -> CGPoint {
        let p = ExploreRenderer.pixel(x: x, y: y, side: side)
        return CGPoint(x: p.x, y: -p.y + lift)
    }

    private func depth(_ x: Double, _ y: Double) -> CGFloat { CGFloat(x + y) }

    // MARK: Касание — идти туда

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.encounter == nil, !session.isFrozen, let touch = touches.first else { return }
        let location = touch.location(in: self)
        let t = ExploreRenderer.tile(px: Double(location.x), py: Double(-location.y), side: side)
        var target = TilePoint(Int(t.x.rounded()), Int(t.y.rounded()))
        // Касание памятника Epic — карточка (15B.2).
        if let monument = session.island.monuments.first(where: { $0.position.distance(to: target) <= 1.5 }) {
            session.monumentCard = monument
            return
        }
        // Активный режим: ходят джойстиком; касание дороги — только плашка.
        if session.mode == .active {
            if let road = session.island.road(at: target) { session.toast = road.caption }
            return
        }
        if session.sailing != nil {
            // На корабле: касание по воде — плыть туда; по суше — к ближайшей воде у этой точки (12B).
            let from = TilePoint(Int(heroPosition.x.rounded()), Int(heroPosition.y.rounded()))
            if session.island.isLand(target) {
                var best: TilePoint?, bestDistance = Double.infinity
                for dy in -8...8 { for dx in -8...8 {
                    let point = TilePoint(target.x + dx, target.y + dy)
                    guard point.x >= 0, point.y >= 0, point.x < side, point.y < side, !session.island.isLand(point) else { continue }
                    let distance = point.distance(to: target)
                    if distance < bestDistance { bestDistance = distance; best = point }
                } }
                guard let best else { return }
                target = best
            }
            guard let route = session.island.seaPath(from: from, to: target) else { return }
            path = Array(route.dropFirst())
            return
        }
        // Касание рядом с сундуком или костром ведёт прямо к нему (8C.9).
        let goals = session.island.chests.filter { !session.openedChests.contains($0.id) }.map(\.position)
            + session.island.campfires.filter { !session.litCampfires.contains($0.id) }.map(\.position)
        if let goal = goals.min(by: { $0.distance(to: target) < $1.distance(to: target) }), goal.distance(to: target) <= 1.5 { target = goal }
        let from = TilePoint(Int(heroPosition.x.rounded()), Int(heroPosition.y.rounded()))
        // Касание дороги — плашка с привычкой, процентом и видом (15A.2).
        if let road = session.island.road(at: target) { session.toast = road.caption }
        guard session.island.isWalkable(target), let route = session.island.path(from: from, to: target) else { return }
        path = Array(route.dropFirst())
    }

    // MARK: Кадр

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(0.1, currentTime - lastTime)
        lastTime = currentTime
        if let encounter = session.encounter {
            // Пошаговая встреча: анимация ударов на карте позади окна (15G.3).
            now += dt
            watchEncounter(encounter)
            layoutDynamic()
            return
        }
        seenLog = 0
        guard !session.isFrozen else { return }
        now += dt
        updateActiveFight(dt)
        chunkTicker += dt
        if chunkTicker > 0.2 { chunkTicker = 0; loadChunks(synchronously: false) }
        weatherTicker += dt
        if weatherTicker > 1 { weatherTicker = 0; updateWeather() }
        if session.heroTile != exploredTile {
            exploredTile = session.heroTile
            session.explore(around: exploredTile, radius: session.vision)
        }
        if session.mode == .active { moveByStick(dt) } else { moveHero(dt) }
        moveNPCs(dt)
        moveGhosts(dt)
        interact(dt)
        advanceClock(dt)
        layoutDynamic()
        updateFog()
        updateCompass()
        if abs(cameraNode.xScale - session.zoom) > 0.001 { cameraNode.run(.scale(to: session.zoom, duration: 0.15)) }
    }

    /// Сутки на острове — 12 минут (14.5); модель обновляется раз в игровую минуту.
    private func advanceClock(_ dt: Double) {
        clockAccumulator += dt / ExploreRules.daySeconds * 24
        if clockAccumulator >= 1.0 / 60 {
            session.clockHour = (session.clockHour + clockAccumulator).truncatingRemainder(dividingBy: 24)
            clockAccumulator = 0
        }
        // Плавные сумерки: 19–21 темнеет, 6–8 светает.
        let hour = session.clockHour
        let darkness: Double = switch hour {
        case 21..<24, 0..<6: 1
        case 19..<21: (hour - 19) / 2
        case 6..<8: 1 - (hour - 6) / 2
        default: 0
        }
        nightNode.alpha = CGFloat(darkness * 0.5)
        for node in glowNodes { node.alpha = CGFloat(darkness * 0.75) }
        let torch = (session.torchUntil ?? .distantPast) > .now
        heroGlow.alpha = CGFloat(darkness * (torch ? 0.9 : 0.35))
        heroGlow.position = point(heroPosition.x, heroPosition.y, lift: 6)
    }

    private func updateCompass() {
        guard (session.compassUntil ?? .distantPast) > .now else { compassNode.isHidden = true; return }
        let goals = session.island.chests.filter { !session.openedChests.contains($0.id) }.map(\.position)
        guard let goal = goals.min(by: { hypot(Double($0.x) - heroPosition.x, Double($0.y) - heroPosition.y) < hypot(Double($1.x) - heroPosition.x, Double($1.y) - heroPosition.y) }) else {
            compassNode.isHidden = true; return
        }
        let from = point(heroPosition.x, heroPosition.y), to = point(Double(goal.x), Double(goal.y))
        let angle = atan2(to.y - from.y, to.x - from.x)
        compassNode.isHidden = false
        compassNode.zRotation = angle - .pi / 2
        compassNode.position = CGPoint(x: cos(angle) * 40, y: sin(angle) * 40 + 20)
    }

    private func moveHero(_ dt: Double) {
        guard let next = path.first else { bobPhase = 0; return }
        defer { if session.sailing != nil { bobPhase = 0 } }
        let dx = Double(next.x) - heroPosition.x, dy = Double(next.y) - heroPosition.y
        let distance = hypot(dx, dy)
        let step = session.speed * dt
        if session.sailing != nil, abs(dx - dy) > 0.01 { shipFacesRight = dx - dy > 0 }
        if distance <= step {
            heroPosition = (Double(next.x), Double(next.y))
            path.removeFirst()
            session.steps += 1
            session.heroTile = next
        } else {
            heroPosition = (heroPosition.x + dx / distance * step, heroPosition.y + dy / distance * step)
        }
        bobPhase += dt * 12
        walkPhase += dt * session.speed * 2.2
    }

    private func moveNPCs(_ dt: Double) {
        let island = session.island
        let heroTile = TilePoint(Int(heroPosition.x.rounded()), Int(heroPosition.y.rounded()))
        // На корабле NPC не догоняют (море без встреч, 12B).
        let heroSafe = island.safeCity(at: heroTile) != nil || session.sailing != nil
        for index in npcs.indices {
            var state = npcs[index]
            let npc = island.npcs[index]
            // Спутник (14.5) идёт за героем, в том числе на корабле.
            if npc.id == session.companion?.id {
                state.peaceful = true
                state.chasing = false
                // В активном бою спутник встаёт рядом с противником, иначе идёт за героем.
                let opponent = activeTarget()
                let target = opponent.map { ($0.x + 0.8, $0.y - 0.6) } ?? (heroPosition.x - 0.9, heroPosition.y + 0.5)
                let dx = target.0 - state.x, dy = target.1 - state.y, distance = hypot(dx, dy)
                if distance > 6 || session.sailing != nil { state.x = target.0; state.y = target.1 }
                else if distance > 0.3 { let move = min(distance, session.speed * dt); state.x += dx / distance * move; state.y += dy / distance * move }
                npcs[index] = state
                continue
            }
            let toHero = hypot(heroPosition.x - state.x, heroPosition.y - state.y)
            // Активный бой: противник держится вплотную к герою, остальные NPC ждут.
            if session.mode == .active {
                if session.activeNPC == npc.id, session.activeFight != nil {
                    state.chasing = true
                    if toHero > 1.0 { step(&state, toward: heroPosition, speed: NPCTier.chaseSpeed * dt) }
                    npcs[index] = state
                    continue
                }
                if session.activeFight != nil { state.chasing = false; npcs[index] = state; continue }
            }
            state.chasing = !state.peaceful && now >= state.calmUntil && !heroSafe && toHero <= npc.tier.chaseRadius
            if state.chasing {
                step(&state, toward: heroPosition, speed: NPCTier.chaseSpeed * dt)
                if session.mode == .active, toHero <= ExploreRules.activeRange {
                    npcs[index] = state
                    session.startActive(npc: npc)
                    return
                }
                if session.mode == .turnBased, toHero < 0.8 {
                    npcs[index] = state
                    path = []
                    session.startEncounter(npc: npc)
                    onEncounter?()
                    return
                }
            } else {
                if state.target == nil || hypot(state.target!.x - state.x, state.target!.y - state.y) < 0.2 {
                    let candidate = TilePoint(npc.home.x + random.int(11) - 5, npc.home.y + random.int(11) - 5)
                    state.target = island.isWalkable(candidate) && island.safeCity(at: candidate) == nil ? (Double(candidate.x), Double(candidate.y)) : nil
                }
                if let target = state.target, !step(&state, toward: target, speed: (state.peaceful ? 0.6 : NPCTier.wanderSpeed) * dt) {
                    state.target = nil
                }
            }
            npcs[index] = state
        }
    }

    private func randomLand() -> TilePoint {
        for _ in 0..<200 {
            let point = TilePoint(random.int(side), random.int(side))
            if session.island.isLand(point) { return point }
        }
        return session.island.start
    }

    /// Призраки плывут к случайной точке острова (над водой тоже), затем выбирают новую.
    private func moveGhosts(_ dt: Double) {
        for index in ghostStates.indices {
            var ghost = ghostStates[index]
            let dx = ghost.tx - ghost.x, dy = ghost.ty - ghost.y
            let distance = hypot(dx, dy)
            if distance < 0.3 {
                let target = randomLand()
                ghost.tx = Double(target.x); ghost.ty = Double(target.y)
            } else {
                let step = min(distance, 1.2 * dt)
                ghost.x += dx / distance * step; ghost.y += dy / distance * step
            }
            ghostStates[index] = ghost
        }
    }

    /// Шаг к цели по суше; в воду и в безопасную зону NPC не заходят. false — шаг невозможен.
    @discardableResult
    private func step(_ state: inout NPCState, toward target: (x: Double, y: Double), speed: Double) -> Bool {
        let dx = target.x - state.x, dy = target.y - state.y
        let distance = hypot(dx, dy)
        guard distance > 0.01 else { return true }
        let move = min(speed, distance)
        let nx = state.x + dx / distance * move, ny = state.y + dy / distance * move
        let tile = TilePoint(Int(nx.rounded()), Int(ny.rounded()))
        guard session.island.isWalkable(tile), session.island.safeCity(at: tile) == nil else { return false }
        state.x = nx
        state.y = ny
        return true
    }

    private func interact(_ dt: Double) {
        let island = session.island
        let tile = session.heroTile
        let here = (x: heroPosition.x, y: heroPosition.y)
        func near(_ point: TilePoint, _ radius: Double) -> Bool { hypot(Double(point.x) - here.x, Double(point.y) - here.y) <= radius }
        // Бутылки — с берега или с корабля (14.5).
        if session.letter == nil, let bottle = island.bottles.first(where: { !session.readBottles.contains($0.id) && near($0.position, ExploreRules.pickupRadius) }) {
            session.readBottles.insert(bottle.id)
            bottleNodes[bottle.id]?.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            session.letter = bottle
        }
        guard session.sailing == nil else { return }
        // 15G.4: монументы полезного и восстановление от баффов; 15B.3: болото.
        for shrine in island.shrines where near(shrine.position, 1.5) && (session.buffs[shrine.buff] ?? 0) < shrine.strength {
            session.visit(shrine)
            if let node = shrineNodes[shrine.id] { flash(node) }
        }
        // 15C: смотровая площадка и клад.
        for lookout in island.lookouts where !session.usedLookouts.contains(lookout.id) && near(lookout.position, 1.5) {
            session.useLookout(lookout)
            lookoutNodes[lookout.id]?.texture = texture(ExploreSprites.lookout(used: true).image)
            if let node = lookoutNodes[lookout.id] { flash(node) }
        }
        if let spot = session.treasureSpot {
            if !treasureShown {
                treasureShown = true
                treasureNode.texture = texture(ExploreSprites.treasureMark().image)
                treasureNode.size = CGSize(width: 12, height: 8)
                treasureNode.position = point(Double(spot.x), Double(spot.y))
                treasureNode.zPosition = depth(Double(spot.x), Double(spot.y))
                treasureNode.isHidden = false
            }
            if !session.treasureFound && near(spot, 1.2) {
                session.openTreasure()
                treasureNode.texture = texture(ExploreSprites.treasureChest(opened: true).image)
                treasureNode.size = CGSize(width: 22, height: 18)
                flash(treasureNode)
            }
        }
        let water = session.buff(.water), vegetables = session.buff(.vegetables)
        let swampDamage = island.isSwamp(tile) ? ExploreRules.swampHPPerSecond : 0
        if water > 0 || vegetables > 0 || swampDamage > 0 {
            session.hp = max(1, min(session.hero.maxHP, session.hp + session.hero.maxHP * (water - swampDamage) * dt))
            session.mp = min(session.hero.maxMP, session.mp + session.hero.maxMP * vegetables * dt)
        }
        if let region = island.region(at: tile) { session.visitedRegions.insert(region.id) }
        for village in island.villages where !session.visitedVillages.contains(village.id) && near(village.center, 1.5) {
            session.visitedVillages.insert(village.id)
        }
        for light in island.lighthouses where !session.litLighthouses.contains(light.id) && near(light.position, 1.5) {
            session.litLighthouses.insert(light.id)
            session.lighthouseUntil = .now + ExploreRules.lighthouseSeconds
            lightNodes[light.id]?.texture = texture(ExploreRenderer.lighthouse(lit: true))
            if let node = lightNodes[light.id] { flash(node) }
            session.toast = "Маяк «\(light.title)» зажжён: обзор +\(Int(ExploreRules.lighthouseVisionBonus))"
        }
        if let tower = island.towers.first(where: { !session.conqueredTowers.contains($0.id) && near($0.position, 1.2) }) {
            if session.mode == .active {
                if session.activeFight == nil { session.startActiveGuardian(tower) }
                return
            }
            path = []
            session.startGuardian(tower)
            onEncounter?()
            return
        }
        if let city = island.safeCity(at: tile) {
            session.visitedCities.insert(city.id)
            // Доска заданий: первое посещение города берёт его задание.
            if let task = island.tasks.first(where: { $0.cityId == city.id }) { session.takeTask(task) }
            session.lastCity = city.center
            // В городе +10% в секунду (09, раздел 5); обновляем модель не чаще раза в 0,25 с.
            restAccumulator += dt
            if restAccumulator >= 0.25 {
                session.hp = min(session.hero.maxHP, session.hp + session.hero.maxHP * ExploreRules.cityRestorePerSecond * restAccumulator)
                session.mp = min(session.hero.maxMP, session.mp + session.hero.maxMP * ExploreRules.cityRestorePerSecond * restAccumulator)
                restAccumulator = 0
            }
        }
        for chest in island.chests where !session.openedChests.contains(chest.id) && chest.position.distance(to: tile) <= 1 {
            session.openedChests.insert(chest.id)
            chestNodes[chest.id]?.texture = texture(ExploreRenderer.chest(opened: true))
            if let node = chestNodes[chest.id] { flash(node) }
            session.toast = "Сундук: \(chest.title)" + (session.addItem(chest.item) ? " · \(chest.item.title)" : " · сумка полна")
            if let fragment = chest.fragment { session.findFragment(fragment, in: chest) }
        }
        for fire in island.campfires where !session.litCampfires.contains(fire.id) && fire.position.distance(to: tile) <= 1 {
            session.litCampfires.insert(fire.id)
            fireNodes[fire.id]?.texture = texture(ExploreRenderer.campfire(lit: true))
            if let node = fireNodes[fire.id] { flash(node) }
            let share = ExploreRules.campfireShare * fire.quality
            session.hp = min(session.hero.maxHP, session.hp + session.hero.maxHP * share)
            session.mp = min(session.hero.maxMP, session.mp + session.hero.maxMP * share)
            session.toast = "Костёр: +\(Int((share * 100).rounded()))% HP и MP"
        }
        session.settleTasks()
    }

    /// Короткая вспышка при находке: увеличение и золотое кольцо.
    private func flash(_ node: SKSpriteNode) {
        node.run(.sequence([.scale(to: 1.8, duration: 0.12), .scale(to: 1, duration: 0.2)]))
        let ring = SKShapeNode(circleOfRadius: 6)
        ring.strokeColor = UIColor(red: 0.95, green: 0.82, blue: 0.48, alpha: 1)
        ring.lineWidth = 2
        ring.position = CGPoint(x: node.position.x, y: node.position.y + 5)
        ring.zPosition = 9_800
        addChild(ring)
        ring.run(.sequence([.group([.scale(to: 4, duration: 0.45), .fadeOut(withDuration: 0.45)]), .removeFromParent()]))
    }

    private func texture(_ image: CGImage?) -> SKTexture? {
        guard let image else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }

    private func layoutDynamic() {
        // Кадры шага (15A.7): герой — пока идёт, NPC — пока двигаются.
        let walking = (!path.isEmpty || stickMoving) && session.sailing == nil
        if !heroFrames.isEmpty { heroNode.texture = heroFrames[walking ? Int(walkPhase) % 4 : 0] }
        let bob = heroFrames.isEmpty && walking ? abs(sin(bobPhase)) * 1.5 : 0
        // На корабле герой стоит на палубе у кормы, корабль идёт вместе с ним.
        let sailing = session.sailing
        heroNode.position = point(heroPosition.x, heroPosition.y, lift: sailing == nil ? bob : 3)
        heroNode.position += lungeOffset(heroNode)
        if sailing != nil { heroNode.position.x += 4 }
        heroNode.zPosition = depth(heroPosition.x, heroPosition.y) + (sailing == nil ? 0.5 : 0.7)
        for (index, node) in shipNodes.enumerated() {
            if index == sailing {
                // Спрайт идёт вправо-вниз; курс влево — зеркало. Парус «дышит» на ходу.
                node.xScale = abs(node.xScale) * (shipFacesRight ? 1 : -1)
                if !shipFrames.isEmpty { node.texture = shipFrames[path.isEmpty && !stickMoving ? 0 : Int(now * 5) % 4] }
                node.position = point(heroPosition.x, heroPosition.y, lift: sin(now * 2) * 0.8)
                node.zPosition = depth(heroPosition.x, heroPosition.y) + 0.6
            } else {
                let tile = session.ships[index]
                node.position = point(Double(tile.x), Double(tile.y), lift: sin(now * 1.5 + Double(index)) * 0.5)
                node.zPosition = depth(Double(tile.x), Double(tile.y)) + 0.3
            }
        }
        cameraNode.position = point(heroPosition.x, heroPosition.y, lift: 20)
        updateWake()
        for (index, ghost) in ghostStates.enumerated() {
            ghostNodes[index].position = point(ghost.x, ghost.y, lift: 14 + sin(now * 2 + Double(index)) * 3)
        }
        for (index, state) in npcs.enumerated() {
            let moved = hypot(npcNodes[index].position.x - point(state.x, state.y).x, npcNodes[index].position.y - point(state.x, state.y).y) > 0.01
            if npcFrames.indices.contains(index), !npcFrames[index].isEmpty {
                npcNodes[index].texture = npcFrames[index][moved ? Int(now * 6 + Double(index)) % 4 : 0]
            }
            let lunge = session.island.npcs[index].id == session.companion?.id && now - companionLunge < 0.3
            npcNodes[index].position = point(state.x, state.y, lift: lunge ? sin((now - companionLunge) / 0.3 * .pi) * 4 : 0)
            npcNodes[index].position += lungeOffset(npcNodes[index])
            npcNodes[index].zPosition = depth(state.x, state.y) + 0.4
            npcBadges[index].fillColor = state.peaceful
                ? UIColor(red: 0.18, green: 0.42, blue: 0.31, alpha: 1)
                : state.chasing ? UIColor(red: 0.66, green: 0.26, blue: 0.18, alpha: 1) : UIColor(white: 0.6, alpha: 1)
        }
    }

    private func updateFog() {
        let hole = session.vision * Double(ExploreRenderer.tileW) * 0.75
        guard abs(hole - fogHole) > 0.5 else { return }
        fogHole = hole
        if let image = ExploreRenderer.fog(size: 512, hole: hole / 2) {
            fogNode.texture = SKTexture(cgImage: image)
            fogNode.size = CGSize(width: 1024, height: 1024)
        }
    }

    /// Вернуться на остров из пещеры — на другом её конце (15C.2).
    func placeHero(at tile: TilePoint) {
        path = []
        heroPosition = (Double(tile.x), Double(tile.y))
        session.heroTile = tile
        lastTime = 0
        layoutDynamic()
    }

    // MARK: Корабль (12B)

    /// «Сесть на корабль»: герой переходит на палубу, дальше управление кораблём.
    func boardShip() {
        guard let index = session.boardableShip else { return }
        let tile = session.ships[index]
        path = []
        session.sailing = index
        heroPosition = (Double(tile.x), Double(tile.y))
        session.heroTile = tile
        layoutDynamic()
    }

    /// «Сойти на берег»: корабль остаётся у этого берега, герой — на соседней суше.
    func disembark() {
        guard let index = session.sailing, let landing = session.landingTile else { return }
        path = []
        session.ships[index] = session.heroTile
        session.sailing = nil
        heroPosition = (Double(landing.x), Double(landing.y))
        session.heroTile = landing
        layoutDynamic()
    }

    // MARK: После встречи

    func resolveEncounter(_ outcome: EncounterOutcome?, npcId: Int?, towerId: Int? = nil) {
        if let towerId {
            if outcome == .won {
                towerNodes[towerId]?.texture = texture(session.island.towers.first { $0.id == towerId }?.isFinal == true
                    ? ExploreSprites.bossTower(conquered: true).image : ExploreRenderer.tower(conquered: true))
                if let node = towerNodes[towerId] { flash(node) }
            } else {
                // Побег или поражение — отойти от башни, чтобы встреча не началась снова.
                if outcome == .lost { let home = session.lastCity; heroPosition = (Double(home.x), Double(home.y)); session.heroTile = home }
                else if let tower = session.island.towers.first(where: { $0.id == towerId }) {
                    let dx = heroPosition.x - Double(tower.position.x), dy = heroPosition.y - Double(tower.position.y)
                    let length = max(0.01, hypot(dx, dy))
                    let target = TilePoint(Int((heroPosition.x + dx / length * 3).rounded()), Int((heroPosition.y + dy / length * 3).rounded()))
                    if session.island.isWalkable(target) { heroPosition = (Double(target.x), Double(target.y)); session.heroTile = target }
                }
            }
            path = []
            layoutDynamic()
            return
        }
        guard let npcId, npcs.indices.contains(npcId) else { return }
        switch outcome {
        case .won, .persuaded:
            npcs[npcId].peaceful = true
        case .fled:
            npcs[npcId].calmUntil = now + NPCTier.calmAfterEncounter
            // Герой отскакивает на 2 клетки от NPC, если там суша.
            let dx = heroPosition.x - npcs[npcId].x, dy = heroPosition.y - npcs[npcId].y
            let length = max(0.01, hypot(dx, dy))
            let target = TilePoint(Int((heroPosition.x + dx / length * 2).rounded()), Int((heroPosition.y + dy / length * 2).rounded()))
            if session.island.isWalkable(target) { heroPosition = (Double(target.x), Double(target.y)); session.heroTile = target }
        case .lost:
            npcs[npcId].calmUntil = now + NPCTier.calmAfterEncounter
            let home = session.lastCity
            heroPosition = (Double(home.x), Double(home.y))
            session.heroTile = home
        case nil:
            break
        }
        path = []
        layoutDynamic()
    }
}

private extension CGPoint {
    static func += (lhs: inout CGPoint, rhs: CGPoint) { lhs = CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
}
