import SpriteKit
import Domain

/// Пещера (15C.2, макет ExploreCave): тёмная подкарта под горой. Видно 3 клетки (с факелом — 9),
/// два тайника и выход, который светится сам. Ходьба — по режиму игры: касание или джойстик.
final class CaveScene: SKScene {
    let session: ExploreSession
    let cave: IslandCave
    /// Герой дошёл до выхода.
    var onLeave: (() -> Void)?

    private let heroNode = SKSpriteNode()
    private var heroFrames: [SKTexture] = []
    private var heroBackFrames: [SKTexture] = []
    private var facing = 0
    private let cameraNode = SKCameraNode()
    private let darkNode = SKSpriteNode()
    private var darkRadius: CGFloat = 0
    private var chestNodes: [SKSpriteNode] = []
    private let exitNode = SKSpriteNode()
    private var heroPosition: (x: Double, y: Double)
    private var path: [TilePoint] = []
    private var lastTime: TimeInterval = 0
    private var walkPhase = 0.0
    private var moving = false
    /// Цель — выход внутри пещеры (вошёл через выход — идёт к старту).
    private let goal: TilePoint
    private var side: Int { cave.side }

    init(session: ExploreSession, cave: IslandCave, size: CGSize) {
        self.session = session
        self.cave = cave
        let entry = session.enteredFromExit ? cave.inner : cave.start
        goal = session.enteredFromExit ? cave.start : cave.inner
        heroPosition = (Double(entry.x), Double(entry.y))
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.055, alpha: 1)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func didMove(to view: SKView) {
        guard children.isEmpty else { return }
        if let image = Self.render(cave) {
            let texture = SKTexture(cgImage: image)
            texture.filteringMode = .nearest
            let ground = SKSpriteNode(texture: texture)
            ground.anchorPoint = CGPoint(x: 0, y: 1)
            ground.position = .zero
            ground.zPosition = -1000
            addChild(ground)
        }
        for (index, chest) in cave.chests.enumerated() {
            let opened = session.openedCaveChests.contains("\(cave.id)-\(index)")
            let node = SKSpriteNode(texture: texture(ExploreRenderer.chest(opened: opened)))
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.position = point(Double(chest.x), Double(chest.y))
            node.zPosition = CGFloat(chest.x + chest.y)
            chestNodes.append(node)
            addChild(node)
        }
        // Выход — тёплое пятно света.
        var glow = RGBACanvas(width: 24, height: 16, fill: nil)
        for y in 0..<16 { for x in 0..<24 {
            let d = hypot((Double(x) - 11.5) / 12, (Double(y) - 7.5) / 8)
            if d < 1 { glow.setAlpha(x, y, d < 0.45 ? 0xFFFCE6 : 0xF2D27A, alpha: min(1, (1 - d) * 1.6)) }
        } }
        exitNode.texture = glow.image.map { SKTexture(cgImage: $0) }
        exitNode.size = CGSize(width: 24, height: 16)
        exitNode.position = point(Double(goal.x), Double(goal.y), lift: 4)
        exitNode.zPosition = 900
        exitNode.run(.repeatForever(.sequence([.fadeAlpha(to: 0.6, duration: 0.8), .fadeAlpha(to: 1, duration: 0.8)])))
        addChild(exitNode)

        if let appearance = session.appearance {
            let pixels = ExploreCharacters.pixels(appearance, accent: session.accent)
            let weapon = HeroComposer.weaponLayers(appearance, accent: session.accent)
            heroFrames = ExploreCharacters.frames(pixels, outline: false, weapon: weapon).compactMap { texture($0) }
            heroBackFrames = ExploreCharacters.backFrames(pixels, hair: appearance.hair.hex, outline: false, weapon: weapon).compactMap { texture($0) }
            heroNode.texture = heroFrames.first
            heroNode.size = CGSize(width: ExploreCharacters.frameSize.width, height: ExploreCharacters.frameSize.height)
            heroNode.anchorPoint = CGPoint(x: 0.5, y: CGFloat(ExploreCharacters.feetFromBottom) / CGFloat(ExploreCharacters.frameSize.height))
            heroNode.setScale(0.25)
        } else {
            heroNode.color = UIColor(red: 0.18, green: 0.42, blue: 0.31, alpha: 1)
            heroNode.size = CGSize(width: 8, height: 14)
            heroNode.anchorPoint = CGPoint(x: 0.5, y: 0)
        }
        addChild(heroNode)
        camera = cameraNode
        cameraNode.setScale(0.45)
        addChild(cameraNode)
        darkNode.zPosition = 5000
        cameraNode.addChild(darkNode)
        layout()
    }

    private func texture(_ image: CGImage?) -> SKTexture? {
        guard let image else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }

    private func point(_ x: Double, _ y: Double, lift: Double = 0) -> CGPoint {
        let p = ExploreRenderer.pixel(x: x, y: y, side: side)
        return CGPoint(x: p.x, y: -p.y + lift)
    }

    // MARK: Ходьба

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.mode == .turnBased, !session.isFrozen, let touch = touches.first else { return }
        let location = touch.location(in: self)
        let t = ExploreRenderer.tile(px: Double(location.x), py: Double(-location.y), side: side)
        let target = TilePoint(Int(t.x.rounded()), Int(t.y.rounded()))
        let from = TilePoint(Int(heroPosition.x.rounded()), Int(heroPosition.y.rounded()))
        if let route = cave.path(from: from, to: target) { path = route }
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(0.1, currentTime - lastTime)
        lastTime = currentTime
        guard !session.isFrozen else { return }
        // Время на острове идёт и в пещере.
        session.clockHour = (session.clockHour + dt / ExploreRules.daySeconds * 24).truncatingRemainder(dividingBy: 24)
        if session.mode == .active { moveByStick(dt) } else { moveAlongPath(dt) }
        interact()
        layout()
    }

    private func moveAlongPath(_ dt: Double) {
        guard let next = path.first else { moving = false; return }
        moving = true
        let dx = Double(next.x) - heroPosition.x, dy = Double(next.y) - heroPosition.y
        let distance = hypot(dx, dy), step = session.speed * dt
        facing = ExploreScene.facing(dx: dx, dy: dy, current: facing)
        if distance <= step { heroPosition = (Double(next.x), Double(next.y)); path.removeFirst() }
        else { heroPosition = (heroPosition.x + dx / distance * step, heroPosition.y + dy / distance * step) }
        walkPhase += dt * session.speed * 2.2
    }

    private func moveByStick(_ dt: Double) {
        let stick = session.stick
        let magnitude = min(1, hypot(stick.dx, stick.dy))
        guard magnitude > 0.15 else { moving = false; return }
        var tx = Double(stick.dx) / 16 + Double(stick.dy) / 8, ty = Double(stick.dy) / 8 - Double(stick.dx) / 16
        let length = max(0.0001, hypot(tx, ty))
        tx /= length; ty /= length
        let step = session.speed * dt * magnitude
        facing = ExploreScene.facing(dx: tx, dy: ty, current: facing)
        func floor(_ x: Double, _ y: Double) -> Bool { cave.isFloor(TilePoint(Int(x.rounded()), Int(y.rounded()))) }
        let (x, y) = heroPosition
        if floor(x + tx * step, y + ty * step) { heroPosition = (x + tx * step, y + ty * step) }
        else if floor(x + tx * step, y) { heroPosition = (x + tx * step, y) }
        else if floor(x, y + ty * step) { heroPosition = (x, y + ty * step) }
        else { moving = false; return }
        moving = true
        walkPhase += dt * session.speed * 2.2
    }

    private func interact() {
        for (index, chest) in cave.chests.enumerated() {
            let key = "\(cave.id)-\(index)"
            guard !session.openedCaveChests.contains(key), hypot(Double(chest.x) - heroPosition.x, Double(chest.y) - heroPosition.y) <= 1 else { continue }
            session.openedCaveChests.insert(key)
            chestNodes[index].texture = texture(ExploreRenderer.chest(opened: true))
            let item = cave.items[index]
            session.toast = "Тайник пещеры \(cave.chests.indices.filter { session.openedCaveChests.contains("\(cave.id)-\($0)") }.count)/\(cave.chests.count)"
                + (session.addItem(item) ? " · \(item.title)" : " · сумка полна")
        }
        if hypot(Double(goal.x) - heroPosition.x, Double(goal.y) - heroPosition.y) <= 0.8 {
            onLeave?()
            onLeave = nil
        }
    }

    private func layout() {
        if !heroFrames.isEmpty {
            let set = facing >= 2 && !heroBackFrames.isEmpty ? heroBackFrames : heroFrames
            heroNode.texture = set[moving ? Int(walkPhase) % 4 : 0]
            heroNode.xScale = abs(heroNode.xScale) * (facing % 2 == 0 ? 1 : -1)
        }
        heroNode.position = point(heroPosition.x, heroPosition.y)
        heroNode.zPosition = CGFloat(heroPosition.x + heroPosition.y) + 0.5
        cameraNode.position = point(heroPosition.x, heroPosition.y, lift: 16)
        // Темнота: дыра света вокруг героя — 3 клетки, с факелом 9.
        let torch = (session.torchUntil ?? .distantPast) > .now
        let radius = CGFloat((torch ? ExploreRules.caveTorchVision : ExploreRules.caveVision) * Double(ExploreRenderer.tileW) * 0.75)
        if abs(radius - darkRadius) > 0.5 {
            darkRadius = radius
            var canvas = RGBACanvas(width: 256, height: 256, fill: nil)
            let hole = Double(radius) / 4
            for y in 0..<256 { for x in 0..<256 {
                let d = hypot(Double(x) - 127.5, (Double(y) - 127.5) * 1.4)
                let alpha = min(0.96, max(0, (d - hole) / (hole * 0.6)) * 0.96)
                if alpha > 0 { canvas.setAlpha(x, y, 0x050508, alpha: alpha) }
            } }
            darkNode.texture = canvas.image.map { SKTexture(cgImage: $0) }
            darkNode.size = CGSize(width: 1024 * 2, height: 1024 * 2)
        }
    }

    // MARK: Рисунок пещеры

    /// Пол — тёмная земля с кристаллами, стены — поднятые блоки камня.
    static func render(_ cave: IslandCave) -> CGImage? {
        let n = cave.side, size = ExploreRenderer.imageSize(side: n)
        var canvas = RGBACanvas(width: size.width, height: size.height, fill: 0x0A0A0E)
        let tw = ExploreRenderer.tileW, th = ExploreRenderer.tileH
        for d in 0..<(2 * n - 1) {
            for x in 0...d where x < n {
                let y = d - x
                guard y < n else { continue }
                let wall = !cave.isFloor(TilePoint(x, y))
                let p = ExploreRenderer.pixel(x: Double(x), y: Double(y), side: n)
                let cx = Int(p.x), cy = Int(p.y), e = wall ? 10 : 0
                if wall {
                    for dx in (-tw / 2)..<(tw / 2) {
                        var bottom = 0
                        for py in 0..<th {
                            let half = py < th / 2 ? (py + 1) * 2 : (th - py) * 2
                            if dx >= -half && dx < half { bottom = py }
                        }
                        for dy in 0...e { canvas.set(cx + dx, cy - th / 2 + bottom - dy, dx < 0 ? 0x362E28 : 0x2A2420) }
                    }
                }
                for py in 0..<th {
                    let half = py < th / 2 ? (py + 1) * 2 : (th - py) * 2
                    for dx in -half..<half {
                        let sx = cx + dx, sy = cy - th / 2 + py - e
                        let h = Pix.hash(sx, sy, 3)
                        var c: UInt32 = wall ? (h < 0.5 ? 0x4A4038 : 0x423A32) : (h < 0.6 ? 0x382C22 : 0x30261E)
                        if !wall && Pix.hash(sx, sy, 9) < 0.02 { c = 0x6E96AA }
                        canvas.set(sx, sy, c)
                    }
                }
            }
        }
        return canvas.image
    }
}
