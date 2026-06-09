import CoreGraphics

enum GamePhase {
    case menu
    case playing
    case gameOver
}

// MARK: - Enemies

enum EnemyType {
    case grunt      // common, weak
    case escort     // tougher, fires more
    case flagship   // can capture the player; freeing it grants a twin fighter
}

enum EnemyState {
    case entering   // flying in along a path to its formation slot
    case formation  // parked in the swaying grid
    case diving     // peeled off, swooping at the player
    case returning  // looping back to the top after a dive
}

struct Enemy {
    let id: Int
    var type: EnemyType
    var state: EnemyState
    var row: Int
    var col: Int
    var pos: CGPoint
    var path: [CGPoint] = []   // cubic bezier control points (4)
    var t: CGFloat = 0         // progress along path
    var dur: CGFloat = 1       // seconds to traverse the path
    var fireCD: CGFloat = 0
    var hp: Int
    var holding: Bool = false  // flagship carrying a captured ship
    var wobble: CGFloat = 0
    var delay: CGFloat = 0     // staggered fly-in delay

    var radius: CGFloat { type == .flagship ? 11 : 9 }
    var score: Int {
        switch type {
        case .grunt:    return state == .formation ? 50  : 100
        case .escort:   return state == .formation ? 80  : 160
        case .flagship: return state == .formation ? 150 : 400
        }
    }
}

// MARK: - Projectiles, pickups, fx

struct Bullet {
    var pos: CGPoint
    var vel: CGVector
    var fromPlayer: Bool
    var radius: CGFloat
}

enum PowerKind: CaseIterable {
    case spread   // 3-way shot
    case rapid    // faster fire
    case shield   // absorbs one hit
    case bomb     // +1 smart bomb
    case wing     // instant twin fighter
}

struct PowerUp {
    var pos: CGPoint
    var kind: PowerKind
    var wobble: CGFloat = 0
}

enum ParticleColor { case fire, spark, cyan, gold, smoke }

struct Particle {
    var pos: CGPoint
    var vel: CGVector
    var life: CGFloat
    var maxLife: CGFloat
    var size: CGFloat
    var color: ParticleColor
}

struct Star {
    var pos: CGPoint
    var speed: CGFloat
    var size: CGFloat
    var bright: CGFloat
}

// MARK: - Math helpers

@inline(__always) func clamp<T: Comparable>(_ x: T, _ lo: T, _ hi: T) -> T { min(max(x, lo), hi) }
@inline(__always) func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

extension CGPoint {
    func distance(to p: CGPoint) -> CGFloat { hypot(x - p.x, y - p.y) }
}

/// Point along a cubic Bézier defined by 4 control points.
func cubicBezier(_ p: [CGPoint], _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    return CGPoint(x: a * p[0].x + b * p[1].x + c * p[2].x + d * p[3].x,
                   y: a * p[0].y + b * p[1].y + c * p[2].y + d * p[3].y)
}
