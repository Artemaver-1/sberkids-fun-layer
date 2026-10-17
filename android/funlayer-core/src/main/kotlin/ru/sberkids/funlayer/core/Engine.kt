package ru.sberkids.funlayer.core

import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import kotlin.math.max

// Перенос EggEngine.swift + Progress.swift.

/** SharedPreferences / DataStore реализуют этот интерфейс в приложении. */
interface KeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String?)
}

/** Прогресс только на устройстве: какие пасхалки найдены. Никаких персональных данных. */
class ProgressStore(private val store: KeyValueStore) {
    private val found = mutableListOf<String>()
    private val hintLevel = mutableMapOf<String, Int>()
    var teaserShows = 0
        private set

    init {
        store.getString(KEY)?.let { raw ->
            runCatching {
                val o = JSONObject(raw)
                o.optJSONArray("found")?.let { a -> for (i in 0 until a.length()) found += a.optString(i) }
                teaserShows = o.optInt("teaserShows")
                o.optJSONObject("hintLevel")?.let { h -> for (k in h.keys()) hintLevel[k] = h.optInt(k) }
            }
        }
    }

    fun isFound(id: String) = id in found
    fun markFound(id: String): Boolean {
        if (id in found) return false
        found += id; save(); return true
    }
    fun incrementTeaser() { teaserShows++; save() }
    fun hintLevel(id: String) = hintLevel[id] ?: 0
    fun revealMoreHint(id: String) { hintLevel[id] = 1; save() }
    fun reset() { found.clear(); hintLevel.clear(); teaserShows = 0; save() }

    private fun save() {
        store.putString(KEY, JSONObject()
            .put("found", JSONArray(found))
            .put("teaserShows", teaserShows)
            .put("hintLevel", JSONObject(hintLevel as Map<*, *>))
            .toString())
    }

    companion object { const val KEY = "fun_layer.progress.v1" }
}

interface RandomSource { fun next(): Double }
fun RandomSource.range(a: Double, b: Double) = a + (b - a) * next()

class SystemRandom : RandomSource { override fun next() = Math.random() }

/** SplitMix64 — та же последовательность, что на iOS. */
class SeededRandom(seed: Long) : RandomSource {
    private var state = seed
    override fun next(): Double {
        state += -0x61c8864680b583ebL
        var z = state
        z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
        z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
        z = z xor (z ushr 31)
        return (z ushr 11).toDouble() / (1L shl 53).toDouble()
    }
}

object WeightedPicker {
    fun <T> pick(items: List<Pair<T, Double>>, rng: RandomSource): T? {
        val total = items.sumOf { max(0.0, it.second) }
        if (total <= 0) return items.firstOrNull()?.first
        var r = rng.next() * total
        for ((item, w) in items) { r -= max(0.0, w); if (r < 0) return item }
        return items.lastOrNull()?.first
    }
}

data class PlayDecision(val egg: Egg, val variant: Variant, val trigger: TriggerKind,
                        val isFirstFind: Boolean, val foundCount: Int, val total: Int)

sealed interface HintCard {
    data class Next(val egg: Egg, val level: Int) : HintCard
    data object ComingSoon : HintCard
    data object AllFound : HintCard
}

class EggEngine(var config: FunConfig, val progress: ProgressStore, private val rng: RandomSource = SystemRandom()) {
    private val lastPlayed = mutableMapOf<String, Long>()
    var isPlaying = false
        private set

    val total get() = config.announcedTotal
    val foundCount get() = config.eggs.count { progress.isFound(it.id) }

    fun eggs(screen: String, now: Calendar) = config.eggs.filter { it.screen == screen && (it.schedule?.isActive(now) ?: true) }

    fun activeTriggers(screen: String, now: Calendar): Map<TriggerKind, Trigger> {
        val result = linkedMapOf<TriggerKind, Trigger>()
        for (egg in eggs(screen, now)) {
            result.putIfAbsent(egg.trigger.kind, egg.trigger)
            egg.fallbackTrigger?.let { result.putIfAbsent(it.kind, it) }
        }
        return result
    }

    fun handle(kind: TriggerKind, screen: String, nowMs: Long, cal: Calendar = Calendar.getInstance()): PlayDecision? {
        if (isPlaying) return null
        val egg = eggs(screen, cal).firstOrNull { kind in it.triggerKinds } ?: return null
        lastPlayed[egg.id]?.let { if ((nowMs - it) / 1000.0 < egg.cooldown) return null }
        val variant = WeightedPicker.pick(egg.variants.map { it to it.weight }, rng) ?: egg.variants.first()
        val first = progress.markFound(egg.id)
        lastPlayed[egg.id] = nowMs
        isPlaying = true
        return PlayDecision(egg, variant, kind, first, foundCount, total)
    }

    fun effectFinished() { isPlaying = false }
    fun cancelEffect() { isPlaying = false }

    fun nextHint(): HintCard {
        config.eggs.firstOrNull { !progress.isFound(it.id) }?.let { return HintCard.Next(it, progress.hintLevel(it.id)) }
        return if (foundCount < total) HintCard.ComingSoon else HintCard.AllFound
    }
}

object Template {
    fun render(s: String, values: Map<String, String>) = values.entries.fold(s) { acc, (k, v) -> acc.replace("{$k}", v) }
}
