package ru.sberkids.funlayer.core

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.util.Calendar
import kotlin.math.max
import kotlin.math.min

// Перенос ConfigValidator.swift + Model.swift. Парсер — org.json, он входит в Android SDK:
// новых зависимостей нет. Тот же JSON, те же лимиты, те же правила, что на iOS.

enum class TriggerKind(val raw: String) { SHAKE("shake"), PULL_HOLD("pullHold"), PALM("palm"), FACE_DOWN_FLIP("faceDownFlip"), TAP_SEQUENCE("tapSequence");
    companion object { fun of(s: String?) = entries.firstOrNull { it.raw == s } }
}

data class Trigger(
    val kind: TriggerKind,
    val shake: ShakeParams = ShakeParams(),
    val pull: PullHoldParams = PullHoldParams(),
    val palm: PalmParams = PalmParams(),
    val flip: FlipParams = FlipParams(),
    val tap: TapParams = TapParams(),
)

/** «Интерфейс отъезжает и открывает сцену» — снимок экрана сдвигается и с ударом возвращается. */
data class RevealSpec(val toRight: Boolean = true, val open: Double = 1.1, val closeAt: Double = 5.7, val close: Double = 0.28)

data class Hint(val riddle: String, val help: String, val pictograms: List<String>)

sealed interface EffectLayer {
    data class Particles(
        val asset: String, val count: Int = 22, val sizeMin: Double = 34.0, val sizeMax: Double = 86.0,
        val speedMin: Double = 70.0, val speedMax: Double = 150.0, val up: Boolean = true,
        val wobble: Double = 18.0, val wobbleSpeed: Double = 1.6, val spin: Double = 0.4,
        val spawn: Double = 2.5, val tapToPop: Boolean = true, val opacity: Double = 1.0,
    ) : EffectLayer
    data class Lottie(val asset: String, val speed: Double = 1.0) : EffectLayer
    data class Fog(val asset: String, val colors: List<Long>, val opacity: Double = 0.55, val drift: Double = 14.0, val stars: Int = 24) : EffectLayer
    data class Ghosts(val count: Int = 4, val sizeMin: Double = 70.0, val sizeMax: Double = 110.0,
                      val palette: List<Long>, val tapToVanish: Boolean = true, val followFinger: Boolean = true) : EffectLayer
}

data class Effect(
    val duration: Double, val dimColor: Long, val dimOpacity: Double, val layers: List<EffectLayer>,
    val sound: String?, val interactSound: String?, val haptic: String,
    val reveal: RevealSpec? = null,
)

data class Variant(val id: String, val weight: Double, val effect: Effect)

data class Schedule(val from: Int?, val to: Int?, val months: Set<Int>?) {
    /** Дата как yyyymmdd. */
    fun isActive(cal: Calendar): Boolean {
        val m = cal.get(Calendar.MONTH) + 1
        val key = cal.get(Calendar.YEAR) * 10_000 + m * 100 + cal.get(Calendar.DAY_OF_MONTH)
        if (months != null && m !in months) return false
        if (from != null && key < from) return false
        if (to != null && key > to) return false
        return true
    }
}

data class Egg(
    val id: String, val order: Int, val title: String, val pictogram: String, val screen: String,
    val trigger: Trigger, val fallbackTrigger: Trigger?, val schedule: Schedule?,
    val cooldown: Double, val variants: List<Variant>, val hint: Hint,
) {
    val triggerKinds get() = listOfNotNull(trigger.kind, fallbackTrigger?.kind)
}

data class AssetRef(val key: String, val path: String, val url: String?, val sha256: String?, val bytes: Int?)

data class FunConfig(
    val configId: String, val announcedTotal: Int, val foundSound: String?,
    val texts: Map<String, String>, val eggs: List<Egg>, val assets: Map<String, AssetRef>,
)

class ValidationReport(val config: FunConfig?, val warnings: List<String>, val disabledByConfig: Boolean)

/** Экраны с деньгами закрыты в коде — конфиг не может их включить. */
class ScreenPolicy(private val knownScreens: Set<String>) {
    fun allows(screen: String) = screen in knownScreens && screen !in SENSITIVE
    companion object {
        val SENSITIVE = setOf("payment", "transfer", "requisites", "limits", "card_details", "top_up")
    }
}

object ConfigValidator {
    const val SUPPORTED_SCHEMA = 1
    const val MAX_PARTICLES = 40
    const val MAX_GHOSTS = 6
    const val MAX_DIM = 0.35
    const val MAX_ASSET_BYTES = 6 * 1024 * 1024

    fun decode(json: String, policy: ScreenPolicy, baseUrl: String? = null): ValidationReport {
        val warnings = mutableListOf<String>()
        val root = try { JSONObject(json) } catch (e: Exception) {
            return ValidationReport(null, listOf("JSON не разобран: ${e.message}"), false)
        }
        val version = root.optInt("schemaVersion", -1)
        if (version !in 1..SUPPORTED_SCHEMA) return ValidationReport(null, listOf("Неподдерживаемая schemaVersion"), false)
        if (root.has("enabled") && !root.optBoolean("enabled", true)) {
            return ValidationReport(null, listOf("Слой выключен в конфиге"), true)
        }

        val assets = mutableMapOf<String, AssetRef>()
        var totalBytes = 0
        root.optJSONObject("assets")?.let { a ->
            for (key in a.keys()) {
                val o = a.optJSONObject(key) ?: continue
                val path = o.optString("url").takeIf { it.isNotEmpty() } ?: continue
                val resolved = runCatching { baseUrl?.let { URI(it).resolve(path).toString() } ?: URI(path).takeIf { it.isAbsolute }?.toString() }.getOrNull()
                if (resolved != null && !resolved.startsWith("https://") && !resolved.startsWith("file:")) {
                    warnings += "Ресурс $key: разрешён только https"; continue
                }
                val bytes = if (o.has("bytes")) o.optInt("bytes") else null
                totalBytes += bytes ?: 0
                assets[key] = AssetRef(key, path, resolved, o.optString("sha256").takeIf { it.isNotEmpty() }?.lowercase(), bytes)
            }
        }
        if (totalBytes > MAX_ASSET_BYTES) return ValidationReport(null, warnings + "Ресурсы больше 6 МБ", false)
        fun asset(key: String?): String? = when {
            key.isNullOrEmpty() -> null
            key.startsWith("builtin:") -> key
            assets.containsKey(key) -> key
            else -> null
        }

        val texts = mutableMapOf<String, String>()
        root.optJSONObject("texts")?.let { t -> for (k in t.keys()) t.optString(k).takeIf { it.isNotBlank() }?.let { texts[k] = it } }
        texts["shareText"]?.let { if (it.contains("http") || it.contains("www.")) texts.remove("shareText") }

        val eggs = mutableListOf<Egg>()
        val seen = mutableSetOf<String>()
        val arr = root.optJSONArray("eggs") ?: JSONArray()
        for (i in 0 until arr.length()) {
            val e = arr.optJSONObject(i) ?: continue
            val id = e.optString("id")
            if (id.isEmpty() || id in seen) { warnings += "Пасхалка #$i: нет id"; continue }
            if (!e.optBoolean("enabled", true)) continue
            val screen = e.optString("screen")
            if (!policy.allows(screen)) { warnings += "$id: экран «$screen» недоступен"; continue }
            val trigger = trigger(e.optJSONObject("trigger")) ?: run { warnings += "$id: неизвестный триггер"; null } ?: continue
            val variants = mutableListOf<Variant>()
            val va = e.optJSONArray("variants") ?: JSONArray()
            for (vi in 0 until va.length()) {
                val v = va.optJSONObject(vi) ?: continue
                val effect = effect(v.optJSONObject("effect"), ::asset) ?: continue
                variants += Variant(v.optString("id", "$id-$vi"), max(0.0, v.optDouble("weight", 1.0)), effect)
            }
            if (variants.isEmpty()) { warnings += "$id: нет вариантов"; continue }
            val normalized = if (variants.all { it.weight == 0.0 }) variants.map { it.copy(weight = 1.0) } else variants
            val h = e.optJSONObject("hint")
            seen += id
            eggs += Egg(
                id = id, order = e.optInt("order", i + 1), title = e.optString("title", id),
                pictogram = e.optString("pictogram", "sparkles"), screen = screen,
                trigger = trigger, fallbackTrigger = trigger(e.optJSONObject("fallbackTrigger")),
                schedule = schedule(e.optJSONObject("schedule")),
                cooldown = clamp(e.optDouble("cooldownMs", 3000.0) / 1000, 1.0, 600.0),
                variants = normalized,
                hint = Hint(h?.optString("riddle") ?: "", h?.optString("help") ?: "",
                            h?.optJSONArray("pictograms")?.let { p -> (0 until p.length()).map { p.optString(it) } } ?: emptyList()),
            )
        }
        eggs.sortBy { it.order }
        if (eggs.isEmpty()) return ValidationReport(null, warnings + "Нет рабочих пасхалок", false)
        val announced = max(eggs.size, min(root.optInt("announcedTotal", eggs.size), 20))
        return ValidationReport(
            FunConfig(root.optString("configId", "unnamed"), announced, asset(root.optString("foundSound")), texts, eggs, assets),
            warnings, false,
        )
    }

    private fun trigger(o: JSONObject?): Trigger? {
        o ?: return null
        val kind = TriggerKind.of(o.optString("type")) ?: return null
        val hold = if (o.has("holdMs")) clamp(o.optDouble("holdMs") / 1000, 0.3, 4.0) else null
        return Trigger(
            kind = kind,
            shake = ShakeParams(
                threshold = clamp(o.optDouble("threshold", 1.3), 0.6, 4.0),
                peaks = o.optInt("peaks", 3).coerceIn(1, 8),
                window = clamp(o.optDouble("windowMs", 1000.0) / 1000, 0.3, 3.0),
            ),
            pull = PullHoldParams(clamp(o.optDouble("distance", 90.0), 40.0, 250.0), hold ?: 1.0),
            palm = PalmParams(
                minTouches = o.optInt("minTouches", 3).coerceIn(2, 10),
                minRadius = clamp(o.optDouble("minRadius", 30.0), 10.0, 120.0),
                hold = hold ?: 1.2,
                maxMovement = clamp(o.optDouble("maxMovement", 70.0), 10.0, 300.0),
                maxHold = clamp(o.optDouble("maxHoldMs", 6000.0) / 1000, 2.0, 20.0),
            ),
            flip = FlipParams(down = clamp(o.optDouble("downMs", 800.0) / 1000, 0.3, 5.0)),
            tap = TapParams(
                target = o.optString("target", "settings.version").ifEmpty { "settings.version" },
                taps = o.optInt("taps", 7).coerceIn(2, 15),
                maxGap = clamp(o.optDouble("maxGapMs", 800.0) / 1000, 0.2, 2.0),
            ),
        )
    }

    private fun schedule(o: JSONObject?): Schedule? {
        o ?: return null
        fun parse(s: String?) = s?.split("-")?.mapNotNull { it.toIntOrNull() }?.takeIf { it.size == 3 }?.let { it[0] * 10_000 + it[1] * 100 + it[2] }
        val months = o.optJSONArray("months")?.let { a -> (0 until a.length()).map { a.optInt(it) }.filter { it in 1..12 }.toSet() }
        return Schedule(parse(o.optString("from", null)), parse(o.optString("to", null)), months?.takeIf { it.isNotEmpty() })
    }

    private fun effect(o: JSONObject?, asset: (String?) -> String?): Effect? {
        o ?: return null
        val layers = mutableListOf<EffectLayer>()
        val la = o.optJSONArray("layers") ?: JSONArray()
        for (i in 0 until la.length()) {
            val l = la.optJSONObject(i) ?: continue
            when (l.optString("type")) {
                "particles" -> asset(l.optString("asset"))?.let { a ->
                    val sMin = clamp(l.optDouble("sizeMin", 34.0), 8.0, 220.0); val sMax = clamp(l.optDouble("sizeMax", 86.0), 8.0, 220.0)
                    val vMin = clamp(l.optDouble("speedMin", 70.0), 5.0, 600.0); val vMax = clamp(l.optDouble("speedMax", 150.0), 5.0, 600.0)
                    layers += EffectLayer.Particles(
                        asset = a, count = l.optInt("count", 22).coerceIn(1, MAX_PARTICLES),
                        sizeMin = min(sMin, sMax), sizeMax = max(sMin, sMax), speedMin = min(vMin, vMax), speedMax = max(vMin, vMax),
                        up = l.optString("direction", "up") != "down",
                        wobble = clamp(l.optDouble("wobble", 18.0), 0.0, 80.0), wobbleSpeed = clamp(l.optDouble("wobbleSpeed", 1.6), 0.0, 6.0),
                        spin = clamp(l.optDouble("spin", 0.4), -6.0, 6.0), spawn = clamp(l.optDouble("spawnMs", 2500.0) / 1000, 0.0, 8.0),
                        tapToPop = l.optBoolean("tapToPop", true), opacity = clamp(l.optDouble("opacity", 1.0), 0.1, 1.0),
                    )
                }
                "lottie" -> asset(l.optString("asset"))?.let { layers += EffectLayer.Lottie(it, clamp(l.optDouble("speed", 1.0), 0.25, 3.0)) }
                "fog" -> asset(l.optString("asset"))?.let { a ->
                    layers += EffectLayer.Fog(a, colors(l.optJSONArray("colors")).ifEmpty { listOf(0xFF8E7CFF) }.take(4),
                        clamp(l.optDouble("opacity", 0.55), 0.05, 0.8), clamp(l.optDouble("drift", 14.0), 0.0, 80.0),
                        l.optInt("stars", 24).coerceIn(0, 60))
                }
                "ghosts" -> {
                    val sMin = clamp(l.optDouble("sizeMin", 70.0), 40.0, 160.0); val sMax = clamp(l.optDouble("sizeMax", 110.0), 40.0, 160.0)
                    layers += EffectLayer.Ghosts(l.optInt("count", 4).coerceIn(1, MAX_GHOSTS), min(sMin, sMax), max(sMin, sMax),
                        colors(l.optJSONArray("palette")).ifEmpty { listOf(0xFFFFFFFF) }.take(6),
                        l.optBoolean("tapToVanish", true), l.optBoolean("followFinger", true))
                }
                else -> Unit  // неизвестный слой пропускается
            }
        }
        if (layers.isEmpty()) return null
        val dim = o.optJSONObject("dim")
        return Effect(
            duration = clamp(o.optDouble("durationMs", 6000.0) / 1000, 1.0, 10.0),
            dimColor = dim?.optString("color")?.let(::parseColor) ?: 0xFF0D0A26,
            dimOpacity = clamp(dim?.optDouble("opacity", 0.0) ?: 0.0, 0.0, MAX_DIM),
            layers = layers,
            sound = o.optString("sound").takeIf { it.isNotEmpty() },
            interactSound = o.optString("interactSound").takeIf { it.isNotEmpty() },
            haptic = o.optString("haptic", "light"),
            reveal = o.optJSONObject("reveal")?.let { r ->
                val open = clamp(r.optDouble("openMs", 1100.0) / 1000, 0.3, 3.0)
                RevealSpec(
                    toRight = r.optString("direction", "right") != "left",
                    open = open,
                    closeAt = clamp(r.optDouble("closeAtMs", 5700.0) / 1000, open + 0.5, 9.0),
                    close = clamp(r.optDouble("closeMs", 280.0) / 1000, 0.1, 1.5),
                )
            },
        )
    }

    private fun colors(a: JSONArray?) = a?.let { (0 until it.length()).mapNotNull { i -> parseColor(it.optString(i)) } } ?: emptyList()

    fun parseColor(hex: String): Long? {
        val s = hex.removePrefix("#")
        val v = s.toLongOrNull(16) ?: return null
        return when (s.length) {
            6 -> 0xFF000000 or v
            8 -> ((v and 0xFF) shl 24) or (v ushr 8)  // #RRGGBBAA → ARGB
            else -> null
        }
    }

    fun clamp(v: Double, lo: Double, hi: Double) = if (v.isNaN()) lo else min(max(v, lo), hi)
}
