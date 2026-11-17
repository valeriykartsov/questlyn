import SpriteKit
import Domain

/// Зал Чёрной башни (16.5, макет ExploreStage16): тёмный каменный зал 11×11, факелы на стенах, босс у дальней стены.
/// Подойти к боссу — бой (пошаговое окно в обоих режимах); выход — у входа.
final class HallScene: SKScene {
    let session: ExploreSession
    let tower: IslandTower
    /// Герой вышел через вход.
    var onLeave: (() -> Void)?
    /// Герой подошёл к боссу — начать бой.
    var onBoss: (() -> Void)?

    private let heroNode = SKSpriteNode()
    private var heroFrames: [SKTexture] = []
    private var heroBackFrames: [SKTexture] = []
    private let bossNode = SKSpriteNode()
    private let cameraNode = SKCameraNode()
    private let darkNode = SKSpriteNode()
    private var heroPosition: (x: Double, y: Double)
    private var path: [TilePoint] = []
    private var lastTime: TimeInterval = 0
    private var now: TimeInterval = 0
    private var walkPhase = 0.0
    private var moving = false
    private var facing = 2
    private var leftEntrance = false
    private var bossCalmUntil: TimeInterval = 0
    private let n = ExploreRules.hallSide
    private var entrance: TilePoint { TilePoint(n / 2, n - 1) }
    private var bossTile: TilePoint { TilePoint(n / 2, 1) }

    init(session: ExploreSession, tower: IslandTower, size: CGSize) {
        self.session = session
        self.tower = tower
        heroPosition = (Double(ExploreRules.hallSide / 2), Double(ExploreRules.hallSide - 2))
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.055, alpha: 1)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    private func isFloor(_ tile: TilePoint) -> Bool { tile.x >= 1 && tile.y >= 1 && tile.x < n && tile.y < n }

    override func didMove(to view: SKView) {
        guard children.isEmpty else { return }
        if let image = Self.render(side: n) {
            let texture = SKTexture(cgImage: image)
            texture.filteringMode = .nearest
            let ground = SKSpriteNode(texture: texture)
            ground.anchorPoint = CGPoint(x: 0, y: 1)
            ground.position = CGPoint(x: 0, y: 40)
            ground.zPosition = -1000
            addChild(ground)
        }
        // Факелы на дальних стенах светят сами — поверх темноты.
        for tile in [TilePoint(3, 0), TilePoint(8, 0), TilePoint(0, 3), TilePoint(0, 8)] {
            var glow = RGBACanvas(width: 30, height: 22, fill: nil)
            for y in 0..<22 { for x in 0..<30 {
                let d = hypot((Double(x) - 14.5) / 15, (Double(y) - 10.5) / 11)
                if d < 1 { glow.setAlpha(x, y, d < 0.18 ? 0xFFE09A : 0xF2B35B, alpha: min(0.9, (1 - d) * (d < 0.18 ? 1 : 0.45))) }
            } }
            let node = SKSpriteNode(texture: glow.image.map { SKTexture(cgImage: $0) })
            node.size = CGSize(width: 30, height: 22)
            node.position = point(Double(tile.x), Double(tile.y), lift: 16)
            node.zPosition = 6000
            node.run(.repeatForever(.sequence([.fadeAlpha(to: 0.75, duration: 0.4 + Double(tile.x) * 0.03), .fadeAlpha(to: 1, duration: 0.5)])))
            addChild(node)
        }
        // Выход — светлое пятно у входа.
        let exit = SKShapeNode(ellipseOf: CGSize(width: 18, height: 9))
        exit.fillColor = UIColor(red: 0.95, green: 0.82, blue: 0.48, alpha: 0.6)
        exit.strokeColor = .clear
        exit.position = point(Double(entrance.x), Double(entrance.y))
        exit.zPosition = 6000
        addChild(exit)
        // Босс ×1,5 к обычному NPC; у финальной башни — фиолетовая аура.
        let boss = ExploreCharacters.boss()
        let frames = boss.front.compactMap { texture($0) }
        bossNode.texture = frames.first
        bossNode.size = CGSize(width: ExploreCharacters.frameSize.width, height: ExploreCharacters.frameSize.height)
        bossNode.anchorPoint = CGPoint(x: 0.5, y: CGFloat(ExploreCharacters.feetFromBottom) / CGFloat(ExploreCharacters.frameSize.height))
        bossNode.setScale(ExploreScene.characterScale / 2 * 1.5)
        bossNode.position = point(Double(bossTile.x), Double(bossTile.y))
        bossNode.zPosition = CGFloat(bossTile.x + bossTile.y)
        bossNode.run(.repeatForever(.sequence([.moveBy(x: 0, y: 1, duration: 0.8), .moveBy(x: 0, y: -1, duration: 0.8)])))
        if tower.isFinal {
            let aura = SKShapeNode(ellipseOf: CGSize(width: 40, height: 64))
            aura.fillColor = UIColor(red: 0.42, green: 0.31, blue: 0.55, alpha: 0.35)
            aura.strokeColor = UIColor(red: 0.42, green: 0.31, blue: 0.55, alpha: 0.8)
            aura.position = CGPoint(x: 0, y: 30)
            aura.zPosition = -1
            bossNode.addChild(aura)
        }
        addChild(bossNode)
        let label = SKLabelNode(text: tower.isFinal ? "Финальный босс" : "Страж «\(tower.title)»")
        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 7
        label.fontColor = .white
        label.position = point(Double(bossTile.x), Double(bossTile.y), lift: 36)
        label.zPosition = 6100
        addChild(label)

        if let appearance = session.appearance {
            let pixels = ExploreCharacters.pixels(appearance, accent: session.accent)
            let weapon = HeroComposer.weaponLayers(appearance, accent: session.accent)
            heroFrames = ExploreCharacters.frames(pixels, outline: false, weapon: weapon).compactMap { texture($0) }
            heroBackFrames = ExploreCharacters.backFrames(pixels, hair: appearance.hair.hex, outline: false, weapon: weapon).compactMap { texture($0) }
            heroNode.texture = heroBackFrames.first ?? heroFrames.first
            heroNode.size = CGSize(width: ExploreCharacters.frameSize.width, height: ExploreCharacters.frameSize.height)
            heroNode.anchorPoint = CGPoint(x: 0.5, y: CGFloat(ExploreCharacters.feetFromBottom) / CGFloat(ExploreCharacters.frameSize.height))
            heroNode.setScale(ExploreScene.characterScale / 2)
        } else {
            heroNode.color = UIColor(red: 0.18, green: 0.42, blue: 0.31, alpha: 1)
            heroNode.size = CGSize(width: 8, height: 14)
            heroNode.anchorPoint = CGPoint(x: 0.5, y: 0)
        }
        addChild(heroNode)
        camera = cameraNode
        cameraNode.setScale(0.5)
        addChild(cameraNode)
        // Темнота с дырой обзора вокруг героя.
        var canvas = RGBACanvas(width: 256, height: 256, fill: nil)
        let hole = ExploreRules.hallVision * Double(ExploreRenderer.tileW) * 0.75 / 4
        for y in 0..<256 { for x in 0..<256 {
            let d = hypot(Double(x) - 127.5, (Double(y) - 127.5) * 1.4)
            let alpha = min(0.9, max(0, (d - hole) / (hole * 0.8)) * 0.9)
            if alpha > 0 { canvas.setAlpha(x, y, 0x050508, alpha: alpha) }
        } }
        darkNode.texture = canvas.image.map { SKTexture(cgImage: $0) }
        darkNode.size = CGSize(width: 2048, height: 2048)
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
        let p = ExploreRenderer.pixel(x: x, y: y, side: n)
        return CGPoint(x: p.x, y: -p.y + lift)
    }

    /// После побега — передышка, чтобы бой не начался сразу снова.
    func calmBoss() { bossCalmUntil = now + 8 }

    // MARK: Ходьба

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.mode == .turnBased, !session.isFrozen, let touch = touches.first else { return }
        let location = touch.location(in: self)
        let t = ExploreRenderer.tile(px: Double(location.x), py: Double(-location.y), side: n)
        let target = TilePoint(Int(t.x.rounded()), Int(t.y.rounded()))
        guard isFloor(target) else { return }
        // Зал пустой — путь прямой, по клеткам.
        var route: [TilePoint] = []
        var current = TilePoint(Int(heroPosition.x.rounded()), Int(heroPosition.y.rounded()))
        while current != target {
            current = TilePoint(current.x + (target.x > current.x ? 1 : target.x < current.x ? -1 : 0),
                                current.y + (target.y > current.y ? 1 : target.y < current.y ? -1 : 0))
            route.append(current)
        }
        path = route
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(0.1, currentTime - lastTime)
        lastTime = currentTime
        now += dt
        guard !session.isFrozen else { return }
        session.clockHour = (session.clockHour + dt / ExploreRules.daySeconds * 24).truncatingRemainder(dividingBy: 24)
        if session.mode == .active { moveByStick(dt) } else { moveAlongPath(dt) }
        interact()
        layout()
    }

    private func moveAlongPath(_ dt: Double) {
        guard let next = path.first else { moving = false; return }
        moving = true
        let dx = Double(next.x) - heroPosition.x, dy = Double(next.y) - heroPosition.y
        facing = ExploreScene.facing(dx: dx, dy: dy, current: facing)
        let distance = hypot(dx, dy), step = session.speed * dt
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
        facing = ExploreScene.facing(dx: tx, dy: ty, current: facing)
        let step = session.speed * dt * magnitude
        let x = min(Double(n - 1), max(1, heroPosition.x + tx * step)), y = min(Double(n - 1), max(1, heroPosition.y + ty * step))
        heroPosition = (x, y)
        moving = true
        walkPhase += dt * session.speed * 2.2
    }

    private func interact() {
        let toExit = hypot(Double(entrance.x) - heroPosition.x, Double(entrance.y) - heroPosition.y)
        if toExit > 1.5 { leftEntrance = true }
        if leftEntrance && toExit <= 0.6 {
            onLeave?()
            onLeave = nil
            return
        }
        let toBoss = hypot(Double(bossTile.x) - heroPosition.x, Double(bossTile.y) - heroPosition.y)
        if toBoss <= 1.3, now >= bossCalmUntil, session.encounter == nil {
            path = []
            moving = false
            onBoss?()
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
        cameraNode.position = point(heroPosition.x, heroPosition.y, lift: 18)
    }

    // MARK: Рисунок зала

    /// Пол — тёмные каменные плиты в шахматку, задние стены (x = 0, y = 0) подняты.
    static func render(side n: Int) -> CGImage? {
        let size = ExploreRenderer.imageSize(side: n)
        var canvas = RGBACanvas(width: size.width, height: size.height + 40, fill: 0x0A0A0E)
        let tw = ExploreRenderer.tileW, th = ExploreRenderer.tileH
        for d in 0..<(2 * n - 1) {
            for x in 0...d where x < n {
                let y = d - x
                guard y < n else { continue }
                let wall = x == 0 || y == 0
                let p = ExploreRenderer.pixel(x: Double(x), y: Double(y), side: n)
                let cx = Int(p.x), cy = Int(p.y) + 40, e = wall ? 34 : 0
                if wall {
                    for dx in (-tw / 2)..<(tw / 2) {
                        var bottom = 0
                        for py in 0..<th {
                            let half = py < th / 2 ? (py + 1) * 2 : (th - py) * 2
                            if dx >= -half && dx < half { bottom = py }
                        }
                        for dy in 0...e { canvas.set(cx + dx, cy - th / 2 + bottom - dy, dx < 0 ? 0x2C2834 : 0x221F29) }
                    }
                }
                for py in 0..<th {
                    let half = py < th / 2 ? (py + 1) * 2 : (th - py) * 2
                    for dx in -half..<half {
                        let edge = dx == -half || dx == half - 1 || py == 0
                        let floor: UInt32 = (x + y) % 2 == 0 ? 0x3A3640 : 0x34303A
                        canvas.set(cx + dx, cy - th / 2 + py - e, wall ? 0x3C3846 : (edge ? 0x26232C : floor))
                    }
                }
            }
        }
        return canvas.image
    }
}
