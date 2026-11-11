import SpriteKit
import Domain

/// Сцена острова (8B): изометрия, камера за героем, ходьба касанием по пути через сушу, NPC бродят и преследуют.
final class ExploreScene: SKScene {
    let session: ExploreSession
    /// Встреча началась — экран SwiftUI показывает окно встречи.
    var onEncounter: (() -> Void)?

    private var side: Int { session.island.side }
    private let heroNode = SKSpriteNode()
    private let heroLabel = SKLabelNode()
    private let cameraNode = SKCameraNode()
    private let fogNode = SKSpriteNode()
    private var fogHole: Double = 0
    private var npcNodes: [SKSpriteNode] = []
    private var npcBadges: [SKShapeNode] = []
    private var chestNodes: [Int: SKSpriteNode] = [:]
    private var fireNodes: [Int: SKSpriteNode] = [:]

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
        heroPosition = (Double(session.island.start.x), Double(session.island.start.y))
        random = ExploreRandom(session.seed ^ 0x5EED)
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0x3F / 255, green: 0x6E / 255, blue: 0x9C / 255, alpha: 1)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func didMove(to view: SKView) {
        guard children.isEmpty else { return }
        let island = session.island
        if let image = ExploreRenderer.islandImage(island, seed: session.seed, season: session.season) {
            let texture = SKTexture(cgImage: image)
            texture.filteringMode = .nearest
            let ground = SKSpriteNode(texture: texture)
            ground.anchorPoint = CGPoint(x: 0, y: 1)
            ground.position = .zero
            ground.zPosition = -10_000
            addChild(ground)
        }
        for city in island.cities + island.villages {
            let label = SKLabelNode(text: city.name)
            label.fontName = "HelveticaNeue-Bold"
            // Подписи — в масштабе персонажей (×0,5): мельче вместе с ними.
            label.fontSize = 4
            label.fontColor = city.isCity ? .white : UIColor(red: 0.12, green: 0.16, blue: 0.27, alpha: 1)
            label.position = point(Double(city.center.x), Double(city.center.y), lift: city.isCity ? 24 : 14)
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
        let looks: [HeroAppearance] = [
            HeroAppearance(hair: .red, skin: .light, outfit: .archer), HeroAppearance(hair: .blond, skin: .tan, outfit: .warrior),
            HeroAppearance(hair: .black, skin: .deep, outfit: .mage), HeroAppearance(hair: .dark, skin: .medium, outfit: .baller),
        ]
        let colors: [UInt32] = [0x8A4B3A, 0x3E5C8A, 0x6B4FA3, 0x2F6B4F]
        for npc in island.npcs {
            let node = sprite(ExploreRenderer.person(looks[npc.id % looks.count], accent: colors[npc.id % colors.count]))
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.setScale(Self.characterScale)
            addChild(node)
            npcNodes.append(node)
            let badge = SKShapeNode(rectOf: CGSize(width: 4, height: 4))
            badge.strokeColor = UIColor(red: 0.12, green: 0.16, blue: 0.27, alpha: 1)
            badge.lineWidth = 1
            badge.position = CGPoint(x: 0, y: 32)
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
        if let appearance = session.appearance, let image = ExploreRenderer.person(appearance, accent: session.accent) {
            heroNode.texture = SKTexture(cgImage: image)
            heroNode.texture?.filteringMode = .nearest
            heroNode.size = CGSize(width: image.width, height: image.height)
        } else {
            heroNode.color = UIColor(red: 0.18, green: 0.42, blue: 0.31, alpha: 1)
            heroNode.size = CGSize(width: 8, height: 14)
        }
        heroNode.anchorPoint = CGPoint(x: 0.5, y: 0)
        heroNode.setScale(Self.characterScale)
        addChild(heroNode)
        heroLabel.text = "\(session.hero.rankLetter) · Герой"
        heroLabel.fontName = "HelveticaNeue-Bold"
        heroLabel.fontSize = 6
        heroLabel.fontColor = UIColor(red: 0.12, green: 0.16, blue: 0.27, alpha: 1)
        heroLabel.position = CGPoint(x: 0, y: 34)
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
        fogNode.zPosition = 20_000
        cameraNode.addChild(fogNode)
        if session.precipitation { cameraNode.addChild(precipitationNode(snow: session.season == .winter)) }
        updateFog()
        layoutDynamic()
    }

    /// Персонажи мельче при прежнем масштабе карты (8C.9).
    static let characterScale: CGFloat = 0.5

    /// Осадки поверх острова: дождь или снег (зимой).
    private func precipitationNode(snow: Bool) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        let canvas = RGBACanvas(width: snow ? 2 : 1, height: snow ? 2 : 5, fill: snow ? 0xF4F7F9 : 0xBFD3E6)
        if let image = canvas.image {
            emitter.particleTexture = SKTexture(cgImage: image)
            emitter.particleTexture?.filteringMode = .nearest
        }
        emitter.particleBirthRate = snow ? 60 : 160
        emitter.particleLifetime = snow ? 6 : 1.4
        emitter.particlePositionRange = CGVector(dx: 520, dy: 40)
        emitter.position = CGPoint(x: 0, y: 260)
        emitter.emissionAngle = snow ? -.pi / 2 : -.pi / 2 - 0.25
        emitter.emissionAngleRange = snow ? 0.6 : 0.05
        emitter.particleSpeed = snow ? 40 : 320
        emitter.particleSpeedRange = snow ? 20 : 60
        emitter.particleAlpha = snow ? 0.9 : 0.6
        emitter.particleRotation = snow ? 0 : 0.25
        emitter.zPosition = 19_000
        emitter.advanceSimulationTime(6)
        return emitter
    }

    private func sprite(_ image: CGImage?) -> SKSpriteNode {
        guard let image else { return SKSpriteNode(color: .clear, size: .zero) }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return SKSpriteNode(texture: texture)
    }

    // MARK: Координаты

    private func point(_ x: Double, _ y: Double, lift: Double = 0) -> CGPoint {
        let p = ExploreRenderer.pixel(x: x, y: y, side: side)
        return CGPoint(x: p.x, y: -p.y + lift)
    }

    private func depth(_ x: Double, _ y: Double) -> CGFloat { CGFloat(x + y) }

    // MARK: Касание — идти туда

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.encounter == nil, let touch = touches.first else { return }
        let location = touch.location(in: self)
        let t = ExploreRenderer.tile(px: Double(location.x), py: Double(-location.y), side: side)
        var target = TilePoint(Int(t.x.rounded()), Int(t.y.rounded()))
        // Касание рядом с сундуком или костром ведёт прямо к нему (8C.9).
        let goals = session.island.chests.filter { !session.openedChests.contains($0.id) }.map(\.position)
            + session.island.campfires.filter { !session.litCampfires.contains($0.id) }.map(\.position)
        if let goal = goals.min(by: { $0.distance(to: target) < $1.distance(to: target) }), goal.distance(to: target) <= 1.5 { target = goal }
        let from = TilePoint(Int(heroPosition.x.rounded()), Int(heroPosition.y.rounded()))
        guard session.island.isLand(target), let route = session.island.path(from: from, to: target) else { return }
        path = Array(route.dropFirst())
    }

    // MARK: Кадр

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(0.1, currentTime - lastTime)
        lastTime = currentTime
        guard session.encounter == nil else { return }
        now += dt
        moveHero(dt)
        moveNPCs(dt)
        moveGhosts(dt)
        interact(dt)
        layoutDynamic()
        updateFog()
        if abs(cameraNode.xScale - session.zoom) > 0.001 { cameraNode.run(.scale(to: session.zoom, duration: 0.15)) }
    }

    private func moveHero(_ dt: Double) {
        guard let next = path.first else { bobPhase = 0; return }
        let dx = Double(next.x) - heroPosition.x, dy = Double(next.y) - heroPosition.y
        let distance = hypot(dx, dy)
        let step = session.speed * dt
        if distance <= step {
            heroPosition = (Double(next.x), Double(next.y))
            path.removeFirst()
            session.steps += 1
            session.heroTile = next
        } else {
            heroPosition = (heroPosition.x + dx / distance * step, heroPosition.y + dy / distance * step)
        }
        bobPhase += dt * 12
    }

    private func moveNPCs(_ dt: Double) {
        let island = session.island
        let heroTile = TilePoint(Int(heroPosition.x.rounded()), Int(heroPosition.y.rounded()))
        let heroSafe = island.safeCity(at: heroTile) != nil
        for index in npcs.indices {
            var state = npcs[index]
            let npc = island.npcs[index]
            let toHero = hypot(heroPosition.x - state.x, heroPosition.y - state.y)
            state.chasing = !state.peaceful && now >= state.calmUntil && !heroSafe && toHero <= npc.tier.chaseRadius
            if state.chasing {
                step(&state, toward: heroPosition, speed: NPCTier.chaseSpeed * dt)
                if toHero < 0.8 {
                    npcs[index] = state
                    path = []
                    session.startEncounter(npc: npc)
                    onEncounter?()
                    return
                }
            } else {
                if state.target == nil || hypot(state.target!.x - state.x, state.target!.y - state.y) < 0.2 {
                    let candidate = TilePoint(npc.home.x + random.int(11) - 5, npc.home.y + random.int(11) - 5)
                    state.target = island.isLand(candidate) && island.safeCity(at: candidate) == nil ? (Double(candidate.x), Double(candidate.y)) : nil
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
        guard session.island.isLand(tile), session.island.safeCity(at: tile) == nil else { return false }
        state.x = nx
        state.y = ny
        return true
    }

    private func interact(_ dt: Double) {
        let island = session.island
        let tile = session.heroTile
        if let city = island.safeCity(at: tile) {
            session.visitedCities.insert(city.id)
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
            session.toast = "Сундук: \(chest.title)"
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
        let bob = path.isEmpty ? 0 : abs(sin(bobPhase)) * 1.5
        heroNode.position = point(heroPosition.x, heroPosition.y, lift: bob)
        heroNode.zPosition = depth(heroPosition.x, heroPosition.y) + 0.5
        cameraNode.position = point(heroPosition.x, heroPosition.y, lift: 20)
        for (index, ghost) in ghostStates.enumerated() {
            ghostNodes[index].position = point(ghost.x, ghost.y, lift: 14 + sin(now * 2 + Double(index)) * 3)
        }
        for (index, state) in npcs.enumerated() {
            npcNodes[index].position = point(state.x, state.y)
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

    // MARK: После встречи

    func resolveEncounter(_ outcome: EncounterOutcome?, npcId: Int?) {
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
            if session.island.isLand(target) { heroPosition = (Double(target.x), Double(target.y)); session.heroTile = target }
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
