package ru.sberkids.funlayer.core

import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

// Перенос ios/FunLayerCore/Sources/FunLayerCore/Detectors.swift 1:1.
// Чистые конечные автоматы: ни одного Android API внутри, тестируются на JVM.

data class ShakeParams(val threshold: Double = 1.3, val peaks: Int = 3, val window: Double = 1.0)
data class PullHoldParams(val distance: Double = 90.0, val hold: Double = 1.0)
data class PalmParams(
    val minTouches: Int = 3,
    val minRadius: Double = 30.0,
    val hold: Double = 1.2,
    val maxMovement: Double = 70.0,
    val maxHold: Double = 6.0,
)
data class FlipParams(val down: Double = 0.8, val maxDown: Double = 6.0)
data class TapParams(val target: String = "settings.version", val taps: Int = 7, val maxGap: Double = 0.8)

data class SpiralParams(val minTurns: Double = 2.0, val minDiameter: Double = 120.0, val minDuration: Double = 0.6,
                        val maxDuration: Double = 4.0, val directionConsistency: Double = 0.85, val minRadiusChange: Double = 0.35)

data class StrokePoint(val x: Double, val y: Double, val t: Double)

/** Спираль одним штрихом (перенос SpiralDetector.swift): ≥ N витков, вращение в одну сторону, радиус меняется. */
class SpiralDetector(var params: SpiralParams = SpiralParams()) {
    sealed interface Result {
        data class Recognized(val turns: Double) : Result
        data class Rejected(val why: String) : Result
    }

    fun evaluate(pts: List<StrokePoint>): Result {
        if (pts.size < 24) return Result.Rejected("мало точек")
        val duration = pts.last().t - pts.first().t
        if (duration < params.minDuration) return Result.Rejected("слишком быстро")
        if (duration > params.maxDuration) return Result.Rejected("слишком долго")
        val minX = pts.minOf { it.x }; val maxX = pts.maxOf { it.x }
        val minY = pts.minOf { it.y }; val maxY = pts.maxOf { it.y }
        if (maxOf(maxX - minX, maxY - minY) < params.minDiameter) return Result.Rejected("слишком мелко")
        val cx = (maxX + minX) / 2; val cy = (maxY + minY) / 2
        var total = 0.0; var pos = 0.0; var neg = 0.0
        var prev: Double? = null
        val radii = ArrayList<Double>(pts.size)
        for (p in pts) {
            val dx = p.x - cx; val dy = p.y - cy
            val r = kotlin.math.sqrt(dx * dx + dy * dy)
            radii += r
            if (r <= 8) { prev = null; continue }
            val a = kotlin.math.atan2(dy, dx)
            prev?.let { pa ->
                var d = a - pa
                if (d > Math.PI) d -= 2 * Math.PI
                if (d < -Math.PI) d += 2 * Math.PI
                total += d
                if (d > 0) pos += d else neg -= d
            }
            prev = a
        }
        val turns = kotlin.math.abs(total) / (2 * Math.PI)
        if (turns < params.minTurns) return Result.Rejected("витков $turns")
        if (maxOf(pos, neg) / maxOf(1e-9, pos + neg) < params.directionConsistency) return Result.Rejected("вращение не в одну сторону")
        val k = maxOf(3, radii.size / 7)
        val rStart = radii.take(k).average(); val rEnd = radii.takeLast(k).average()
        if (kotlin.math.abs(rStart - rEnd) / maxOf(1.0, maxOf(rStart, rEnd)) < params.minRadiusChange) return Result.Rejected("это круги, а не спираль")
        return Result.Recognized(turns)
    }
}

/** N нажатий по элементу подряд (как «режим разработчика» Android). */
class TapSequenceDetector(var params: TapParams = TapParams()) {
    sealed interface Output {
        data object None : Output
        data class Progress(val done: Int, val left: Int) : Output
        data object Triggered : Output
    }
    private var count = 0
    private var last = Double.NEGATIVE_INFINITY

    fun reset() { count = 0; last = Double.NEGATIVE_INFINITY }

    fun feed(target: String, time: Double): Output {
        if (target != params.target) return Output.None
        if (time - last > params.maxGap) count = 0
        last = time
        count++
        if (count >= params.taps) { reset(); return Output.Triggered }
        return Output.Progress(count, params.taps - count)
    }
}

/** Вход — линейное ускорение без гравитации в g (Sensor.TYPE_LINEAR_ACCELERATION / 9.81). */
class ShakeDetector(var params: ShakeParams = ShakeParams()) {
    private val peaks = ArrayDeque<Double>()
    private var above = false
    private val minPeakGap = 0.07

    fun reset() { peaks.clear(); above = false }

    fun feed(x: Double, y: Double, z: Double, time: Double): Boolean {
        val magnitude = sqrt(x * x + y * y + z * z)
        while (peaks.isNotEmpty() && time - peaks.first() > params.window) peaks.removeFirst()
        if (magnitude >= params.threshold) {
            if (!above && (peaks.lastOrNull()?.let { time - it >= minPeakGap } ?: true)) peaks.addLast(time)
            above = true
        } else if (magnitude < params.threshold * 0.6) {
            above = false
        }
        if (peaks.size >= params.peaks) { reset(); return true }
        return false
    }
}

class PullHoldDetector(var params: PullHoldParams = PullHoldParams()) {
    sealed interface Output {
        data object Idle : Output
        data class Progress(val value: Double) : Output
        data object Triggered : Output
    }

    private var startedAt: Double? = null
    private var fired = false

    fun reset() { startedAt = null; fired = false }

    fun feed(distance: Double, time: Double): Output {
        if (distance < params.distance * 0.25) { reset(); return Output.Idle }
        if (fired) return Output.Idle
        if (distance >= params.distance) {
            val start = startedAt ?: time
            startedAt = start
            val p = (time - start) / params.hold
            if (p >= 1) { fired = true; startedAt = null; return Output.Triggered }
            return Output.Progress(max(0.0, p))
        }
        if (distance < params.distance * 0.75) startedAt = null
        return Output.Progress(0.0)
    }

    fun pullFraction(distance: Double) = min(1.0, max(0.0, distance / params.distance))
}

/** radius — MotionEvent.getTouchMajor(i) / 2 в dp. */
data class TouchSample(val x: Double, val y: Double, val radius: Double)

class PalmDetector(var params: PalmParams = PalmParams()) {
    enum class Output { NONE, BEGAN, PROGRESS, ARMED, TRIGGERED, CANCELLED }
    private enum class State { IDLE, HOLDING, ARMED, CANCELLED }

    private var state = State.IDLE
    private var startTime = 0.0
    private var startX = 0.0
    private var startY = 0.0
    private var lastPalmLike = 0.0
    private val dropGrace = 0.25
    var progress = 0.0
        private set

    fun reset() { state = State.IDLE; progress = 0.0 }

    fun isPalmLike(t: List<TouchSample>) =
        t.size >= params.minTouches || (t.maxOfOrNull { it.radius } ?: 0.0) >= params.minRadius

    fun feed(touches: List<TouchSample>, time: Double): Output {
        if (touches.isEmpty()) {
            val out = when (state) {
                State.ARMED -> Output.TRIGGERED
                State.HOLDING -> Output.CANCELLED
                else -> Output.NONE
            }
            reset()
            return out
        }
        val palmLike = isPalmLike(touches)
        val cx = touches.sumOf { it.x } / touches.size
        val cy = touches.sumOf { it.y } / touches.size
        val moved = sqrt((cx - startX) * (cx - startX) + (cy - startY) * (cy - startY))
        return when (state) {
            State.IDLE -> {
                if (!palmLike) return Output.NONE
                startTime = time; lastPalmLike = time; startX = cx; startY = cy
                state = State.HOLDING; progress = 0.0
                Output.BEGAN
            }
            State.HOLDING -> {
                if (palmLike) lastPalmLike = time
                if ((!palmLike && time - lastPalmLike > dropGrace) || moved > params.maxMovement) {
                    state = State.CANCELLED; return Output.CANCELLED
                }
                progress = (time - startTime) / params.hold
                if (progress >= 1) { state = State.ARMED; Output.ARMED } else Output.PROGRESS
            }
            State.ARMED -> {
                if (time - startTime > params.maxHold || moved > params.maxMovement * 1.5) {
                    state = State.CANCELLED; Output.CANCELLED
                } else Output.NONE
            }
            State.CANCELLED -> Output.NONE
        }
    }
}

/** gravityZ: на Android TYPE_GRAVITY.z / 9.81 со знаком минус (экран вверх → −1, как на iOS). */
class FaceDownFlipDetector(var params: FlipParams = FlipParams()) {
    private var downSince: Double? = null
    private var longEnough = false

    fun reset() { downSince = null; longEnough = false }

    fun feed(gravityZ: Double, time: Double): Boolean {
        if (gravityZ > 0.8) {
            val since = downSince ?: time
            downSince = since
            val dt = time - since
            longEnough = dt >= params.down && dt <= params.maxDown
            return false
        }
        if (gravityZ < -0.5 && downSince != null) {
            val fire = longEnough
            reset()
            return fire
        }
        return false
    }
}
