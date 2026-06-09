import SwiftUI

/// Stateless arcade renderer. `@MainActor` because the `Canvas` closure is
/// main-actor isolated and reads the `@MainActor` engine.
@MainActor
enum NovaRenderer {

    static func draw(engine e: GameEngine, context ctx: inout GraphicsContext, size: CGSize) {
        // space
        ctx.fill(Path(CGRect(x: -16, y: -16, width: size.width + 32, height: size.height + 32)),
                 with: .color(.black))

        var world = ctx
        if e.shake > 0 {
            world.translateBy(x: .random(in: -e.shake...e.shake) * 0.4,
                              y: .random(in: -e.shake...e.shake) * 0.4)
        }

        drawStars(e, &world)
        for pu in e.powerups { drawPowerUp(pu, &world) }
        for en in e.enemies { drawEnemy(en, &world) }
        drawCaptureBeam(e, &world)
        for b in e.bullets { drawBullet(b, &world) }
        drawPlayer(e, &world)
        for p in e.particles { drawParticle(p, &world) }

        if e.flashBomb > 0 {
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(col(1, 1, 1, Double(e.flashBomb) * 0.6)))
        }
        scanlines(&ctx, size: size)
        drawHUD(e, &ctx, size: size)
    }

    // MARK: Background

    private static func drawStars(_ e: GameEngine, _ ctx: inout GraphicsContext) {
        for s in e.stars {
            ctx.fill(circle(s.pos, s.size), with: .color(col(0.8, 0.9, 1.0, Double(s.bright) * 0.9)))
        }
    }

    private static func scanlines(_ ctx: inout GraphicsContext, size: CGSize) {
        var path = Path()
        var y: CGFloat = 0
        while y < size.height { path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 3 }
        ctx.fill(path, with: .color(col(0, 0, 0, 0.18)))
    }

    // MARK: Enemies

    private static func drawEnemy(_ en: Enemy, _ ctx: inout GraphicsContext) {
        let p = en.pos
        let r = en.radius
        let flap = 1 + CGFloat(sin(Double(en.wobble) * 9)) * 0.28
        let (body, wing, eye): (Color, Color, Color)
        switch en.type {
        case .grunt:    body = col(1, 0.36, 0.30); wing = col(1, 0.62, 0.30); eye = col(0.2, 0, 0)
        case .escort:   body = col(0.62, 0.5, 1.0); wing = col(0.45, 0.82, 1.0); eye = col(0.1, 0, 0.2)
        case .flagship: body = col(0.42, 0.95, 0.5); wing = col(0.85, 1.0, 0.45); eye = col(0, 0.15, 0)
        }

        if en.holding { drawShipShape(&ctx, at: CGPoint(x: p.x, y: p.y + r + 7), r: 6, alpha: 0.9) }

        // wings (flap)
        for s in [CGFloat(-1), 1] {
            let w = Path(ellipseIn: CGRect(x: p.x + s * r * 0.7 - r * 0.5, y: p.y - r * 0.35 * flap,
                                           width: r * 1.0, height: r * 0.7 * flap))
            ctx.fill(w, with: .color(wing))
        }
        // body
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.75, y: p.y - r, width: r * 1.5, height: r * 2)),
                 with: .radialGradient(Gradient(colors: [body, body.opacity(0.65)]),
                                       center: CGPoint(x: p.x - r * 0.2, y: p.y - r * 0.3),
                                       startRadius: 1, endRadius: r * 1.4))
        // eyes
        ctx.fill(circle(CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.1), r * 0.18), with: .color(eye))
        ctx.fill(circle(CGPoint(x: p.x + r * 0.3, y: p.y - r * 0.1), r * 0.18), with: .color(eye))

        if en.type == .flagship {
            for s in [CGFloat(-1), 1] {
                var a = Path()
                a.move(to: CGPoint(x: p.x + s * r * 0.4, y: p.y - r * 0.8))
                a.addLine(to: CGPoint(x: p.x + s * r * 0.8, y: p.y - r * 1.5))
                ctx.stroke(a, with: .color(wing), lineWidth: 1.2)
                ctx.fill(circle(CGPoint(x: p.x + s * r * 0.8, y: p.y - r * 1.5), 1.6),
                         with: .color(col(1, 1, 0.6)))
            }
        }
    }

    private static func drawCaptureBeam(_ e: GameEngine, _ ctx: inout GraphicsContext) {
        guard let cid = e.capturingId, let en = e.enemies.first(where: { $0.id == cid }) else { return }
        let top = CGPoint(x: en.pos.x, y: en.pos.y + en.radius)
        let pulse = 0.4 + 0.6 * Double(e.captureT)
        let halfW = 4 + 12 * CGFloat(e.captureT)
        let bottomY = e.playerPos().y
        var beam = Path()
        beam.move(to: CGPoint(x: top.x - 3, y: top.y))
        beam.addLine(to: CGPoint(x: top.x + 3, y: top.y))
        beam.addLine(to: CGPoint(x: top.x + halfW, y: bottomY))
        beam.addLine(to: CGPoint(x: top.x - halfW, y: bottomY))
        beam.closeSubpath()
        ctx.fill(beam, with: .linearGradient(
            Gradient(colors: [col(0.5, 1, 0.6, pulse * 0.7), col(0.5, 1, 0.6, 0.05)]),
            startPoint: top, endPoint: CGPoint(x: top.x, y: bottomY)))
    }

    // MARK: Player

    private static func drawPlayer(_ e: GameEngine, _ ctx: inout GraphicsContext) {
        guard e.playerAlive else { return }
        let p = e.playerPos()
        let blink = e.invuln > 0 && (sin(Double(e.elapsed) * 28) > 0)
        let alpha: Double = blink ? 0.35 : 1.0

        if e.dual {
            drawShipShape(&ctx, at: CGPoint(x: p.x - 7, y: p.y), r: e.playerRadius * 0.92, alpha: alpha)
            drawShipShape(&ctx, at: CGPoint(x: p.x + 7, y: p.y), r: e.playerRadius * 0.92, alpha: alpha)
        } else {
            drawShipShape(&ctx, at: p, r: e.playerRadius, alpha: alpha)
        }

        if e.hasShield {
            let pulse = 1 + CGFloat(sin(Double(e.elapsed) * 6)) * 0.06
            ctx.stroke(circle(p, e.playerRadius * 1.9 * pulse),
                       with: .color(col(0.3, 0.9, 1.0, 0.8)), lineWidth: 1.6)
        }
    }

    private static func drawShipShape(_ ctx: inout GraphicsContext, at p: CGPoint, r: CGFloat, alpha: Double) {
        // engine flame (flickers)
        let f = CGFloat.random(in: 0.5...1.2)
        var flame = Path()
        flame.move(to: CGPoint(x: p.x - r * 0.32, y: p.y + r * 0.4))
        flame.addLine(to: CGPoint(x: p.x, y: p.y + r * 0.4 + r * f))
        flame.addLine(to: CGPoint(x: p.x + r * 0.32, y: p.y + r * 0.4))
        flame.closeSubpath()
        ctx.fill(flame, with: .color(col(1, 0.7, 0.2, alpha * 0.9)))

        var body = Path()
        body.move(to: CGPoint(x: p.x, y: p.y - r * 1.3))
        body.addLine(to: CGPoint(x: p.x - r, y: p.y + r * 0.7))
        body.addLine(to: CGPoint(x: p.x - r * 0.32, y: p.y + r * 0.38))
        body.addLine(to: CGPoint(x: p.x + r * 0.32, y: p.y + r * 0.38))
        body.addLine(to: CGPoint(x: p.x + r, y: p.y + r * 0.7))
        body.closeSubpath()
        ctx.fill(body, with: .linearGradient(
            Gradient(colors: [col(0.75, 1, 1, alpha), col(0.2, 0.7, 0.95, alpha)]),
            startPoint: CGPoint(x: p.x, y: p.y - r), endPoint: CGPoint(x: p.x, y: p.y + r)))
        ctx.fill(circle(CGPoint(x: p.x, y: p.y - r * 0.15), r * 0.26), with: .color(col(0.1, 0.25, 0.35, alpha)))
    }

    // MARK: Bullets / pickups / particles

    private static func drawBullet(_ b: Bullet, _ ctx: inout GraphicsContext) {
        if b.fromPlayer {
            ctx.fill(Path(roundedRect: CGRect(x: b.pos.x - 1.4, y: b.pos.y - 5, width: 2.8, height: 10),
                          cornerRadius: 1.4),
                     with: .color(col(0.6, 1, 1)))
            ctx.fill(circle(b.pos, 1.4), with: .color(.white))
        } else {
            ctx.fill(circle(b.pos, b.radius + 1.5), with: .color(col(1, 0.5, 0.2, 0.4)))
            ctx.fill(circle(b.pos, b.radius), with: .color(col(1, 0.8, 0.3)))
        }
    }

    private static func drawPowerUp(_ pu: PowerUp, _ ctx: inout GraphicsContext) {
        let (c, letter): (Color, String)
        switch pu.kind {
        case .spread: c = col(1, 0.6, 0.2); letter = "S"
        case .rapid:  c = col(1, 0.9, 0.2); letter = "R"
        case .shield: c = col(0.3, 0.9, 1.0); letter = "D"
        case .bomb:   c = col(1, 0.4, 0.5); letter = "B"
        case .wing:   c = col(0.6, 1, 0.6); letter = "W"
        }
        let p = pu.pos
        ctx.fill(circle(p, 11), with: .color(c.opacity(0.25)))
        ctx.stroke(circle(p, 9), with: .color(c), lineWidth: 1.6)
        ctx.draw(Text(letter).font(.system(size: 11, weight: .black, design: .rounded)).foregroundStyle(c),
                 at: p)
    }

    private static func drawParticle(_ p: Particle, _ ctx: inout GraphicsContext) {
        let a = Double(max(0, p.life / p.maxLife))
        let c: Color
        switch p.color {
        case .fire:  c = col(1, 0.5 + 0.4 * a, 0.15, a)
        case .spark: c = col(1, 0.95, 0.4, a)
        case .cyan:  c = col(0.4, 0.9, 1.0, a)
        case .gold:  c = col(1, 0.85, 0.3, a)
        case .smoke: c = col(0.6, 0.6, 0.7, a * 0.6)
        }
        ctx.fill(circle(p.pos, p.size * CGFloat(0.4 + a)), with: .color(c))
    }

    // MARK: HUD

    private static func drawHUD(_ e: GameEngine, _ ctx: inout GraphicsContext, size: CGSize) {
        ctx.draw(Text("\(e.score)").font(.system(size: 16, weight: .heavy, design: .rounded))
            .foregroundStyle(.white), at: CGPoint(x: 7, y: 5), anchor: .topLeading)
        ctx.draw(Text("HI \(e.hiScore)").font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(col(1, 0.85, 0.3, 0.9)), at: CGPoint(x: 8, y: 23), anchor: .topLeading)

        let waveLabel = (e.wave % 4 == 0) ? "CHALLENGE" : "WAVE \(e.wave)"
        ctx.draw(Text(waveLabel).font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.85)), at: CGPoint(x: size.width - 7, y: 6), anchor: .topTrailing)

        if e.combo > 1 {
            ctx.draw(Text("x\(e.combo)").font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(col(1, 0.75, 0.2)), at: CGPoint(x: size.width - 7, y: 20), anchor: .topTrailing)
        }

        // lives (small ships, bottom-left)
        for i in 0..<max(0, e.lives - 1) {
            drawShipShape(&ctx, at: CGPoint(x: 9 + CGFloat(i) * 11, y: size.height - 8), r: 4, alpha: 0.9)
        }
        // bombs (bottom-right)
        for i in 0..<e.bombs {
            let x = size.width - 9 - CGFloat(i) * 11
            ctx.fill(circle(CGPoint(x: x, y: size.height - 8), 3.2), with: .color(col(1, 0.4, 0.5)))
            ctx.stroke(circle(CGPoint(x: x, y: size.height - 8), 3.2), with: .color(.white.opacity(0.6)), lineWidth: 0.6)
        }

        if e.bannerTimer > 0 {
            let a = Double(min(1, e.bannerTimer / 0.5))
            ctx.draw(Text(e.bannerText).font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(col(0.5, 1, 0.7, a)),
                     at: CGPoint(x: size.width / 2, y: size.height * 0.38), anchor: .center)
        }
    }

    // MARK: Helpers

    private static func col(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
    private static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
}
