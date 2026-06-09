import SwiftUI

/// The whole Nova Wing simulation. Coarse UI state (`phase`, `score`, …) is
/// `@Published`; the hot per-frame entity arrays are `private(set)` and mutated
/// inside `advance`, which the `TimelineView` in `GamePlayView` drives once per
/// display refresh. The renderer only reads this state.
@MainActor
final class GameEngine: ObservableObject {

    // MARK: Published HUD state
    @Published private(set) var phase: GamePhase = .menu
    @Published private(set) var score = 0
    @Published private(set) var hiScore = 0
    @Published private(set) var lives = 3
    @Published private(set) var wave = 0
    @Published private(set) var bombs = 2

    // MARK: Tunables
    let playerRadius: CGFloat = 8
    let playerYFrac: CGFloat = 0.85

    // MARK: Per-frame state (read by the renderer)
    private(set) var screen = CGSize(width: 184, height: 224)
    private(set) var playerXFrac: CGFloat = 0.5
    var targetXFrac: CGFloat = 0.5             // written by the Digital Crown
    private(set) var dual = false
    private(set) var shield = false
    private(set) var invuln: CGFloat = 0
    private(set) var playerAlive = true
    private(set) var respawnTimer: CGFloat = 0
    private(set) var enemies: [Enemy] = []
    private(set) var bullets: [Bullet] = []
    private(set) var powerups: [PowerUp] = []
    private(set) var particles: [Particle] = []
    private(set) var stars: [Star] = []
    private(set) var elapsed: CGFloat = 0
    private(set) var combo = 0
    private(set) var shake: CGFloat = 0
    private(set) var flashBomb: CGFloat = 0
    private(set) var bannerText = ""
    private(set) var bannerTimer: CGFloat = 0
    private(set) var capturingId: Int?
    private(set) var captureT: CGFloat = 0

    // MARK: Private bookkeeping
    private var rapidTimer: CGFloat = 0
    private var spreadTimer: CGFloat = 0
    private var fireCD: CGFloat = 0
    private var comboTimer: CGFloat = 0
    private var formationCols = 5
    private var diveTimer: CGFloat = 1.5
    private var isChallenge = false
    private var clearPause: CGFloat = 1
    private var enemyIdSeq = 0
    private var nextLifeScore = 10_000
    private var lastDate: Date?
    private var ending = false
    private var pendingDemo: String?
    private let hiKey = "NovaWing.hiScore"

    var hasShield: Bool { shield }

    init() {
        hiScore = UserDefaults.standard.integer(forKey: hiKey)
        #if DEBUG
        configureLaunchDemo()
        #endif
    }

    // MARK: Lifecycle

    func start() {
        phase = .playing
        ending = false
        score = 0; lives = 3; bombs = 2; wave = 0; combo = 0
        playerXFrac = 0.5; targetXFrac = 0.5
        dual = false; shield = false; invuln = 1.2; playerAlive = true; respawnTimer = 0
        enemies.removeAll(); bullets.removeAll(); powerups.removeAll(); particles.removeAll()
        rapidTimer = 0; spreadTimer = 0; fireCD = 0; comboTimer = 0
        capturingId = nil; captureT = 0
        elapsed = 0; shake = 0; flashBomb = 0; clearPause = 1
        nextLifeScore = 10_000
        lastDate = nil
        seedStars()
        nextWave()
    }

    func backToMenu() { phase = .menu }

    /// Tap → smart bomb: wipes enemy fire and damages everything on screen.
    func dropBomb() {
        guard phase == .playing, playerAlive, bombs > 0 else { return }
        bombs -= 1
        flashBomb = 1
        shake = 13
        Haptic.bomb()
        bullets.removeAll { !$0.fromPlayer }
        for id in enemies.filter({ $0.pos.y > -10 && $0.pos.y < screen.height + 10 }).map(\.id) {
            damageEnemy(id: id, amount: 2)
        }
    }

    // MARK: Geometry

    func playerPos() -> CGPoint {
        let m = playerRadius + 6
        return CGPoint(x: m + playerXFrac * (screen.width - 2 * m), y: screen.height * playerYFrac)
    }

    private func home(_ row: Int, _ col: Int) -> CGPoint {
        let cols = max(formationCols, 1)
        let spacingX = clamp((screen.width - 24) / CGFloat(cols), 22, 30)
        let cx = screen.width / 2 + CGFloat(sin(Double(elapsed) * 0.7)) * 12
        let x = cx + (CGFloat(col) - CGFloat(cols - 1) / 2) * spacingX
        let y = screen.height * 0.17 + CGFloat(row) * 19
        return CGPoint(x: x, y: y)
    }

    // MARK: Main step

    func advance(to date: Date, size: CGSize) {
        guard phase == .playing else { lastDate = date; return }
        screen = size
        #if DEBUG
        if pendingDemo != nil { applyPendingDemo() }
        #endif
        let dt = min(CGFloat(date.timeIntervalSince(lastDate ?? date)), 1.0 / 20.0)
        lastDate = date
        guard dt > 0 else { return }

        elapsed += dt
        invuln = max(0, invuln - dt)
        rapidTimer = max(0, rapidTimer - dt)
        spreadTimer = max(0, spreadTimer - dt)
        shake = max(0, shake - dt * 40)
        flashBomb = max(0, flashBomb - dt * 3)
        bannerTimer = max(0, bannerTimer - dt)
        if comboTimer > 0 { comboTimer -= dt; if comboTimer <= 0 { combo = 0 } }

        updateStars(dt)
        updatePlayer(dt)
        updateEnemies(dt)
        updateCapture(dt)
        updateBullets(dt)
        updatePowerups(dt)
        updateParticles(dt)
        resolveCollisions()
        checkWaveCleared(dt)
    }

    // MARK: Player

    private func updatePlayer(_ dt: CGFloat) {
        if respawnTimer > 0 {
            respawnTimer -= dt
            if respawnTimer <= 0 { playerAlive = true; invuln = 1.5 }
            return
        }
        guard playerAlive else { return }
        playerXFrac += (targetXFrac - playerXFrac) * clamp(dt * 13, 0, 1)
        playerXFrac = clamp(playerXFrac, 0, 1)

        fireCD -= dt
        if fireCD <= 0 {
            fire()
            fireCD = rapidTimer > 0 ? 0.13 : 0.30
        }
    }

    private func fire() {
        let p = playerPos()
        let guns: [CGFloat] = dual ? [p.x - 6, p.x + 6] : [p.x]
        for gx in guns {
            if spreadTimer > 0 {
                for a in [-0.22, 0.0, 0.22] {
                    bullets.append(Bullet(pos: CGPoint(x: gx, y: p.y - 10),
                                          vel: CGVector(dx: CGFloat(sin(a)) * 260, dy: -380),
                                          fromPlayer: true, radius: 2.4))
                }
            } else {
                bullets.append(Bullet(pos: CGPoint(x: gx, y: p.y - 10),
                                      vel: CGVector(dx: 0, dy: -380), fromPlayer: true, radius: 2.4))
            }
        }
    }

    private func playerHit() {
        if shield { shield = false; invuln = 1.0; spawnBurst(playerPos(), .cyan, 12); shake = 7; Haptic.playerHit(); return }
        if dual { dual = false; invuln = 1.0; spawnBurst(playerPos(), .cyan, 12); shake = 8; Haptic.playerHit(); return }
        spawnBurst(playerPos(), .fire, 18)
        shake = 12
        Haptic.playerHit()
        playerAlive = false
        lives -= 1
        if lives <= 0 { gameOver() } else { respawnTimer = 1.0 }
    }

    // MARK: Bullets / powerups / particles / stars

    private func updateBullets(_ dt: CGFloat) {
        for i in bullets.indices {
            bullets[i].pos.x += bullets[i].vel.dx * dt
            bullets[i].pos.y += bullets[i].vel.dy * dt
        }
        bullets.removeAll { $0.pos.y < -12 || $0.pos.y > screen.height + 12 || $0.pos.x < -12 || $0.pos.x > screen.width + 12 }
    }

    private func updatePowerups(_ dt: CGFloat) {
        for i in powerups.indices {
            powerups[i].pos.y += 42 * dt
            powerups[i].wobble += dt
            powerups[i].pos.x += CGFloat(sin(Double(powerups[i].wobble) * 4)) * 18 * dt
        }
        powerups.removeAll { $0.pos.y > screen.height + 18 }
    }

    private func updateParticles(_ dt: CGFloat) {
        for i in particles.indices {
            particles[i].pos.x += particles[i].vel.dx * dt
            particles[i].pos.y += particles[i].vel.dy * dt
            particles[i].vel.dx *= 0.92
            particles[i].vel.dy *= 0.92
            particles[i].life -= dt
        }
        particles.removeAll { $0.life <= 0 }
    }

    private func seedStars() {
        stars = (0..<40).map { _ in
            Star(pos: CGPoint(x: .random(in: 0...screen.width), y: .random(in: 0...screen.height)),
                 speed: .random(in: 16...70), size: .random(in: 0.6...2.0), bright: .random(in: 0.3...1.0))
        }
    }

    private func updateStars(_ dt: CGFloat) {
        if stars.isEmpty { seedStars() }
        for i in stars.indices {
            stars[i].pos.y += stars[i].speed * dt
            if stars[i].pos.y > screen.height {
                stars[i].pos = CGPoint(x: .random(in: 0...screen.width), y: -2)
                stars[i].speed = .random(in: 16...70)
            }
        }
    }

    // MARK: Scoring

    private func addScore(_ base: Int) {
        let mult = 1 + CGFloat(min(combo, 30)) * 0.07
        score += Int(CGFloat(base) * mult)
        if score >= nextLifeScore {
            lives += 1
            nextLifeScore += 25_000
            Haptic.powerUp()
        }
    }

    private func banner(_ text: String) { bannerText = text; bannerTimer = 1.8 }

    private func gameOver() {
        guard !ending else { return }
        ending = true
        if score > hiScore { hiScore = score; UserDefaults.standard.set(hiScore, forKey: hiKey) }
        Haptic.gameOver()
        DispatchQueue.main.async { [weak self] in self?.phase = .gameOver }
    }

    func spawnBurst(_ at: CGPoint, _ color: ParticleColor, _ n: Int) {
        for _ in 0..<n {
            let a = Double.random(in: 0...(.pi * 2))
            let s = CGFloat.random(in: 30...140)
            particles.append(Particle(pos: at,
                                      vel: CGVector(dx: CGFloat(cos(a)) * s, dy: CGFloat(sin(a)) * s),
                                      life: .random(in: 0.3...0.6), maxLife: 0.6,
                                      size: .random(in: 1.5...3.5), color: color))
        }
    }

    // MARK: id

    private func nextId() -> Int { enemyIdSeq += 1; return enemyIdSeq }
    private func hpFor(_ t: EnemyType) -> Int { t == .flagship ? 2 : 1 }
}

// MARK: - Waves, enemy AI, capture & collisions
// (same file so it can reach the engine's private state)

extension GameEngine {

    func nextWave() {
        wave += 1
        combo = 0
        isChallenge = (wave % 4 == 0)
        clearPause = 1.0
        if isChallenge { banner("CHALLENGE"); spawnChallenge() }
        else { banner("WAVE \(wave)"); spawnFormation() }
        Haptic.wave()
        diveTimer = max(0.7, 2.4 - CGFloat(wave) * 0.12)
    }

    private func spawnFormation() {
        let rows = clamp(2 + (wave - 1) / 3, 2, 4)
        formationCols = clamp(4 + (wave - 1) / 3, 4, 6)
        var idx = 0
        for r in 0..<rows {
            for c in 0..<formationCols {
                let type: EnemyType
                if r == 0 && c == formationCols / 2 { type = .flagship }
                else if r <= 1 { type = .escort }
                else { type = .grunt }
                var e = Enemy(id: nextId(), type: type, state: .entering, row: r, col: c,
                              pos: .zero, hp: hpFor(type))
                e.delay = CGFloat(idx) * 0.09
                setEntryPath(&e)
                enemies.append(e)
                idx += 1
            }
        }
    }

    private func spawnChallenge() {
        formationCols = 6
        for g in 0..<3 {
            let fromLeft = g % 2 == 0
            for k in 0..<4 {
                let type: EnemyType = k == 0 ? .escort : .grunt
                var e = Enemy(id: nextId(), type: type, state: .diving, row: 0, col: 0,
                              pos: .zero, hp: hpFor(type))
                let start = CGPoint(x: fromLeft ? -28 : screen.width + 28, y: 28 + CGFloat(k) * 9)
                let cp1 = CGPoint(x: screen.width * (fromLeft ? 0.85 : 0.15), y: screen.height * 0.26)
                let cp2 = CGPoint(x: screen.width * (fromLeft ? 0.15 : 0.85), y: screen.height * 0.5)
                let end = CGPoint(x: fromLeft ? screen.width + 28 : -28, y: screen.height * 0.34)
                e.path = [start, cp1, cp2, end]
                e.t = 0; e.dur = 3.0
                e.delay = CGFloat(g) * 0.8 + CGFloat(k) * 0.18
                e.pos = start
                enemies.append(e)
            }
        }
    }

    private func setEntryPath(_ e: inout Enemy) {
        let fromLeft = (e.id % 2 == 0)
        let start = CGPoint(x: fromLeft ? -28 : screen.width + 28, y: 22 + CGFloat(e.row) * 4)
        let h = home(e.row, e.col)
        let cp1 = CGPoint(x: fromLeft ? screen.width * 0.32 : screen.width * 0.68, y: 4)
        let cp2 = CGPoint(x: h.x, y: h.y - 46)
        e.path = [start, cp1, cp2, h]
        e.t = 0; e.dur = 1.5
        e.pos = start
    }

    private func startReturn(_ e: inout Enemy) {
        let h = home(e.row, e.col)
        let start = CGPoint(x: h.x + CGFloat.random(in: -18...18), y: -26)
        let cp1 = CGPoint(x: h.x, y: -2)
        let cp2 = CGPoint(x: h.x, y: h.y - 40)
        e.path = [start, cp1, cp2, h]
        e.t = 0; e.dur = 1.3; e.state = .returning; e.pos = start
    }

    private func scheduleDive() {
        let candidates = enemies.indices.filter { enemies[$0].state == .formation }
        guard let idx = candidates.randomElement() else { return }
        var e = enemies[idx]
        let p = playerPos()
        let from = e.pos
        let cp1 = CGPoint(x: from.x + (p.x - from.x) * 0.15, y: from.y + 46)
        let cp2 = CGPoint(x: clamp(p.x + .random(in: -26...26), 10, screen.width - 10), y: screen.height * 0.62)
        let end = CGPoint(x: clamp(p.x + .random(in: -60...60), 0, screen.width), y: screen.height + 40)
        e.path = [from, cp1, cp2, end]
        e.t = 0; e.dur = .random(in: 1.6...2.1); e.state = .diving; e.fireCD = 0.4
        enemies[idx] = e
    }

    func updateEnemies(_ dt: CGFloat) {
        for i in enemies.indices {
            var e = enemies[i]
            e.wobble += dt
            if e.delay > 0 { e.delay -= dt; enemies[i] = e; continue }
            switch e.state {
            case .entering, .returning:
                e.t += dt / e.dur
                if e.t >= 1 { e.t = 1; e.pos = home(e.row, e.col); e.state = .formation }
                else { e.pos = cubicBezier(e.path, e.t) }
            case .formation:
                e.pos = home(e.row, e.col)
            case .diving:
                e.t += dt / e.dur
                if e.t >= 1 {
                    if isChallenge { e.hp = -999 } else { startReturn(&e) }
                } else {
                    e.pos = cubicBezier(e.path, e.t)
                    if !isChallenge {
                        e.fireCD -= dt
                        if e.fireCD <= 0 && e.pos.y < screen.height * 0.82 {
                            enemyFire(from: e.pos)
                            e.fireCD = CGFloat.random(in: 0.5...1.2)
                        }
                    }
                }
            }
            enemies[i] = e
        }
        enemies.removeAll { $0.hp <= -100 }

        if !isChallenge && phase == .playing {
            diveTimer -= dt
            if diveTimer <= 0 {
                scheduleDive()
                diveTimer = max(0.5, 2.1 - CGFloat(wave) * 0.1) * CGFloat.random(in: 0.7...1.3)
            }
        }
    }

    private func enemyFire(from pos: CGPoint) {
        let p = playerPos()
        bullets.append(Bullet(pos: pos,
                              vel: CGVector(dx: clamp((p.x - pos.x) * 0.6, -70, 70), dy: 155),
                              fromPlayer: false, radius: 2.6))
    }

    func updateCapture(_ dt: CGFloat) {
        if let cid = capturingId {
            guard let idx = enemies.firstIndex(where: { $0.id == cid }), enemies[idx].state == .diving else {
                capturingId = nil; captureT = 0; return
            }
            let e = enemies[idx]
            let p = playerPos()
            if playerAlive && respawnTimer <= 0 && abs(e.pos.x - p.x) < 17 && e.pos.y < p.y - 22 && e.pos.y > p.y - 130 {
                captureT += dt
                if captureT >= 1.0 {
                    enemies[idx].holding = true
                    startReturn(&enemies[idx])
                    capturePlayer()
                    capturingId = nil; captureT = 0
                }
            } else {
                captureT = max(0, captureT - dt * 1.5)
                if captureT <= 0 { capturingId = nil }
            }
        } else if playerAlive && !dual && invuln <= 0 && respawnTimer <= 0 {
            let p = playerPos()
            if let idx = enemies.firstIndex(where: {
                $0.type == .flagship && $0.state == .diving && !$0.holding &&
                abs($0.pos.x - p.x) < 14 && $0.pos.y > screen.height * 0.32 && $0.pos.y < p.y - 38
            }) {
                capturingId = enemies[idx].id
                captureT = 0
                Haptic.capture()
            }
        }
    }

    private func capturePlayer() {
        spawnBurst(playerPos(), .cyan, 14)
        playerAlive = false
        lives -= 1
        if lives <= 0 { gameOver() } else { respawnTimer = 1.2 }
    }

    func damageEnemy(id: Int, amount: Int) {
        guard let idx = enemies.firstIndex(where: { $0.id == id }) else { return }
        enemies[idx].hp -= amount
        if enemies[idx].hp <= 0 {
            let e = enemies[idx]
            addScore(e.score)
            combo += 1; comboTimer = 1.6
            spawnBurst(e.pos, .fire, e.type == .flagship ? 16 : 10)
            shake = max(shake, 3)
            Haptic.kill()
            if e.holding { rescueDualFighter(at: e.pos) }
            maybeDropPower(at: e.pos, type: e.type)
            if capturingId == e.id { capturingId = nil; captureT = 0 }
            enemies.remove(at: idx)
        } else {
            spawnBurst(enemies[idx].pos, .spark, 4)
        }
    }

    private func rescueDualFighter(at p: CGPoint) {
        addScore(1000)
        if playerAlive && !dual {
            dual = true
            banner("DUAL FIGHTER!")
            spawnBurst(playerPos(), .cyan, 18)
            Haptic.rescue()
        }
    }

    private func maybeDropPower(at p: CGPoint, type: EnemyType) {
        let chance: Double = type == .flagship ? 0.55 : (type == .escort ? 0.2 : 0.05)
        guard Double.random(in: 0...1) < chance else { return }
        let roll = Double.random(in: 0...1)
        let kind: PowerKind
        switch roll {
        case ..<0.34: kind = .spread
        case ..<0.60: kind = .rapid
        case ..<0.80: kind = .shield
        case ..<0.94: kind = .bomb
        default:      kind = .wing
        }
        powerups.append(PowerUp(pos: p, kind: kind))
    }

    private func applyPower(_ kind: PowerKind) {
        switch kind {
        case .spread: spreadTimer = 10; banner("SPREAD")
        case .rapid:  rapidTimer = 10; banner("RAPID")
        case .shield: shield = true; banner("SHIELD")
        case .bomb:   bombs = min(bombs + 1, 5); banner("BOMB +1")
        case .wing:   if !dual { dual = true; banner("TWIN FIGHTER") } else { addScore(500) }
        }
        addScore(150)
        Haptic.powerUp()
    }

    func resolveCollisions() {
        var surviving: [Bullet] = []
        surviving.reserveCapacity(bullets.count)
        for b in bullets {
            var consumed = false
            if b.fromPlayer {
                if let e = enemies.first(where: { $0.pos.distance(to: b.pos) < $0.radius + b.radius + 1 }) {
                    damageEnemy(id: e.id, amount: 1)
                    consumed = true
                }
            } else if playerAlive && invuln <= 0 && respawnTimer <= 0 {
                if b.pos.distance(to: playerPos()) < playerRadius + b.radius {
                    playerHit(); consumed = true
                }
            }
            if !consumed { surviving.append(b) }
        }
        bullets = surviving

        if playerAlive && invuln <= 0 && respawnTimer <= 0 {
            if let e = enemies.first(where: {
                ($0.state == .diving || $0.state == .returning) &&
                $0.pos.distance(to: playerPos()) < $0.radius + playerRadius
            }) {
                damageEnemy(id: e.id, amount: 99)
                playerHit()
            }
        }

        if playerAlive {
            var keep: [PowerUp] = []
            for pu in powerups {
                if pu.pos.distance(to: playerPos()) < playerRadius + 11 { applyPower(pu.kind) }
                else { keep.append(pu) }
            }
            powerups = keep
        }
    }

    func checkWaveCleared(_ dt: CGFloat) {
        if enemies.isEmpty {
            clearPause -= dt
            if clearPause <= 0 { nextWave() }
        } else {
            clearPause = 1.0
        }
    }
}

#if DEBUG
extension GameEngine {
    /// Jump into a representative state for screenshots/QA via the `NW_DEMO`
    /// launch environment variable. Compiled out of Release builds.
    func configureLaunchDemo() {
        guard let mode = ProcessInfo.processInfo.environment["NW_DEMO"] else { return }
        switch mode {
        case "play", "dual":
            phase = .playing
            pendingDemo = mode
        case "over":
            score = 18_650
            hiScore = max(hiScore, 18_650)
            wave = 7
            phase = .gameOver
        default:
            break
        }
    }

    func applyPendingDemo() {
        guard let mode = pendingDemo else { return }
        pendingDemo = nil
        ending = false
        score = 4_820; hiScore = max(hiScore, 12_450); lives = 3; bombs = 3; wave = 3; combo = 6
        comboTimer = 1.6
        playerAlive = true; invuln = 0; dual = (mode == "dual"); shield = true
        seedStarsForDemo()
        enemies.removeAll(); bullets.removeAll(); powerups.removeAll(); particles.removeAll()
        formationCols = 6
        for r in 0..<3 {
            for c in 0..<formationCols {
                let type: EnemyType = (r == 0 && c == formationCols / 2) ? .flagship : (r <= 1 ? .escort : .grunt)
                var e = Enemy(id: nextId(), type: type, state: .formation, row: r, col: c,
                              pos: .zero, hp: hpFor(type))
                e.pos = home(r, c)
                if mode == "dual" && type == .flagship { e.holding = true }
                enemies.append(e)
            }
        }
        scheduleDiveForDemo(); scheduleDiveForDemo()
        let p = playerPos()
        for k in 0..<3 {
            bullets.append(Bullet(pos: CGPoint(x: p.x, y: p.y - 30 - CGFloat(k) * 34),
                                  vel: CGVector(dx: 0, dy: -380), fromPlayer: true, radius: 2.4))
        }
        bullets.append(Bullet(pos: CGPoint(x: p.x + 22, y: screen.height * 0.52),
                              vel: CGVector(dx: 0, dy: 155), fromPlayer: false, radius: 2.6))
        powerups.append(PowerUp(pos: CGPoint(x: screen.width * 0.3, y: screen.height * 0.46), kind: .spread))
        spawnBurst(CGPoint(x: screen.width * 0.66, y: screen.height * 0.4), .fire, 12)
    }

    private func seedStarsForDemo() {
        if stars.isEmpty {
            stars = (0..<40).map { _ in
                Star(pos: CGPoint(x: .random(in: 0...screen.width), y: .random(in: 0...screen.height)),
                     speed: .random(in: 16...70), size: .random(in: 0.6...2.0), bright: .random(in: 0.3...1.0))
            }
        }
    }

    private func scheduleDiveForDemo() {
        let candidates = enemies.indices.filter { enemies[$0].state == .formation && enemies[$0].type != .flagship }
        guard let idx = candidates.randomElement() else { return }
        var e = enemies[idx]
        let p = playerPos()
        let from = e.pos
        let cp1 = CGPoint(x: from.x + (p.x - from.x) * 0.15, y: from.y + 46)
        let cp2 = CGPoint(x: clamp(p.x + .random(in: -26...26), 10, screen.width - 10), y: screen.height * 0.55)
        let end = CGPoint(x: clamp(p.x + .random(in: -60...60), 0, screen.width), y: screen.height + 40)
        e.path = [from, cp1, cp2, end]
        e.t = .random(in: 0.3...0.5); e.dur = 1.9; e.state = .diving; e.fireCD = 0.4
        e.pos = cubicBezier(e.path, e.t)
        enemies[idx] = e
    }
}
#endif
