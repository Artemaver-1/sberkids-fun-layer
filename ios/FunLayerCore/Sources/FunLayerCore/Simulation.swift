import Foundation

// Физика эффектов — чистая математика, без рендеринга.
// Рендерер (SwiftUI Canvas / Compose Canvas) только рисует то, что здесь посчитано.
// Позиции считаются аналитически от времени рождения, поэтому пропуск кадров
// на слабом телефоне не ломает анимацию — она просто «догоняет».

public struct Vec2: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public var length: Double { (x * x + y * y).squareRoot() }
}

public enum Ease {
    public static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
    public static func outCubic(_ t: Double) -> Double { let u = 1 - clamp01(t); return 1 - u * u * u }
    public static func inOutSine(_ t: Double) -> Double { -(cos(Double.pi * clamp01(t)) - 1) / 2 }
    public static func outBack(_ t: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1, u = clamp01(t) - 1
        return 1 + c3 * u * u * u + c1 * u * u
    }
}

// MARK: - Частицы (пузыри, снег, листья, конфетти…)

public struct Particle: Sendable {
    public let id: Int
    public let birth: Double
    public let size: Double
    public let speed: Double
    public let baseX: Double
    public let phase: Double
    public let wobbleSpeed: Double
    public let spin: Double
    public let tint: Double             // 0…1 — рендерер сдвигает оттенок/поворот блика
    public var position = Vec2(0, 0)
    public var rotation = 0.0
    public var scaleX = 1.0
    public var scaleY = 1.0
    public var spawned = false
    public var alive = true
    public var popAt: Double?
    /// 0…1 — прогресс «лопания» (рендерер рисует расходящееся кольцо).
    public var popProgress: Double = 0
}

public struct Droplet: Sendable {
    public let origin: Vec2
    public let velocity: Vec2
    public let birth: Double
    public let size: Double
    public var position: Vec2
    public var alpha: Double = 1
}

public final class ParticleField {
    public static let popDuration = 0.2
    public static let dropletLife = 0.5

    public let spec: ParticleSpec
    public let width: Double
    public let height: Double
    public private(set) var particles: [Particle] = []
    public private(set) var droplets: [Droplet] = []
    public private(set) var time = 0.0
    public private(set) var poppedCount = 0
    private let rng: RandomSource

    public init(spec: ParticleSpec, width: Double, height: Double, rng: RandomSource) {
        self.spec = spec
        self.width = width
        self.height = height
        self.rng = rng
        for i in 0..<spec.count {
            let size = rng.range(spec.sizeMin, spec.sizeMax)
            // крупные медленнее — ощущение глубины
            let depth = (size - spec.sizeMin) / max(1, spec.sizeMax - spec.sizeMin)
            let speed = spec.speedMax - (spec.speedMax - spec.speedMin) * (0.35 * depth + 0.65 * rng.next())
            let birth = spec.count > 1 ? spec.spawn * Double(i) / Double(spec.count - 1) * rng.range(0.8, 1.0) : 0
            let margin = size * 0.5
            particles.append(Particle(
                id: i, birth: birth, size: size, speed: speed,
                baseX: rng.range(margin, max(margin + 1, width - margin)),
                phase: rng.range(0, 2 * .pi),
                wobbleSpeed: spec.wobbleSpeed * rng.range(0.7, 1.3),
                spin: spec.spin * rng.range(-1, 1),
                tint: rng.next()
            ))
        }
        update(to: 0)
    }

    public var allGone: Bool { particles.allSatisfy { !$0.alive } && droplets.isEmpty }

    public func update(to t: Double) {
        time = t
        for i in particles.indices {
            var p = particles[i]
            guard p.alive else { continue }
            let age = t - p.birth
            guard age >= 0 else { p.spawned = false; particles[i] = p; continue }
            p.spawned = true
            let travel = p.speed * age
            let y = spec.direction == .up ? height + p.size * 0.5 - travel : -p.size * 0.5 + travel
            let x = p.baseX + spec.wobble * sin(p.phase + p.wobbleSpeed * age)
            p.position = Vec2(x, y)
            // без вращения (spin=0) блик пузыря остаётся сверху-слева, как от настоящего света
            p.rotation = p.spin == 0 ? 0 : p.phase + p.spin * age
            let breathe = 0.035 * sin(age * 5.3 + p.phase)
            p.scaleX = 1 + breathe
            p.scaleY = 1 - breathe
            if let popAt = p.popAt {
                p.popProgress = Ease.clamp01((t - popAt) / Self.popDuration)
                if p.popProgress >= 1 { p.alive = false }
            }
            let out = spec.direction == .up ? y < -p.size * 0.5 : y > height + p.size * 0.5
            if out { p.alive = false }
            particles[i] = p
        }
        droplets = droplets.compactMap { d in
            let age = t - d.birth
            guard age < Self.dropletLife else { return nil }
            var d = d
            d.position = Vec2(d.origin.x + d.velocity.x * age,
                              d.origin.y + d.velocity.y * age + 0.5 * 900 * age * age)
            d.alpha = 1 - age / Self.dropletLife
            return d
        }
    }

    /// Индекс частицы под пальцем (верхняя — последняя нарисованная).
    public func hit(at point: Vec2) -> Int? {
        for i in particles.indices.reversed() {
            let p = particles[i]
            guard p.alive, p.spawned, p.popAt == nil else { continue }
            if (p.position - point).length <= p.size * 0.55 { return i }
        }
        return nil
    }

    @discardableResult
    public func pop(at point: Vec2) -> Bool {
        guard spec.tapToPop, let i = hit(at: point) else { return false }
        particles[i].popAt = time
        poppedCount += 1
        let p = particles[i]
        let n = 9
        for k in 0..<n {
            let angle = 2 * Double.pi * Double(k) / Double(n) + rng.range(-0.25, 0.25)
            let speed = rng.range(90, 190) * (p.size / 70)
            droplets.append(Droplet(
                origin: p.position,
                velocity: Vec2(cos(angle) * speed, sin(angle) * speed - 60),
                birth: time,
                size: rng.range(2.5, 5.5),
                position: p.position
            ))
        }
        return true
    }
}

// MARK: - Призраки

public struct Ghost: Sendable {
    public let id: Int
    public let anchor: Vec2
    public let size: Double
    public let phase: Double
    public let amp: Vec2
    public let freq: Vec2
    public let appearAt: Double
    public let colorIndex: Int
    public let blinkOffset: Double
    public var position = Vec2(0, 0)
    public var scale = 0.0
    public var alpha = 0.0
    public var tilt = 0.0
    public var eyesClosed = false
    public var vanishAt: Double?
    public var gone = false
    /// Фаза «волн» подола — рендерер рисует волнистый низ.
    public var tailPhase = 0.0
}

public final class GhostField {
    public static let appearDuration = 0.7
    public static let vanishDuration = 0.45

    public let spec: GhostSpec
    public let width: Double
    public let height: Double
    public private(set) var ghosts: [Ghost] = []
    public private(set) var time = 0.0
    public private(set) var vanishedCount = 0

    public init(spec: GhostSpec, width: Double, height: Double, rng: RandomSource) {
        self.spec = spec
        self.width = width
        self.height = height
        var anchors: [Vec2] = []
        let minDist = spec.sizeMax * 1.15
        for _ in 0..<spec.count {
            var best = Vec2(width / 2, height / 2)
            var bestScore = -1.0
            for _ in 0..<40 {
                let c = Vec2(rng.range(width * 0.18, width * 0.82), rng.range(height * 0.2, height * 0.78))
                let d = anchors.map { ($0 - c).length }.min() ?? .infinity
                if d >= minDist { best = c; bestScore = d; break }
                if d > bestScore { best = c; bestScore = d }
            }
            anchors.append(best)
        }
        for (i, a) in anchors.enumerated() {
            ghosts.append(Ghost(
                id: i,
                anchor: a,
                size: rng.range(spec.sizeMin, spec.sizeMax),
                phase: rng.range(0, 2 * .pi),
                amp: Vec2(rng.range(14, 30), rng.range(10, 22)),
                freq: Vec2(rng.range(0.6, 1.1), rng.range(0.9, 1.6)),
                appearAt: 0.15 + Double(i) * 0.35 + rng.range(0, 0.2),
                colorIndex: i % max(1, spec.palette.count),
                blinkOffset: rng.range(0, 3)
            ))
        }
        update(to: 0)
    }

    public var allGone: Bool { ghosts.allSatisfy(\.gone) }

    public func update(to t: Double) {
        time = t
        for i in ghosts.indices {
            var g = ghosts[i]
            guard !g.gone else { continue }
            let a = Ease.clamp01((t - g.appearAt) / Self.appearDuration)
            let rise = (1 - Ease.outCubic(a)) * 50
            let drift = Vec2(g.amp.x * sin(g.freq.x * t + g.phase),
                             g.amp.y * sin(g.freq.y * t + g.phase * 1.7))
            g.position = g.anchor + drift + Vec2(0, rise)
            g.tilt = 0.14 * cos(g.freq.x * t + g.phase)
            g.scale = t < g.appearAt ? 0 : 0.55 + 0.45 * Ease.outBack(a)
            g.alpha = Ease.outCubic(a)
            g.tailPhase = t * 4.2 + g.phase
            g.eyesClosed = (t + g.blinkOffset).truncatingRemainder(dividingBy: 3.1) < 0.13
            if let v = g.vanishAt {
                let p = Ease.clamp01((t - v) / Self.vanishDuration)
                g.scale *= 1 + 0.45 * p
                g.alpha *= 1 - p
                g.position.y -= 40 * Ease.outCubic(p)
                if p >= 1 { g.gone = true }
            }
            ghosts[i] = g
        }
    }

    public func hit(at point: Vec2) -> Int? {
        for i in ghosts.indices.reversed() {
            let g = ghosts[i]
            guard !g.gone, g.vanishAt == nil, g.alpha > 0.3 else { continue }
            if (g.position - point).length <= g.size * 0.55 * g.scale { return i }
        }
        return nil
    }

    @discardableResult
    public func vanish(at point: Vec2) -> Bool {
        guard spec.tapToVanish, let i = hit(at: point) else { return false }
        ghosts[i].vanishAt = time
        vanishedCount += 1
        return true
    }

    /// Смещение зрачков в сторону пальца (−1…1 по каждой оси).
    public static func pupilOffset(ghost: Ghost, target: Vec2?) -> Vec2 {
        guard let target else { return Vec2(0, 0) }
        let d = target - ghost.position
        let len = max(1, d.length)
        let k = min(1, len / 120)
        return Vec2(d.x / len * k, d.y / len * k)
    }
}

// MARK: - Огибающая эффекта

public enum EffectEnvelope {
    public static let fadeIn = 0.35
    public static let fadeOut = 0.6

    /// Общая прозрачность слоя эффекта во времени: плавное появление и исчезновение.
    public static func alpha(time t: Double, duration: Double) -> Double {
        if t < 0 || t > duration { return 0 }
        let a = Ease.clamp01(t / fadeIn)
        let b = Ease.clamp01((duration - t) / fadeOut)
        return min(a, b)
    }
}
