import CoreMotion
import FunLayerCore
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct MotionSample: Sendable {
    let time: Double
    let ax: Double, ay: Double, az: Double
    let gz: Double
}

/// Акселерометр/гироскоп через CoreMotion. Разрешений не требует.
/// Включается только на экранах, где есть пасхалка с тряской или переворотом,
/// и только пока приложение активно — батарею не тратим.
@MainActor
final class MotionSensor {
    private let manager = CMMotionManager()
    private let shake = ShakeDetector()
    private let flip = FaceDownFlipDetector()
    private var shakeEnabled = false
    private var flipEnabled = false

    var onShake: (() -> Void)?
    var onFlip: (() -> Void)?

    var isRunning: Bool { manager.isDeviceMotionActive }

    func configure(shake shakeTrigger: Trigger?, flip flipTrigger: Trigger?) {
        shakeEnabled = shakeTrigger != nil
        flipEnabled = flipTrigger != nil
        if let t = shakeTrigger { shake.params = t.shake }
        if let t = flipTrigger { flip.params = t.flip }
        if shakeEnabled || flipEnabled { start() } else { stop() }
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        shake.reset()
        flip.reset()
        manager.deviceMotionUpdateInterval = 1.0 / 50.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            // в главный актор передаём только числа (Sendable), а не сам CMDeviceMotion
            let sample = MotionSample(time: motion.timestamp,
                                      ax: motion.userAcceleration.x, ay: motion.userAcceleration.y,
                                      az: motion.userAcceleration.z, gz: motion.gravity.z)
            MainActor.assumeIsolated {
                self?.handle(sample)
            }
        }
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
    }

    private func handle(_ m: MotionSample) {
        if shakeEnabled, shake.feed(x: m.ax, y: m.ay, z: m.az, time: m.time) { onShake?() }
        if flipEnabled, flip.feed(gravityZ: m.gz, time: m.time) { onFlip?() }
    }
}

/// «Ладонь на экране». Вешается на окно приложения и наблюдает за касаниями,
/// не мешая обычным нажатиям и прокрутке. Как только касания похожи на ладонь,
/// распознаватель переходит в .began — UIKit отменяет случайные нажатия под ладонью.
@MainActor
final class PalmGestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    let detector = PalmDetector()

    var onProgress: ((Double) -> Void)?
    var onArmed: (() -> Void)?
    var onTriggered: (() -> Void)?
    var onCancelled: (() -> Void)?
    /// Касания: количество, максимальный радиус, первая точка (калибровка, «глаза» призраков).
    var onSample: ((Int, Double, CGPoint?) -> Void)?

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = true
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    private func samples(_ event: UIEvent) -> [TouchSample] {
        guard let view else { return [] }
        return (event.allTouches ?? []).compactMap { touch in
            guard touch.phase != .ended, touch.phase != .cancelled else { return nil }
            let p = touch.location(in: view)
            return TouchSample(x: p.x, y: p.y, radius: touch.majorRadius)
        }
    }

    private func process(_ event: UIEvent) {
        let s = samples(event)
        onSample?(s.count, s.map(\.radius).max() ?? 0, s.first.map { CGPoint(x: $0.x, y: $0.y) })
        let out = detector.feed(touches: s, time: event.timestamp)
        switch out {
        case .began:
            if state == .possible { state = .began }
            onProgress?(0)
        case .progress(let p):
            if state == .began || state == .changed { state = .changed }
            onProgress?(p)
        case .armed:
            if state == .began || state == .changed { state = .changed }
            onArmed?()
        case .triggered:
            if state == .began || state == .changed { state = .ended } else { state = .failed }
            onTriggered?()
        case .cancelled:
            onCancelled?()
            if state == .began || state == .changed { state = .cancelled }
        case .none:
            if s.isEmpty && state == .possible { state = .failed }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { process(event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { process(event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { process(event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        detector.reset()
        onCancelled?()
        state = (state == .possible) ? .failed : .cancelled
    }

    override func reset() {
        super.reset()
        if case .holding = detector.state { detector.reset() }
        if case .cancelled = detector.state { detector.reset() }
    }

    nonisolated func gestureRecognizer(_ g: UIGestureRecognizer,
                                       shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
