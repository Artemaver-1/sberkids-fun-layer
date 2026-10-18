import Foundation

/// Какие экраны приложение отдаёт слою приколов.
/// Экраны с деньгами зашиты в код и НЕ могут быть включены конфигом:
/// контент-менеджер может только сузить список, но не расширить его.
public struct ScreenPolicy: Sendable {
    public static let sensitive: Set<String> = [
        "payment", "transfer", "requisites", "limits", "card_details", "top_up",
    ]

    public var knownScreens: Set<String>

    public init(knownScreens: Set<String>) {
        self.knownScreens = knownScreens
    }

    public func allows(_ screen: String) -> Bool {
        knownScreens.contains(screen) && !ScreenPolicy.sensitive.contains(screen)
    }
}

public struct ValidationReport: Sendable {
    public var warnings: [String] = []
    /// Конфиг валиден и явно выключает слой (enabled=false) — «рубильник» без релиза.
    public var disabledByConfig = false
    public var isUsable: Bool { config != nil }
    public var config: FunConfig?
}

/// Превращает сырой JSON в проверенную модель.
/// Принцип: всё неизвестное или битое отбрасывается точечно, а не роняет весь конфиг;
/// всё, что влияет на производительность и безопасность, жёстко ограничено.
public enum ConfigValidator {
    public static let supportedSchemaVersion = 1

    /// Жёсткие ограничители в коде — конфиг не может их превысить.
    public enum Limits {
        public static let maxParticles = 40
        public static let maxGhosts = 6
        public static let durationRange: ClosedRange<Double> = 1...10
        public static let maxDim = 0.35
        public static let sizeRange: ClosedRange<Double> = 8...220
        public static let speedRange: ClosedRange<Double> = 5...600
        public static let cooldownRange: ClosedRange<Double> = 1...600
        public static let maxEggs = 20
        public static let maxAssetBytes = 6 * 1024 * 1024
    }

    /// - Parameter baseURL: адрес самого конфига; относительные пути ресурсов
    ///   разрешаются от него. Так один и тот же конфиг работает на любом CDN.
    public static func decode(_ data: Data, policy: ScreenPolicy, baseURL: URL? = nil) -> ValidationReport {
        do {
            let dto = try JSONDecoder().decode(ConfigDTO.self, from: data)
            return validate(dto, policy: policy, baseURL: baseURL)
        } catch {
            return ValidationReport(warnings: ["JSON не разобран: \(error.localizedDescription)"], config: nil)
        }
    }

    public static func validate(_ dto: ConfigDTO, policy: ScreenPolicy, baseURL: URL? = nil) -> ValidationReport {
        var report = ValidationReport()
        func warn(_ s: String) { report.warnings.append(s) }

        guard let version = dto.schemaVersion, version <= supportedSchemaVersion, version >= 1 else {
            warn("Неподдерживаемая schemaVersion: \(dto.schemaVersion.map(String.init) ?? "нет")")
            return report
        }
        if dto.enabled == false {
            report.disabledByConfig = true
            warn("Слой выключен в конфиге (enabled=false)")
            return report
        }

        // Ресурсы
        var assets: [String: AssetRef] = [:]
        var totalBytes = 0
        for (key, a) in dto.assets ?? [:] {
            guard let s = a.url, !s.isEmpty, let parsed = URL(string: s, relativeTo: baseURL) else {
                warn("Ресурс \(key): нет адреса"); continue
            }
            var url: URL? = parsed.absoluteURL
            if parsed.scheme == nil {
                url = nil  // относительный путь без базы — только копия из сборки
            } else if parsed.scheme != "https" && parsed.scheme != "file" {
                warn("Ресурс \(key): разрешён только https"); continue
            }
            totalBytes += a.bytes ?? 0
            assets[key] = AssetRef(key: key, path: s, url: url, sha256: a.sha256?.lowercased(), bytes: a.bytes)
        }
        if totalBytes > Limits.maxAssetBytes {
            warn("Ресурсы весят \(totalBytes) байт — больше бюджета 6 МБ, конфиг отклонён")
            return report
        }
        func assetExists(_ key: String?) -> String? {
            guard let key, !key.isEmpty else { return nil }
            if key.hasPrefix("builtin:") { return key }
            return assets[key] != nil ? key : nil
        }

        // Тексты: каждое поле можно переопределить по отдельности
        var texts = FunTexts()
        if let t = dto.texts {
            func set(_ kp: WritableKeyPath<FunTexts, String>, _ v: String?) {
                if let v, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { texts[keyPath: kp] = v }
            }
            set(\.toastTitle, t.toastTitle); set(\.toastSubtitle, t.toastSubtitle)
            set(\.toastRepeatTitle, t.toastRepeatTitle)
            set(\.tapProgress, t.tapProgress)
            set(\.sheetTitle, t.sheetTitle); set(\.sheetIntro, t.sheetIntro)
            set(\.nextHintTitle, t.nextHintTitle); set(\.moreHintButton, t.moreHintButton)
            set(\.shareButton, t.shareButton); set(\.closeButton, t.closeButton)
            set(\.shareText, t.shareText); set(\.lockedSlot, t.lockedSlot)
            set(\.allFoundTitle, t.allFoundTitle); set(\.allFoundText, t.allFoundText)
            set(\.comingSoonText, t.comingSoonText)
        }
        if texts.shareText.contains("http") || texts.shareText.contains("www.") {
            warn("Ссылки в тексте шаринга запрещены — используется текст по умолчанию")
            texts.shareText = FunTexts().shareText
        }

        // Пасхалки
        var eggs: [Egg] = []
        var seen = Set<String>()
        for (i, e) in (dto.eggs ?? []).enumerated() {
            guard eggs.count < Limits.maxEggs else { warn("Слишком много пасхалок, лишние отброшены"); break }
            guard let id = e.id, !id.isEmpty, !seen.contains(id) else {
                warn("Пасхалка #\(i): нет id или он повторяется"); continue
            }
            if e.enabled == false { continue }
            guard let screen = e.screen, policy.allows(screen) else {
                warn("Пасхалка \(id): экран «\(e.screen ?? "-")» недоступен для приколов"); continue
            }
            guard let trigger = makeTrigger(e.trigger) else {
                warn("Пасхалка \(id): неизвестный триггер"); continue
            }
            let fallback = makeTrigger(e.fallbackTrigger)
            var variants: [Variant] = []
            for (vi, v) in (e.variants ?? []).enumerated() {
                guard let effect = makeEffect(v.effect, assetExists: assetExists, warn: { warn("\(id): \($0)") }) else {
                    warn("Пасхалка \(id): вариант #\(vi) без валидных слоёв"); continue
                }
                variants.append(Variant(id: v.id ?? "\(id)-\(vi)", weight: max(0, v.weight ?? 1), effect: effect))
            }
            guard !variants.isEmpty else { warn("Пасхалка \(id): нет вариантов эффекта"); continue }
            if variants.allSatisfy({ $0.weight == 0 }) {
                for k in variants.indices { variants[k].weight = 1 }
            }
            let hint = Hint(riddle: e.hint?.riddle ?? "", help: e.hint?.help ?? "",
                            pictograms: e.hint?.pictograms ?? [])
            seen.insert(id)
            eggs.append(Egg(
                id: id,
                order: e.order ?? (i + 1),
                title: e.title ?? id,
                pictogram: e.pictogram ?? "sparkles",
                screen: screen,
                trigger: trigger,
                fallbackTrigger: fallback,
                schedule: makeSchedule(e.schedule),
                cooldown: clamp(Double(e.cooldownMs ?? 3000) / 1000, Limits.cooldownRange),
                variants: variants,
                hint: hint
            ))
        }
        eggs.sort { $0.order < $1.order }
        guard !eggs.isEmpty else {
            warn("В конфиге нет ни одной рабочей пасхалки")
            return report
        }

        var teaser: Teaser?
        if let t = dto.teaser, t.enabled != false, let eggId = t.eggId, eggs.contains(where: { $0.id == eggId }),
           let screen = t.screen, policy.allows(screen) {
            teaser = Teaser(screen: screen, eggId: eggId,
                            delay: clamp(Double(t.delayMs ?? 4000) / 1000, 1...60),
                            maxShows: max(0, min(t.maxShows ?? 3, 20)),
                            text: t.text ?? "Потряси телефон!")
        }

        report.config = FunConfig(
            configId: dto.configId ?? "unnamed",
            announcedTotal: max(eggs.count, min(dto.announcedTotal ?? eggs.count, Limits.maxEggs)),
            foundSound: assetExists(dto.foundSound),
            texts: texts,
            teaser: teaser,
            eggs: eggs,
            assets: assets
        )
        return report
    }

    // MARK: - Части

    static func makeTrigger(_ t: TriggerDTO?) -> Trigger? {
        guard let t, let type = t.type, let kind = TriggerKind(rawValue: type) else { return nil }
        var trig = Trigger(kind: kind)
        if let v = t.threshold { trig.shake.threshold = clamp(v, 0.6...4) }
        if let v = t.peaks { trig.shake.peaks = max(1, min(v, 8)) }
        if let v = t.windowMs { trig.shake.window = clamp(Double(v) / 1000, 0.3...3) }
        if let v = t.distance { trig.pull.distance = clamp(v, 40...250) }
        if let v = t.holdMs {
            let s = clamp(Double(v) / 1000, 0.3...4)
            trig.pull.hold = s; trig.palm.hold = s
        }
        if let v = t.minTouches { trig.palm.minTouches = max(2, min(v, 10)) }
        if let v = t.minRadius { trig.palm.minRadius = clamp(v, 10...120) }
        if let v = t.maxMovement { trig.palm.maxMovement = clamp(v, 10...300) }
        if let v = t.maxHoldMs { trig.palm.maxHold = clamp(Double(v) / 1000, 2...20) }
        if let v = t.downMs { trig.flip.down = clamp(Double(v) / 1000, 0.3...5) }
        if let v = t.minTurns { trig.spiral.minTurns = clamp(v, 1.5...5) }
        if let v = t.minDiameter { trig.spiral.minDiameter = clamp(v, 60...400) }
        if let v = t.minDurationMs { trig.spiral.minDuration = clamp(Double(v) / 1000, 0.2...3) }
        if let v = t.maxDurationMs { trig.spiral.maxDuration = clamp(Double(v) / 1000, 1...10) }
        if let v = t.target, !v.isEmpty { trig.tap.target = v }
        if let v = t.taps { trig.tap.taps = max(2, min(v, 15)) }
        if let v = t.maxGapMs { trig.tap.maxGap = clamp(Double(v) / 1000, 0.2...2) }
        return trig
    }

    static func makeSchedule(_ s: ScheduleDTO?) -> Schedule? {
        guard let s else { return nil }
        func parse(_ str: String?) -> DateComponents? {
            guard let str else { return nil }
            let p = str.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3 else { return nil }
            return DateComponents(year: p[0], month: p[1], day: p[2])
        }
        let months = s.months.map { Set($0.filter { (1...12).contains($0) }) }
        return Schedule(from: parse(s.from), to: parse(s.to), months: months?.isEmpty == true ? nil : months)
    }

    static func makeEffect(_ e: EffectDTO?, assetExists: (String?) -> String?, warn: (String) -> Void) -> Effect? {
        guard let e else { return nil }
        var layers: [EffectLayer] = []
        for l in e.layers ?? [] {
            switch l.type {
            case "particles":
                guard let asset = assetExists(l.asset) else { warn("слой particles: нет ресурса \(l.asset ?? "-")"); continue }
                var p = ParticleSpec(asset: asset)
                if let v = l.count { p.count = max(1, min(v, Limits.maxParticles)) }
                if let v = l.sizeMin { p.sizeMin = clamp(v, Limits.sizeRange) }
                if let v = l.sizeMax { p.sizeMax = clamp(v, Limits.sizeRange) }
                if p.sizeMax < p.sizeMin { swap(&p.sizeMin, &p.sizeMax) }
                if let v = l.speedMin { p.speedMin = clamp(v, Limits.speedRange) }
                if let v = l.speedMax { p.speedMax = clamp(v, Limits.speedRange) }
                if p.speedMax < p.speedMin { swap(&p.speedMin, &p.speedMax) }
                if let v = l.direction, let d = ParticleSpec.Direction(rawValue: v) { p.direction = d }
                if let v = l.wobble { p.wobble = clamp(v, 0...80) }
                if let v = l.wobbleSpeed { p.wobbleSpeed = clamp(v, 0...6) }
                if let v = l.spin { p.spin = clamp(v, -6...6) }
                if let v = l.spawnMs { p.spawn = clamp(Double(v) / 1000, 0...8) }
                if let v = l.tapToPop { p.tapToPop = v }
                if let v = l.opacity { p.opacity = clamp(v, 0.1...1) }
                layers.append(.particles(p))
            case "lottie":
                guard let asset = assetExists(l.asset) else { warn("слой lottie: нет ресурса \(l.asset ?? "-")"); continue }
                var s = LottieSpec(asset: asset)
                if let v = l.speed { s.speed = clamp(v, 0.25...3) }
                if let v = l.placement, let p = LottieSpec.Placement(rawValue: v) { s.placement = p }
                layers.append(.lottie(s))
            case "fog":
                guard let asset = assetExists(l.asset) else { warn("слой fog: нет ресурса \(l.asset ?? "-")"); continue }
                let colors = (l.colors ?? []).compactMap(RGBA.init(hex:))
                var f = FogSpec(asset: asset, colors: colors.isEmpty ? [RGBA(r: 0.55, g: 0.45, b: 0.95)] : Array(colors.prefix(4)))
                if let v = l.opacity { f.opacity = clamp(v, 0.05...0.8) }
                if let v = l.drift { f.drift = clamp(v, 0...80) }
                if let v = l.stars { f.stars = max(0, min(v, 60)) }
                layers.append(.fog(f))
            case "ghosts":
                let palette = (l.palette ?? []).compactMap(RGBA.init(hex:))
                var g = GhostSpec(palette: palette.isEmpty ? [RGBA(r: 1, g: 1, b: 1)] : Array(palette.prefix(6)))
                if let v = l.count { g.count = max(1, min(v, Limits.maxGhosts)) }
                if let v = l.sizeMin { g.sizeMin = clamp(v, 40...160) }
                if let v = l.sizeMax { g.sizeMax = clamp(v, 40...160) }
                if g.sizeMax < g.sizeMin { swap(&g.sizeMin, &g.sizeMax) }
                if let v = l.tapToVanish { g.tapToVanish = v }
                if let v = l.followFinger { g.followFinger = v }
                layers.append(.ghosts(g))
            default:
                warn("неизвестный слой «\(l.type ?? "-")» пропущен")
            }
        }
        guard !layers.isEmpty else { return nil }
        let dimColor = e.dim?.color.flatMap(RGBA.init(hex:)) ?? RGBA(r: 0.05, g: 0.04, b: 0.15)
        return Effect(
            duration: clamp(Double(e.durationMs ?? 6000) / 1000, Limits.durationRange),
            dimColor: dimColor,
            dimOpacity: clamp(e.dim?.opacity ?? 0, 0...Limits.maxDim),
            layers: layers,
            sound: e.sound,
            interactSound: e.interactSound,
            haptic: Haptic(rawValue: e.haptic ?? "light") ?? .light,
            reveal: makeReveal(e.reveal)
        )
    }

    static func makeReveal(_ r: RevealDTO?) -> RevealSpec? {
        guard let r else { return nil }
        var s = RevealSpec()
        if let v = r.direction, let d = RevealSpec.Direction(rawValue: v) { s.direction = d }
        if let v = r.openMs { s.open = clamp(Double(v) / 1000, 0.3...3) }
        if let v = r.closeAtMs { s.closeAt = clamp(Double(v) / 1000, s.open + 0.5...9) }
        if let v = r.closeMs { s.close = clamp(Double(v) / 1000, 0.1...1.5) }
        return s
    }

    static func clamp(_ v: Double, _ r: ClosedRange<Double>) -> Double {
        v.isFinite ? min(max(v, r.lowerBound), r.upperBound) : r.lowerBound
    }
}
