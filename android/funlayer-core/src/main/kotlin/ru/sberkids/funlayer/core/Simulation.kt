package ru.sberkids.funlayer.core

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// Перенос Simulation.swift: позиции считаются аналитически от времени рождения,
// пропущенный кадр не ломает анимацию. Рисует Compose Canvas (drawImage / drawPath).

private fun clamp01(v: Double) = min(1.0, max(0.0, v))
private fun outCubic(t: Double) = 1 - (1 - clamp01(t)).let { it * it * it }
private fun outBack(t: Double): Double { val c1 = 1.70158; val c3 = c1 + 1; val u = clamp01(t) - 1; return 1 + c3 * u * u * u + c1 * u * u }

class Particle(
    val id: Int, val birth: Double, val size: Double, val speed: Double, val baseX: Double,
    val phase: Double, val wobbleSpeed: Double, val spin: Double,
) {
    var x = 0.0; var y = 0.0; var rotation = 0.0; var scaleX = 1.0; var scaleY = 1.0
    var spawned = false; var alive = true; var popAt: Double? = null; var popProgress = 0.0
}

class Droplet(val ox: Double, val oy: Double, val vx: Double, val vy: Double, val birth: Double, val size: Double) {
    var x = ox; var y = oy; var alpha = 1.0
}

class ParticleField(val spec: EffectLayer.Particles, val width: Double, val height: Double, private val rng: RandomSource) {
    val particles = mutableListOf<Particle>()
    val droplets = mutableListOf<Droplet>()
    var time = 0.0; private set

    init {
        for (i in 0 until spec.count) {
            val size = rng.range(spec.sizeMin, spec.sizeMax)
            val depth = (size - spec.sizeMin) / max(1.0, spec.sizeMax - spec.sizeMin)
            val speed = spec.speedMax - (spec.speedMax - spec.speedMin) * (0.35 * depth + 0.65 * rng.next())
            val birth = if (spec.count > 1) spec.spawn * i / (spec.count - 1) * rng.range(0.8, 1.0) else 0.0
            val m = size * 0.5
            particles += Particle(i, birth, size, speed, rng.range(m, max(m + 1, width - m)),
                rng.range(0.0, 2 * PI), spec.wobbleSpeed * rng.range(0.7, 1.3), spec.spin * rng.range(-1.0, 1.0))
        }
        update(0.0)
    }

    val allGone get() = particles.none { it.alive } && droplets.isEmpty()

    fun update(t: Double) {
        time = t
        for (p in particles) {
            if (!p.alive) continue
            val age = t - p.birth
            if (age < 0) { p.spawned = false; continue }
            p.spawned = true
            val travel = p.speed * age
            p.y = if (spec.up) height + p.size * 0.5 - travel else -p.size * 0.5 + travel
            p.x = p.baseX + spec.wobble * sin(p.phase + p.wobbleSpeed * age)
            p.rotation = if (p.spin == 0.0) 0.0 else p.phase + p.spin * age
            val breathe = 0.035 * sin(age * 5.3 + p.phase)
            p.scaleX = 1 + breathe; p.scaleY = 1 - breathe
            p.popAt?.let { p.popProgress = clamp01((t - it) / POP); if (p.popProgress >= 1) p.alive = false }
            if (if (spec.up) p.y < -p.size * 0.5 else p.y > height + p.size * 0.5) p.alive = false
        }
        droplets.removeAll { t - it.birth >= DROPLET_LIFE }
        for (d in droplets) {
            val a = t - d.birth
            d.x = d.ox + d.vx * a; d.y = d.oy + d.vy * a + 0.5 * 900 * a * a
            d.alpha = 1 - a / DROPLET_LIFE
        }
    }

    fun hit(x: Double, y: Double): Particle? =
        particles.lastOrNull { it.alive && it.spawned && it.popAt == null && hypot(it.x - x, it.y - y) <= it.size * 0.55 }

    fun pop(x: Double, y: Double): Boolean {
        if (!spec.tapToPop) return false
        val p = hit(x, y) ?: return false
        p.popAt = time
        for (k in 0 until 9) {
            val angle = 2 * PI * k / 9 + rng.range(-0.25, 0.25)
            val speed = rng.range(90.0, 190.0) * (p.size / 70)
            droplets += Droplet(p.x, p.y, cos(angle) * speed, sin(angle) * speed - 60, time, rng.range(2.5, 5.5))
        }
        return true
    }

    companion object { const val POP = 0.2; const val DROPLET_LIFE = 0.5 }
}

class Ghost(val id: Int, val ax: Double, val ay: Double, val size: Double, val phase: Double,
            val ampX: Double, val ampY: Double, val fx: Double, val fy: Double, val appearAt: Double,
            val colorIndex: Int, val blinkOffset: Double) {
    var x = ax; var y = ay; var scale = 0.0; var alpha = 0.0; var tilt = 0.0
    var eyesClosed = false; var vanishAt: Double? = null; var gone = false; var tailPhase = 0.0
}

class GhostField(val spec: EffectLayer.Ghosts, val width: Double, val height: Double, rng: RandomSource) {
    val ghosts = mutableListOf<Ghost>()
    var time = 0.0; private set

    init {
        val anchors = mutableListOf<Pair<Double, Double>>()
        val minDist = spec.sizeMax * 1.15
        repeat(spec.count) {
            var best = width / 2 to height / 2; var bestScore = -1.0
            for (attempt in 0 until 40) {
                val c = rng.range(width * 0.18, width * 0.82) to rng.range(height * 0.2, height * 0.78)
                val d = anchors.minOfOrNull { hypot(it.first - c.first, it.second - c.second) } ?: Double.MAX_VALUE
                if (d >= minDist) { best = c; break }
                if (d > bestScore) { best = c; bestScore = d }
            }
            anchors += best
        }
        anchors.forEachIndexed { i, (x, y) ->
            ghosts += Ghost(i, x, y, rng.range(spec.sizeMin, spec.sizeMax), rng.range(0.0, 2 * PI),
                rng.range(14.0, 30.0), rng.range(10.0, 22.0), rng.range(0.6, 1.1), rng.range(0.9, 1.6),
                0.15 + i * 0.35 + rng.range(0.0, 0.2), i % max(1, spec.palette.size), rng.range(0.0, 3.0))
        }
        update(0.0)
    }

    fun update(t: Double) {
        time = t
        for (g in ghosts) {
            if (g.gone) continue
            val a = clamp01((t - g.appearAt) / APPEAR)
            val rise = (1 - outCubic(a)) * 50
            g.x = g.ax + g.ampX * sin(g.fx * t + g.phase)
            g.y = g.ay + g.ampY * sin(g.fy * t + g.phase * 1.7) + rise
            g.tilt = 0.14 * cos(g.fx * t + g.phase)
            g.scale = if (t < g.appearAt) 0.0 else 0.55 + 0.45 * outBack(a)
            g.alpha = outCubic(a)
            g.tailPhase = t * 4.2 + g.phase
            g.eyesClosed = (t + g.blinkOffset) % 3.1 < 0.13
            g.vanishAt?.let {
                val p = clamp01((t - it) / VANISH)
                g.scale *= 1 + 0.45 * p; g.alpha *= 1 - p; g.y -= 40 * outCubic(p)
                if (p >= 1) g.gone = true
            }
        }
    }

    fun vanish(x: Double, y: Double): Boolean {
        if (!spec.tapToVanish) return false
        val g = ghosts.lastOrNull { !it.gone && it.vanishAt == null && it.alpha > 0.3 && hypot(it.x - x, it.y - y) <= it.size * 0.55 * it.scale }
            ?: return false
        g.vanishAt = time
        return true
    }

    companion object { const val APPEAR = 0.7; const val VANISH = 0.45 }
}

object EffectEnvelope {
    fun alpha(t: Double, duration: Double): Double =
        if (t < 0 || t > duration) 0.0 else min(clamp01(t / 0.35), clamp01((duration - t) / 0.6))
}
