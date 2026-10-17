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

    /// Эффект длится не меньше своей Lottie-анимации — персонаж не исчезает на полпути.
    var hasLottie: Bool {
        layers.contains { if case .lottie(_, let url) = $0 { return url != nil } else { return false } }
    }

    var duration: Double { max(decision.variant.effect.duration, lottieDuration > 0 ? lottieDuration + 0.3 : 0) }
    var effect: Effect { decision.variant.effect }

    init(decision: PlayDecision, size: CGSize, config: FunConfig, assets: AssetStore) {
        self.decision = decision
        self.size = size
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
