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
/// расстояние от центра спирали монотонно меняется (это спираль, а не круги), крупно и за разумное время.
/// Работает и «на лету» — пока палец ещё рисует. Случайно при обычном пользовании такое не нарисовать.
public final class SpiralDetector {
    public enum Result: Equatable {
        case recognized(turns: Double)
        case rejected(String)
    }

    public struct Stats: Sendable, Equatable {
        public var turns = 0.0
        public var consistency = 0.0
        public var diameter = 0.0
        public var duration = 0.0
        /// |корреляция| номера точки и расстояния до центра спирали: 1 — идеальная спираль, ~0 — круги.
        public var trend = 0.0
    }

    public var params: SpiralParams

    public init(params: SpiralParams = SpiralParams()) { self.params = params }

    public func analyze(_ pts: [StrokePoint]) -> Stats {
        var st = Stats()
        guard pts.count >= 3, let first = pts.first, let last = pts.last else { return st }
        st.duration = last.t - first.t
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        for p in pts { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        st.diameter = max(maxX - minX, maxY - minY)
        let cx = (maxX + minX) / 2, cy = (maxY + minY) / 2

        var total = 0.0, positive = 0.0, negative = 0.0
        var prev: Double?
        for p in pts {
            let dx = p.x - cx, dy = p.y - cy
            guard dx * dx + dy * dy > 64 else { prev = nil; continue }   // у самого центра угол неустойчив
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
        st.turns = abs(total) / (2 * .pi)
        st.consistency = max(positive, negative) / max(1e-9, positive + negative)

        // Центр спирали — тот конец штриха, что ближе к середине (внутренний виток).
        func dist(_ p: StrokePoint) -> Double { ((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)).squareRoot() }
        let core = dist(first) < dist(last) ? first : last
        let n = Double(pts.count)
        var si = 0.0, sr = 0.0, sii = 0.0, srr = 0.0, sir = 0.0
        for (i, p) in pts.enumerated() {
            let r = ((p.x - core.x) * (p.x - core.x) + (p.y - core.y) * (p.y - core.y)).squareRoot()
            let x = Double(i)
            si += x; sr += r; sii += x * x; srr += r * r; sir += x * r
        }
        let cov = sir / n - (si / n) * (sr / n)
        let vi = sii / n - (si / n) * (si / n), vr = srr / n - (sr / n) * (sr / n)
        st.trend = vi > 0 && vr > 0 ? abs(cov / (vi * vr).squareRoot()) : 0
        return st
    }

    /// Похоже ли уже на начало спирали — тогда можно показывать светящийся след.
    public func looksLikeSpiral(_ pts: [StrokePoint]) -> Bool {
        guard pts.count >= 12 else { return false }
        let s = analyze(pts)
        return s.turns >= 0.55 && s.consistency >= params.directionConsistency && s.diameter >= params.minDiameter * 0.55
    }

    public func evaluate(_ pts: [StrokePoint]) -> Result {
        guard pts.count >= 24 else { return .rejected("мало точек") }
        let s = analyze(pts)
        guard s.duration >= params.minDuration else { return .rejected("слишком быстро") }
        guard s.duration <= params.maxDuration else { return .rejected("слишком долго") }
        guard s.diameter >= params.minDiameter else { return .rejected("слишком мелко") }
        guard s.turns >= params.minTurns else { return .rejected(String(format: "витков %.2f", s.turns)) }
        guard s.consistency >= params.directionConsistency else { return .rejected("вращение не в одну сторону") }
        guard s.trend >= params.minRadiusTrend else { return .rejected(String(format: "это круги, а не спираль (%.2f)", s.trend)) }
        return .recognized(turns: s.turns)
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
