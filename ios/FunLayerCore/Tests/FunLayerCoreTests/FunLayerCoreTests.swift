import Foundation
import Testing
@testable import FunLayerCore

let policy = ScreenPolicy(knownScreens: ["main", "content", "profile", "settings", "piggy", "tasks", "transfer"])

/// Настоящий конфиг из cdn/ — тесты гарантируют, что то, что уезжает на CDN, валидно.
func productionConfigData(_ name: String = "config.json") throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("cdn/fun-layer/v1/\(name)"))
}

func loadConfig(_ json: String) -> ValidationReport {
    ConfigValidator.decode(Data(json.utf8), policy: policy, baseURL: URL(string: "https://cdn.example.ru/fun/v1/config.json"))
}

@Suite("Конфиг")
struct ConfigTests {
    @Test("Боевой конфиг с CDN валиден и без предупреждений")
    func productionConfig() throws {
        for name in ["config.json", "config-winter.json", "config-party.json"] {
            let r = ConfigValidator.decode(try productionConfigData(name), policy: policy,
                                           baseURL: URL(string: "https://example.github.io/repo/fun-layer/v1/\(name)"))
            #expect(r.warnings.isEmpty, "\(name): \(r.warnings)")
            let c = try #require(r.config)
            #expect(c.eggs.count == 4)
            #expect(c.announcedTotal == 4)
            let robots = try #require(c.egg(id: "robots"))
            #expect(robots.trigger.kind == .tapSequence)
            #expect(robots.trigger.tap.taps == 7)
            #expect(robots.variants[0].effect.reveal?.direction == .right)
        }
    }

    @Test("Относительные пути ресурсов разрешаются от адреса конфига")
    func relativeAssets() throws {
        let r = ConfigValidator.decode(try productionConfigData(), policy: policy,
                                       baseURL: URL(string: "https://cdn.example.ru/fun-layer/v1/config.json"))
        let bubble = try #require(r.config?.assets["bubble"])
        #expect(bubble.url?.absoluteString == "https://cdn.example.ru/fun-layer/v1/assets/bubble.png")
        #expect(bubble.fileName == "bubble.png")
    }

    @Test("Битый JSON не роняет приложение")
    func brokenJSON() {
        let r = loadConfig("{ this is not json")
        #expect(r.config == nil)
        #expect(!r.warnings.isEmpty)
    }

    @Test("Пустой объект и выключатель")
    func emptyAndKillSwitch() {
        #expect(loadConfig("{}").config == nil)
        #expect(loadConfig(#"{"schemaVersion":1,"enabled":false}"#).config == nil)
        #expect(loadConfig(#"{"schemaVersion":99,"eggs":[]}"#).config == nil)
    }

    @Test("Конфиг не может включить прикол на экране перевода")
    func sensitiveScreenRejected() {
        let json = #"""
        {"schemaVersion":1,"eggs":[
          {"id":"evil","screen":"transfer","trigger":{"type":"shake"},
           "variants":[{"effect":{"layers":[{"type":"particles","asset":"builtin:bubble"}]}}]},
          {"id":"ok","screen":"main","trigger":{"type":"shake"},
           "variants":[{"effect":{"layers":[{"type":"particles","asset":"builtin:bubble"}]}}]}
        ]}
        """#
        let r = loadConfig(json)
        #expect(r.config?.eggs.map(\.id) == ["ok"])
        #expect(r.warnings.contains { $0.contains("evil") })
    }

    @Test("Ограничители: частицы, длительность, затемнение")
    func clamps() throws {
        let json = #"""
        {"schemaVersion":1,"eggs":[{"id":"a","screen":"main","trigger":{"type":"shake","threshold":100},
          "variants":[{"effect":{"durationMs":999999,"dim":{"opacity":1},
            "layers":[{"type":"particles","asset":"builtin:bubble","count":100000,"sizeMax":9999}]}}]}]}
        """#
        let egg = try #require(loadConfig(json).config?.eggs.first)
        let effect = egg.variants[0].effect
        #expect(effect.duration == 10)
        #expect(effect.dimOpacity == ConfigValidator.Limits.maxDim)
        guard case .particles(let p) = effect.layers[0] else { Issue.record("нет частиц"); return }
        #expect(p.count == ConfigValidator.Limits.maxParticles)
        #expect(p.sizeMax == 220)
        #expect(egg.trigger.shake.threshold == 4)
    }

    @Test("Неизвестный слой и неизвестный триггер пропускаются точечно")
    func forwardCompatibility() {
        let json = #"""
        {"schemaVersion":1,"eggs":[
          {"id":"a","screen":"main","trigger":{"type":"shake"},
           "variants":[{"effect":{"layers":[{"type":"hologram3d"},{"type":"particles","asset":"builtin:bubble"}]}}]},
          {"id":"b","screen":"main","trigger":{"type":"telepathy"},
           "variants":[{"effect":{"layers":[{"type":"particles","asset":"builtin:bubble"}]}}]}
        ]}
        """#
        let r = loadConfig(json)
        #expect(r.config?.eggs.map(\.id) == ["a"])
        #expect(r.config?.eggs.first?.variants.first?.effect.layers.count == 1)
    }

    @Test("Ссылки в тексте шаринга запрещены")
    func noLinksInShare() {
        let json = #"""
        {"schemaVersion":1,"texts":{"shareText":"Скачай тут https://evil.example"},
         "eggs":[{"id":"a","screen":"main","trigger":{"type":"shake"},
           "variants":[{"effect":{"layers":[{"type":"particles","asset":"builtin:bubble"}]}}]}]}
        """#
        #expect(loadConfig(json).config?.texts.shareText == FunTexts().shareText)
    }

    @Test("Не-https ресурсы отклоняются")
    func httpRejected() {
        let json = #"""
        {"schemaVersion":1,"assets":{"x":{"url":"http://insecure.example/x.png"}},
         "eggs":[{"id":"a","screen":"main","trigger":{"type":"shake"},
           "variants":[{"effect":{"layers":[{"type":"particles","asset":"x"}]}}]}]}
        """#
        #expect(loadConfig(json).config == nil)
    }

    @Test("Расписание")
    func schedule() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let s = Schedule(from: DateComponents(year: 2026, month: 12, day: 15),
                         to: DateComponents(year: 2027, month: 1, day: 10), months: nil)
        let inside = cal.date(from: DateComponents(year: 2026, month: 12, day: 31))!
        let before = cal.date(from: DateComponents(year: 2026, month: 12, day: 14))!
        #expect(s.isActive(on: inside, calendar: cal))
        #expect(!s.isActive(on: before, calendar: cal))
        let monthsOnly = Schedule(from: nil, to: nil, months: [10])
        #expect(monthsOnly.isActive(on: cal.date(from: DateComponents(year: 2026, month: 10, day: 18))!, calendar: cal))
    }
}

@Suite("Детекторы")
struct DetectorTests {
    @Test("Три резких рывка — тряска")
    func shake() {
        let d = ShakeDetector()
        var fired = false
        var t = 0.0
        for k in 0..<30 {
            let a = (k % 5 == 0) ? 2.2 : 0.1  // пик каждые 100 мс при 50 Гц
            fired = fired || d.feed(x: a, y: 0, z: 0, time: t)
            t += 0.02
        }
        #expect(fired)
    }

    @Test("Ходьба — не тряска")
    func walkingIsNotShake() {
        let d = ShakeDetector()
        var fired = false
        for k in 0..<500 {
            let t = Double(k) * 0.02
            let a = 0.45 * abs(sin(t * 2 * .pi * 1.8))  // шаги ~0.45g
            fired = fired || d.feed(x: 0, y: a, z: 0, time: t)
        }
        #expect(!fired)
    }

    @Test("Медленные одиночные толчки не складываются в тряску")
    func slowBumps() {
        let d = ShakeDetector()
        var fired = false
        for k in 0..<10 {
            let t = Double(k) * 1.5
            fired = fired || d.feed(x: 2, y: 0, z: 0, time: t)
            fired = fired || d.feed(x: 0, y: 0, z: 0, time: t + 0.05)
        }
        #expect(!fired)
    }

    @Test("Потянуть и держать: прогресс, срабатывание один раз, повтор после отпускания")
    func pullHold() {
        let d = PullHoldDetector()
        #expect(d.feed(distance: 120, time: 0) == .progress(0))
        #expect(d.feed(distance: 120, time: 0.5) == .progress(0.5))
        #expect(d.feed(distance: 120, time: 1.01) == .triggered)
        #expect(d.feed(distance: 120, time: 1.5) == .idle)
        #expect(d.feed(distance: 0, time: 2) == .idle)
        _ = d.feed(distance: 120, time: 3)
        #expect(d.feed(distance: 120, time: 4.1) == .triggered)
    }

    @Test("Обычный pull-to-refresh без удержания не срабатывает")
    func quickPull() {
        let d = PullHoldDetector()
        _ = d.feed(distance: 120, time: 0)
        _ = d.feed(distance: 120, time: 0.4)
        #expect(d.feed(distance: 0, time: 0.5) == .idle)
        #expect(d.feed(distance: 120, time: 0.6) == .progress(0))
    }

    @Test("Ладонь: держим, отпускаем — срабатывает на отпускании")
    func palm() {
        let d = PalmDetector()
        let palm = [TouchSample(x: 100, y: 300, radius: 12), TouchSample(x: 140, y: 320, radius: 14),
                    TouchSample(x: 180, y: 310, radius: 13), TouchSample(x: 150, y: 380, radius: 20)]
        #expect(d.feed(touches: palm, time: 0) == .began)
        #expect(d.feed(touches: palm, time: 0.6) == .progress(0.5))
        #expect(d.feed(touches: palm, time: 1.25) == .armed)
        #expect(d.feed(touches: [], time: 1.5) == .triggered)
    }

    @Test("Ладонь: одно большое пятно касания тоже считается")
    func palmBigBlob() {
        let d = PalmDetector()
        #expect(d.feed(touches: [TouchSample(x: 200, y: 400, radius: 45)], time: 0) == .began)
    }

    @Test("Один палец и свайп тремя пальцами — не ладонь")
    func notPalm() {
        let d = PalmDetector()
        #expect(d.feed(touches: [TouchSample(x: 10, y: 10, radius: 8)], time: 0) == .none)
        #expect(d.feed(touches: [], time: 0.1) == .none)
        let three = (0..<3).map { TouchSample(x: 100 + Double($0) * 30, y: 300, radius: 10) }
        _ = d.feed(touches: three, time: 1)
        let moved = three.map { TouchSample(x: $0.x, y: $0.y + 200, radius: $0.radius) }
        #expect(d.feed(touches: moved, time: 1.3) == .cancelled)
        #expect(d.feed(touches: [], time: 1.4) == .none)
    }

    @Test("Убрал ладонь раньше времени — отмена")
    func palmTooShort() {
        let d = PalmDetector()
        let palm = (0..<4).map { TouchSample(x: 100 + Double($0) * 20, y: 300, radius: 12) }
        _ = d.feed(touches: palm, time: 0)
        _ = d.feed(touches: palm, time: 0.5)
        #expect(d.feed(touches: [], time: 0.6) == .cancelled)
    }

    @Test("Семь быстрых тапов по версии — срабатывает; пауза сбрасывает счёт")
    func tapSequence() {
        let d = TapSequenceDetector()
        var t = 0.0
        for i in 1...6 {
            #expect(d.feed(target: "settings.version", time: t) == .progress(done: i, left: 7 - i))
            t += 0.3
        }
        #expect(d.feed(target: "other", time: t) == .none)
        #expect(d.feed(target: "settings.version", time: t) == .triggered)
        _ = d.feed(target: "settings.version", time: 10)
        _ = d.feed(target: "settings.version", time: 10.3)
        #expect(d.feed(target: "settings.version", time: 12) == .progress(done: 1, left: 6))
    }

    func spiral(turns: Double, r0: Double, r1: Double, duration: Double = 2, cx: Double = 200, cy: Double = 400) -> [StrokePoint] {
        let n = 160
        return (0..<n).map { i in
            let p = Double(i) / Double(n - 1)
            let a = p * turns * 2 * .pi
            let r = r0 + (r1 - r0) * p
            return StrokePoint(x: cx + r * cos(a), y: cy + r * sin(a), t: p * duration)
        }
    }

    @Test("Спираль в 2,5 витка распознаётся (снаружи внутрь и изнутри наружу)")
    func spiralRecognized() {
        let d = SpiralDetector()
        if case .recognized(let turns) = d.evaluate(spiral(turns: 2.5, r0: 120, r1: 15)) { #expect(turns > 2.4) } else { Issue.record("не распознана") }
        if case .recognized = d.evaluate(spiral(turns: -2.3, r0: 12, r1: 110)) {} else { Issue.record("обратная не распознана") }
    }

    @Test("Не спираль: круги, мелко, быстро, мало витков, прокрутка, зигзаг")
    func spiralRejected() {
        let d = SpiralDetector()
        func rejected(_ pts: [StrokePoint]) -> Bool { if case .rejected = d.evaluate(pts) { return true } else { return false } }
        #expect(rejected(spiral(turns: 2.5, r0: 90, r1: 88)))                 // круги
        #expect(rejected(spiral(turns: 2.5, r0: 40, r1: 5)))                  // мелко
        #expect(rejected(spiral(turns: 2.5, r0: 120, r1: 15, duration: 0.3)))  // слишком быстро
        #expect(rejected(spiral(turns: 1.4, r0: 120, r1: 15)))                // мало витков
        let swipe = (0..<60).map { StrokePoint(x: 200, y: 700 - Double($0) * 8, t: Double($0) * 0.01) }
        #expect(rejected(swipe))
        let zigzag = (0..<80).map { StrokePoint(x: 60 + Double($0) * 3.5, y: 400 + ($0 % 10 < 5 ? 1 : -1) * 60, t: Double($0) * 0.02) }
        #expect(rejected(zigzag))
    }

    @Test("Экраном вниз и обратно")
    func flip() {
        let d = FaceDownFlipDetector()
        #expect(!d.feed(gravityZ: 0.95, time: 0))
        #expect(!d.feed(gravityZ: 0.95, time: 1.0))
        #expect(d.feed(gravityZ: -0.9, time: 1.4))
        // слишком коротко
        #expect(!d.feed(gravityZ: 0.95, time: 5))
        #expect(!d.feed(gravityZ: -0.9, time: 5.2))
    }
}

@Suite("Движок")
struct EngineTests {
    func engine(store: KeyValueStore = InMemoryStore(), seed: UInt64 = 1) throws -> EggEngine {
        let config = try #require(ConfigValidator.decode(try productionConfigData(), policy: policy).config)
        return EggEngine(config: config, progress: ProgressStore(store: store), rng: SeededRandom(seed: seed))
    }

    @Test("На каждом экране слушаем только свои датчики")
    func triggersPerScreen() throws {
        let e = try engine()
        let now = Date()
        #expect(Set(e.activeTriggers(on: "main", now: now).keys) == [.shake])
        #expect(Set(e.activeTriggers(on: "content", now: now).keys) == [.pullHold])
        #expect(Set(e.activeTriggers(on: "profile", now: now).keys) == [.spiral])
        #expect(Set(e.activeTriggers(on: "settings", now: now).keys) == [.tapSequence])
        #expect(e.activeTriggers(on: "transfer", now: now).isEmpty)
        #expect(e.activeTriggers(on: "piggy", now: now).isEmpty)
    }

    @Test("Находка, счётчик, подсказка к следующей")
    func findFlow() throws {
        let e = try engine()
        let t0 = Date()
        let d1 = try #require(e.handle(.shake, on: "main", now: t0))
        #expect(d1.egg.id == "bubbles")
        #expect(d1.isFirstFind)
        #expect(d1.foundCount == 1 && d1.total == 4)
        // пока играет — второй эффект не стартует
        #expect(e.handle(.shake, on: "main", now: t0) == nil)
        e.effectFinished(now: t0)
        guard case .next(let next) = e.nextHint(now: t0).kind else { Issue.record("нет подсказки"); return }
        #expect(next.id == "monkey")
        // кулдаун
        #expect(e.handle(.shake, on: "main", now: t0.addingTimeInterval(1)) == nil)
        let again = try #require(e.handle(.shake, on: "main", now: t0.addingTimeInterval(5)))
        #expect(!again.isFirstFind)
        #expect(again.foundCount == 1)
    }

    @Test("Нашёл все четыре — «все секреты найдены»")
    func allFound() throws {
        let e = try engine()
        let t = Date()
        for (kind, screen) in [(TriggerKind.shake, "main"), (.pullHold, "content"), (.spiral, "profile"), (.tapSequence, "settings")] {
            #expect(e.handle(kind, on: screen, now: t) != nil)
            e.effectFinished(now: t)
        }
        #expect(e.foundCount == 4)
        #expect(e.nextHint(now: t).kind == .allFound)
    }

    @Test("Прогресс переживает перезапуск приложения")
    func persistence() throws {
        let store = InMemoryStore()
        let e1 = try engine(store: store)
        _ = e1.handle(.pullHold, on: "content", now: Date())
        let e2 = try engine(store: store)
        #expect(e2.progress.isFound("monkey"))
        #expect(e2.foundCount == 1)
    }

    @Test("Тизер: только пока пузыри не найдены и не больше maxShows раз")
    func teaser() throws {
        let e = try engine()
        #expect(e.shouldShowTeaser(on: "main") != nil)
        #expect(e.shouldShowTeaser(on: "content") == nil)
        for _ in 0..<3 { e.teaserShown() }
        #expect(e.shouldShowTeaser(on: "main") == nil)
    }

    @Test("Веса вариантов: золотые пузыри ≈ 5%")
    func weights() {
        let rng = SeededRandom(seed: 42)
        var gold = 0
        let n = 100_000
        for _ in 0..<n where WeightedPicker.pick([("rainbow", 95.0), ("golden", 5.0)], rng: rng) == "golden" {
            gold += 1
        }
        let share = Double(gold) / Double(n)
        #expect(abs(share - 0.05) < 0.005)
    }
}

@Suite("Физика")
struct SimulationTests {
    @Test("Пузыри поднимаются, лопаются и улетают за экран")
    func bubbles() {
        var spec = ParticleSpec(asset: "builtin:bubble")
        spec.count = 10
        let f = ParticleField(spec: spec, width: 390, height: 844, rng: SeededRandom(seed: 7))
        f.update(to: 0.5)
        let first = f.particles[0]
        #expect(first.spawned && first.position.y < 844 + first.size)
        #expect(f.pop(at: first.position))
        #expect(f.droplets.count > 0)
        f.update(to: 0.5 + ParticleField.popDuration + 0.01)
        #expect(!f.particles[0].alive)
        f.update(to: 60)
        #expect(f.allGone)
    }

    @Test("Призраки не слипаются и исчезают по тапу")
    func ghosts() {
        let spec = GhostSpec(count: 4, palette: [RGBA(r: 1, g: 1, b: 1)])
        let f = GhostField(spec: spec, width: 390, height: 844, rng: SeededRandom(seed: 3))
        for i in 0..<f.ghosts.count {
            for j in (i + 1)..<f.ghosts.count {
                #expect((f.ghosts[i].anchor - f.ghosts[j].anchor).length > spec.sizeMin * 0.8)
            }
        }
        f.update(to: 3)
        let g = f.ghosts[0]
        #expect(g.alpha > 0.9)
        #expect(f.vanish(at: g.position))
        f.update(to: 3 + GhostField.vanishDuration + 0.01)
        #expect(f.ghosts[0].gone)
    }

    @Test("Огибающая: плавно появляется и исчезает")
    func envelope() {
        #expect(EffectEnvelope.alpha(time: 0, duration: 5) == 0)
        #expect(EffectEnvelope.alpha(time: 2.5, duration: 5) == 1)
        #expect(EffectEnvelope.alpha(time: 5, duration: 5) == 0)
    }
}

@Suite("Сдвиг интерфейса")
struct RevealTests {
    @Test("Параметры сдвига разбираются и ограничиваются")
    func revealClamp() throws {
        let json = #"""
        {"schemaVersion":1,"eggs":[{"id":"r","screen":"settings","trigger":{"type":"tapSequence","taps":99},
          "variants":[{"effect":{"reveal":{"direction":"left","openMs":100,"closeAtMs":99999,"closeMs":5000},
            "layers":[{"type":"particles","asset":"builtin:bubble"}]}}]}]}
        """#
        let egg = try #require(loadConfig(json).config?.eggs.first)
        #expect(egg.trigger.tap.taps == 15)
        let r = try #require(egg.variants[0].effect.reveal)
        #expect(r.direction == .left)
        #expect(r.open == 0.3)
        #expect(r.closeAt == 9)
        #expect(r.close == 1.5)
    }
}
