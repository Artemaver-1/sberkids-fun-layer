import Foundation

// Детекторы жестов — чистые конечные автоматы. На вход: сэмплы датчиков/касаний
// и время, на выход: событие. Ни одного системного API внутри, поэтому одна и та же
// логика (и одни и те же тесты) работает на iOS и переносится на Android.

// MARK: - Тряска

/// Тряска = N пиков линейного ускорения выше порога в скользящем окне.
/// Вход — ускорение БЕЗ гравитации (iOS: CMDeviceMotion.userAcceleration,
/// Android: Sensor.TYPE_LINEAR_ACCELERATION), в g.
public final class ShakeDetector {
    public var params: ShakeParams
    private var peaks: [Double] = []
    private var above = false
    private let minPeakGap = 0.07

    public init(params: ShakeParams = ShakeParams()) { self.params = params }

    public func reset() { peaks.removeAll(); above = false }

    /// - Returns: true, когда тряска распознана.
    public func feed(x: Double, y: Double, z: Double, time: Double) -> Bool {
        let magnitude = (x * x + y * y + z * z).squareRoot()
        peaks.removeAll { time - $0 > params.window }
        if magnitude >= params.threshold {
            if !above, (peaks.last.map { time - $0 >= minPeakGap } ?? true) {
                peaks.append(time)
            }
            above = true
        } else if magnitude < params.threshold * 0.6 {
            // гистерезис: пик засчитывается заново только после спада
            above = false
        }
        if peaks.count >= params.peaks {
            reset()
            return true
        }
        return false
    }
}

// MARK: - Потянуть и держать

/// Список потянули вниз дальше `distance` и держат `hold` секунд.
/// Вход — текущая величина «перетяга» (pull-to-refresh offset) в pt.
public final class PullHoldDetector {
    public enum Output: Equatable { case idle, progress(Double), triggered }

    public var params: PullHoldParams
    private var startedAt: Double?
    private var fired = false

    public init(params: PullHoldParams = PullHoldParams()) { self.params = params }

    public func reset() { startedAt = nil; fired = false }

    public func feed(distance: Double, time: Double) -> Output {
        if distance < params.distance * 0.25 {
            // отпустили — можно срабатывать снова
            reset()
            return .idle
        }
        if fired { return .idle }
        if distance >= params.distance {
            let start = startedAt ?? time
            startedAt = start
            let p = (time - start) / params.hold
            if p >= 1 {
                fired = true
                startedAt = nil
                return .triggered
            }
            return .progress(max(0, p))
        }
        if distance < params.distance * 0.75 { startedAt = nil }
        // ещё тянет, но порог не взят — прогресс по расстоянию для «выглядывающего банана»
        return .progress(0)
    }

    /// Насколько близко к порогу (0…1) — для визуальной подсказки.
    public func pullFraction(distance: Double) -> Double {
        min(1, max(0, distance / params.distance))
    }
}

// MARK: - Ладонь на экране

public struct TouchSample: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var radius: Double
    public init(x: Double, y: Double, radius: Double) { self.x = x; self.y = y; self.radius = radius }
}

/// Ладонь = ≥ minTouches касаний одновременно ИЛИ одно очень крупное пятно касания,
/// почти без движения, дольше `hold`. Срабатывает в момент, когда ладонь убрали —
/// «открыл глаза, а призраки уже тут».
public final class PalmDetector {
    public enum State: Equatable { case idle, holding(Double), armed, cancelled }
    public enum Output: Equatable { case none, began, progress(Double), armed, triggered, cancelled }

    public var params: PalmParams
    public private(set) var state: State = .idle
    private var startTime = 0.0
    private var startCentroid = (x: 0.0, y: 0.0)
    private var lastPalmLike = 0.0
    private let dropGrace = 0.6

    public init(params: PalmParams = PalmParams()) { self.params = params }

    public func reset() { state = .idle }

    public func isPalmLike(_ touches: [TouchSample]) -> Bool {
        touches.count >= params.minTouches || (touches.map(\.radius).max() ?? 0) >= params.minRadius
    }

    public func feed(touches: [TouchSample], time: Double) -> Output {
        if touches.isEmpty {
            switch state {
            case .armed:
                state = .idle
                return .triggered
            case .holding:
                state = .idle
                return .cancelled
            case .cancelled, .idle:
                state = .idle
                return .none
            }
        }

        let palmLike = isPalmLike(touches)
        let c = centroid(touches)

        switch state {
        case .idle:
            guard palmLike else { return .none }
            startTime = time
            lastPalmLike = time
            startCentroid = c
            state = .holding(0)
            return .began

        case .holding:
            if palmLike { lastPalmLike = time }
            if !palmLike && time - lastPalmLike > dropGrace {
                state = .cancelled
                return .cancelled
            }
            if distance(c, startCentroid) > params.maxMovement {
                state = .cancelled
                return .cancelled
            }
            let p = (time - startTime) / params.hold
            if p >= 1 {
                state = .armed
                return .armed
            }
            state = .holding(p)
            return .progress(p)

        case .armed:
            if time - startTime > params.maxHold || distance(c, startCentroid) > params.maxMovement * 1.5 {
                state = .cancelled
                return .cancelled
            }
            return .none

        case .cancelled:
            return .none
        }
    }

    private func centroid(_ t: [TouchSample]) -> (x: Double, y: Double) {
        let n = Double(t.count)
        return (t.reduce(0) { $0 + $1.x } / n, t.reduce(0) { $0 + $1.y } / n)
    }

    private func distance(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }
}

// MARK: - Спираль

public struct StrokePoint: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var t: Double
    public init(x: Double, y: Double, t: Double) { self.x = x; self.y = y; self.t = t }
}

/// Спираль одним непрерывным штрихом: ≥ N витков вокруг центра, вращение в одну сторону,
/// радиус заметно меняется (это спираль, а не просто круги), крупно и за разумное время.
/// Случайно при обычном пользовании такое не нарисовать.
public final class SpiralDetector {
    public enum Result: Equatable {
        case recognized(turns: Double)
        case rejected(String)
    }

    public var params: SpiralParams

    public init(params: SpiralParams = SpiralParams()) { self.params = params }

    public func evaluate(_ pts: [StrokePoint]) -> Result {
        guard pts.count >= 24, let first = pts.first, let last = pts.last else { return .rejected("мало точек") }
        let duration = last.t - first.t
        guard duration >= params.minDuration else { return .rejected("слишком быстро") }
        guard duration <= params.maxDuration else { return .rejected("слишком долго") }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let w = xs.max()! - xs.min()!, h = ys.max()! - ys.min()!
        guard max(w, h) >= params.minDiameter else { return .rejected("слишком мелко") }
        let cx = (xs.max()! + xs.min()!) / 2, cy = (ys.max()! + ys.min()!) / 2

        var total = 0.0, positive = 0.0, negative = 0.0
        var prev: Double?
        var radii: [Double] = []
        for p in pts {
            let dx = p.x - cx, dy = p.y - cy
            let r = (dx * dx + dy * dy).squareRoot()
            radii.append(r)
            guard r > 8 else { prev = nil; continue }   // у самого центра угол неустойчив
            let a = atan2(dy, dx)
            if let pa = prev {
                var d = a - pa
                if d > .pi { d -= 2 * .pi }
                if d < -.pi { d += 2 * .pi }
                total += d
                if d > 0 { positive += d } else { negative -= d }
            }
            prev = a
        }
        let turns = abs(total) / (2 * .pi)
        guard turns >= params.minTurns else { return .rejected(String(format: "витков %.2f", turns)) }
        let consistency = max(positive, negative) / max(1e-9, positive + negative)
        guard consistency >= params.directionConsistency else { return .rejected("вращение не в одну сторону") }
        let k = max(3, radii.count / 7)
        let rStart = radii.prefix(k).reduce(0, +) / Double(k)
        let rEnd = radii.suffix(k).reduce(0, +) / Double(k)
        let change = abs(rStart - rEnd) / max(1, max(rStart, rEnd))
        guard change >= params.minRadiusChange else { return .rejected("это круги, а не спираль") }
        return .recognized(turns: turns)
    }
}

// MARK: - Серия нажатий

/// N нажатий по одному элементу, между нажатиями не больше `maxGap`.
/// Приложение сообщает о нажатии строкой-идентификатором элемента.
public final class TapSequenceDetector {
    public enum Output: Equatable { case none, progress(done: Int, left: Int), triggered }

    public var params: TapParams
    private var count = 0
    private var last = -Double.infinity

    public init(params: TapParams = TapParams()) { self.params = params }

    public func reset() { count = 0; last = -.infinity }

    public func feed(target: String, time: Double) -> Output {
        guard target == params.target else { return .none }
        if time - last > params.maxGap { count = 0 }
        last = time
        count += 1
        if count >= params.taps {
            reset()
            return .triggered
        }
        return .progress(done: count, left: params.taps - count)
    }
}

// MARK: - Экраном вниз и обратно (запасной триггер для «ладони»)

/// Вход — z-компонента гравитации: −1 экран смотрит вверх, +1 — вниз
/// (iOS: CMDeviceMotion.gravity.z; Android: TYPE_GRAVITY, со знаком наоборот).
public final class FaceDownFlipDetector {
    public var params: FlipParams
    private var downSince: Double?
    private var wasDownLongEnough = false
    /// Телефон лежит экраном вниз уже достаточно долго — можно подать звуковой намёк.
    public var isArmed: Bool { wasDownLongEnough }

    public init(params: FlipParams = FlipParams()) { self.params = params }

    public func reset() { downSince = nil; wasDownLongEnough = false }

    public func feed(gravityZ: Double, time: Double) -> Bool {
        if gravityZ > 0.8 {
            let since = downSince ?? time
            downSince = since
            let dt = time - since
            wasDownLongEnough = dt >= params.down && dt <= params.maxDown
            if dt > params.maxDown { wasDownLongEnough = false }
            return false
        }
        if gravityZ < -0.5, downSince != nil {
            let fire = wasDownLongEnough
            reset()
            return fire
        }
        return false
    }
}
