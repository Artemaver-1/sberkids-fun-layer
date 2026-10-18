import FunLayerCore
import Lottie
import QuartzCore
import UIKit

/// Живой экземпляр эффекта: физика слоёв + загруженные картинки.
/// Создаётся при запуске эффекта и уничтожается сразу после — в фоне ничего не крутится.
@MainActor
final class EffectRuntime: Identifiable {
    enum Layer {
        case particles(ParticleField, UIImage?)
        case lottie(LottieSpec, URL?)
        case fog(FogSpec, UIImage?)
        case ghosts(GhostField)
    }

    let id = UUID()
    let decision: PlayDecision
    let start = CACurrentMediaTime()
    let size: CGSize
    private(set) var layers: [Layer] = []
    /// Куда смотрят призраки (палец ребёнка).
    var lookTarget: CGPoint?
    /// Длительность самой длинной Lottie-анимации эффекта с учётом скорости (с).
    private(set) var lottieDuration: Double = 0
    /// «Интерфейс отъезжает»: снимок экрана приложения и момент возврата (можно приблизить тапом).
    var revealSnapshot: UIImage?
    var revealCloseAt: Double = 0
    var reveal: RevealSpec? { decision.variant.effect.reveal }
    /// Нарисованная спираль: вспыхивает и превращается в портал, из которого вылетают призраки.
    var portalPath: [CGPoint]?
    var portalCenter: CGPoint = .zero
    var revealEnd: Double { reveal.map { revealCloseAt + $0.close + $0.settle } ?? 0 }

    /// Эффект длится не меньше своей Lottie-анимации — персонаж не исчезает на полпути.
    var hasLottie: Bool {
        layers.contains { if case .lottie(_, let url) = $0 { return url != nil } else { return false } }
    }

    var duration: Double {
        if reveal != nil { return revealEnd }
        return max(decision.variant.effect.duration, lottieDuration > 0 ? lottieDuration + 0.3 : 0)
    }

    /// Смещение интерфейса по X (pt) в момент t — механическое открытие и удар при возврате.
    func revealOffset(at t: Double, width: Double) -> (x: Double, y: Double, rotation: Double) {
        guard let r = reveal else { return (0, 0, 0) }
        let w = (r.direction == .right ? 1.0 : -1.0) * (width + 14)
        let jolt = 16.0 * (r.direction == .right ? 1.0 : -1.0)
        func easeInOut(_ p: Double) -> Double { p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }
        if t < revealCloseAt {
            if t < 0.16 {                                   // рывок: фиксатор отпущен
                let p = t / 0.16
                return (jolt * (1 - pow(1 - p, 3)) * (1 + 0.25 * sin(p * .pi)), 0, 0)
            }
            if t < 0.32 { return (jolt, 0, 0) }              // «клац»
            if t < r.open {                                  // сервопривод тянет с лёгкой вибрацией
                let p = (t - 0.32) / (r.open - 0.32)
                let x = jolt + (w - jolt) * easeInOut(p)
                return (x, 0.7 * sin(t * 160) * sin(p * .pi), 0)
            }
            return (w, 0, 0)
        }
        let tc = t - revealCloseAt
        if tc < r.close {                                    // влетает обратно с ускорением
            let p = tc / r.close
            return (w * (1 - pow(p, 2.4)), 0, 0)
        }
        let tau = tc - r.close                               // удар о край и затухающая тряска
        let sign = r.direction == .right ? -1.0 : 1.0
        let x = sign * 20 * exp(-7 * tau) * sin(26 * tau)
        let y = 7 * exp(-9 * tau) * sin(57 * tau)
        let rot = 0.9 * exp(-9 * tau) * sin(43 * tau)
        return (x, y, rot)
    }
    var effect: Effect { decision.variant.effect }

    init(decision: PlayDecision, size: CGSize, config: FunConfig, assets: AssetStore) {
        self.decision = decision
        self.size = size
        self.revealCloseAt = decision.variant.effect.reveal?.closeAt ?? 0
        let rng = SystemRandom()
        func image(_ key: String) -> UIImage? {
            if key.hasPrefix("builtin:") {
                return UIImage(named: String(key.dropFirst(8)))
                    ?? Bundle.main.path(forResource: String(key.dropFirst(8)), ofType: "png").flatMap(UIImage.init(contentsOfFile:))
            }
            return assets.localURL(forKey: key, in: config).flatMap { UIImage(contentsOfFile: $0.path) }
        }
        for layer in decision.variant.effect.layers {
            switch layer {
            case .particles(let spec):
                layers.append(.particles(ParticleField(spec: spec, width: size.width, height: size.height, rng: rng),
                                         image(spec.asset)))
            case .lottie(let spec):
                let url = assets.localURL(forKey: spec.asset, in: config)
                if let url, let anim = LottieAnimation.filepath(url.path, animationCache: DefaultAnimationCache.sharedCache) {
                    lottieDuration = max(lottieDuration, anim.duration / max(0.1, spec.speed))
                }
                layers.append(.lottie(spec, url))
            case .fog(let spec):
                layers.append(.fog(spec, image(spec.asset)))
            case .ghosts(let spec):
                layers.append(.ghosts(GhostField(spec: spec, width: size.width, height: size.height, rng: rng)))
            }
        }
    }

    var elapsed: Double { CACurrentMediaTime() - start }

    func update(to t: Double) {
        for l in layers {
            switch l {
            case .particles(let f, _): f.update(to: t)
            case .ghosts(let g): g.update(to: t)
            default: break
            }
        }
    }

    func hit(at p: CGPoint) -> Bool {
        let v = Vec2(p.x, p.y)
        for l in layers {
            switch l {
            case .particles(let f, _) where f.spec.tapToPop:
                if f.hit(at: v) != nil { return true }
            case .ghosts(let g) where g.spec.tapToVanish:
                if g.hit(at: v) != nil { return true }
            default: break
            }
        }
        return false
    }

    func tap(at p: CGPoint) -> Bool {
        let v = Vec2(p.x, p.y)
        for l in layers.reversed() {
            switch l {
            case .particles(let f, _):
                if f.pop(at: v) { return true }
            case .ghosts(let g):
                if g.vanish(at: v) { return true }
            default: break
            }
        }
        return false
    }
}
