import FunLayerCore
import Lottie
import SwiftUI
import UIKit

/// Хранилище прогресса на устройстве.
final class UserDefaultsStore: KeyValueStore {
    func data(forKey key: String) -> Data? { UserDefaults.standard.data(forKey: key) }
    func set(_ data: Data?, forKey key: String) { UserDefaults.standard.set(data, forKey: key) }
}

struct ToastModel: Equatable {
    let id = UUID()
    let eggId: String
    let title: String
    let subtitle: String
    let isFirstFind: Bool
}

struct SheetModel: Equatable {
    let id = UUID()
    let eggId: String
}

struct TeaserRun: Equatable {
    let id = UUID()
    let start: CFTimeInterval
    let text: String
    var poppedAt: CFTimeInterval?
    var popPoint: CGPoint?
}

/// Точка входа слоя приколов. Интеграция в приложение — три вызова:
/// `install(on:)` при старте, `setScreen(_:)` при смене экрана,
/// `reportPull(distance:)` из списков с pull-to-refresh. Больше приложение ничего не знает.
@MainActor
final class FunLayer: ObservableObject {
    static let shared = FunLayer()

    /// Экраны приложения. Денежные помечены в ScreenPolicy.sensitive и закрыты для приколов в коде.
    static let screens: Set<String> = ["main", "piggy", "tasks", "content", "profile", "transfer", "top_up", "debug",
                                       "history", "design", "content_detail", "tasks_detail", "piggy_detail", "settings"]
    let policy = ScreenPolicy(knownScreens: FunLayer.screens)

    @Published private(set) var config: FunConfig?
    @Published private(set) var source: ConfigSource = .bundled("config")
    @Published private(set) var warnings: [String] = []
    @Published private(set) var effect: EffectRuntime?
    @Published private(set) var toast: ToastModel?
    @Published private(set) var sheet: SheetModel?
    @Published private(set) var teaser: TeaserRun?
    @Published private(set) var palmProgress: Double = 0
    @Published private(set) var palmArmed = false
    @Published private(set) var pullFraction: Double = 0
    @Published private(set) var pullHold: Double = 0
    @Published private(set) var currentScreen = "main"
    @Published private(set) var isLoadingRemote = false
    @Published var calibration: (touches: Int, radius: Double) = (0, 0)
    @Published private(set) var progressVersion = 0
    /// Подсказка во время серии тапов: «Осталось 3…»
    @Published private(set) var tapHint: String?

    private(set) var engine: EggEngine?
    let loader: ConfigLoader
    private let progress = ProgressStore(store: UserDefaultsStore())
    let sounds = SoundPlayer()
    private let motion = MotionSensor()
    private let palm = PalmGestureRecognizer()
    private let pull = PullHoldDetector()
    private var pullEnabled = false
    private let tapSeq = TapSequenceDetector()
    private let strokes = StrokeRecognizer()
    private let spiral = SpiralDetector()
    private var pendingPortal: [CGPoint]?
    /// Светящаяся змейка за пальцем (только когда штрих уже похож на спираль).
    private(set) var trail: [StrokePoint] = []
    @Published private(set) var trailActive = false
    private var tapEnabled = false
    private var tapHintTask: Task<Void, Never>?
    private weak var appWindow: UIWindow?
    private var lastPullDistance = 0.0
    private var maxPullSeen = 0.0
    private var pullTicker: Task<Void, Never>?
    private var overlay: OverlayWindow?
    private var endTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var teaserTask: Task<Void, Never>?
    private var isActive = true
    var calibrating = false { didSet { updateSensors() } }
    private var palmEggActive = false
    private var shakeEggActive = false
    private var lastLoggedTouches = 0
    var toastFrame: CGRect = .zero

    private init() {
        loader = ConfigLoader(policy: ScreenPolicy(knownScreens: FunLayer.screens))
    }

    // MARK: - Установка

    func install(on window: UIWindow) {
        guard overlay == nil, let scene = window.windowScene else { return }
        appWindow = window

        window.addGestureRecognizer(palm)
        window.addGestureRecognizer(strokes)
        strokes.isEnabled = false
        strokes.onStroke = { [weak self] pts in self?.strokeFinished(pts) }
        strokes.onMove = { [weak self] pts in self?.strokeMoved(pts) }
        palm.isEnabled = false
        palm.onProgress = { [weak self] p in self?.palmChanged(p) }
        palm.onArmed = { [weak self] in self?.palmArmedNow() }
        palm.onTriggered = { [weak self] in self?.palmTriggered() }
        palm.onCancelled = { [weak self] in
            self?.log("palm cancelled")
            self?.palmReset()
        }
        palm.onSample = { [weak self] count, radius, point in
            guard let self else { return }
            if self.calibrating { self.calibration = (count, radius) }
            if self.palmEggActive, count > 0, count != self.lastLoggedTouches {
                self.log("touches=\(count) maxRadius=\(Int(radius))")
            }
            self.lastLoggedTouches = count
            self.effect?.lookTarget = point
        }

        motion.onShake = { [weak self] in self?.trigger(.shake) }
        motion.onFlip = { [weak self] in self?.trigger(.faceDownFlip) }
        motion.onFlipArmed = { [weak self] in self?.flipArmed() }

        let o = OverlayWindow(windowScene: scene)
        let host = UIHostingController(rootView: OverlayRootView().environmentObject(self))
        host.view.backgroundColor = .clear
        o.rootViewController = host
        o.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        o.backgroundColor = .clear
        o.isHidden = false
        overlay = o

        apply(loader.loadOnLaunch())
        log("installed: config=\(config?.configId ?? "nil") eggs=\(config?.eggs.count ?? 0) window=\(o.bounds.size) warnings=\(warnings)")
        handleLaunchArguments()

        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appActive(false) }
        }
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appActive(true) }
        }

        // Обновление с CDN — после того как главный экран уже показан: запуск не замедляем.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if case .remote(let url) = self?.loader.savedSource { await self?.loadRemote(url) }
        }
    }

    /// Аргументы запуска для автоматической проверки на устройстве:
    /// `-funReset` — сбросить прогресс, `-funForce <id>` — запустить пасхалку через 1,5 с,
    /// `-funPreset <name>` — встроенный конфиг.
    private func handleLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ key: String) -> String? {
            args.firstIndex(of: key).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }
        if args.contains("-funReset") { resetProgress() }
        if let preset = value("-funPreset") { useBundled(preset) }
        if let id = value("-funForce") {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.forcePlay(id)
            }
        }
    }

    private var traceStart: CFTimeInterval = 0

    func log(_ s: String) {
        #if DEBUG
        let dt = traceStart > 0 ? String(format: " +%.0f ms", (CACurrentMediaTime() - traceStart) * 1000) : ""
        print("[FunLayer] \(s)\(dt)")
        #endif
    }

    var overlaySize: CGSize { overlay?.bounds.size ?? UIScreen.main.bounds.size }
    var safeInsets: UIEdgeInsets { overlay?.safeAreaInsets ?? .zero }

    // MARK: - Конфиг

    private func apply(_ loaded: ConfigLoader.Loaded) {
        cancelEffect()
        source = loaded.source
        warnings = loaded.warnings
        config = loaded.config
        if let c = loaded.config {
            if let engine { engine.update(config: c) } else { engine = EggEngine(config: c, progress: progress) }
        } else {
            engine = nil
        }
        toast = nil
        sheet = nil
        teaser = nil
        updateSensors()
        scheduleTeaser()
    }

    func useBundled(_ name: String) {
        loader.savedSource = .bundled(name)
        apply(loader.loadBundled(name))
    }

    func loadRemote(_ url: URL) async {
        loader.savedSource = .remote(url)
        isLoadingRemote = true
        defer { isLoadingRemote = false }
        guard let loaded = await loader.fetchRemote(url) else { return }
        if loaded.config != nil || loaded.disabled {
            apply(loaded)
        } else {
            warnings = loaded.warnings  // ошибка сети/валидации — остаёмся на прежнем конфиге
        }
    }

    func resetProgress() {
        progress.reset()
        progressVersion += 1
        scheduleTeaser()
    }

    // MARK: - Экраны и датчики

    func setScreen(_ id: String) {
        guard id != currentScreen else { return }
        currentScreen = id
        pull.reset()
        pullFraction = 0
        pullHold = 0
        palmReset()
        if ScreenPolicy.sensitive.contains(id) {
            // поверх денег ничего не показываем — ни эффектов, ни тостов, ни шторки
            cancelEffect()
            toast = nil
            sheet = nil
        }
        teaser = nil
        updateSensors()
        scheduleTeaser()
        prewarmLottie()
    }

    /// На экране с персонажем заранее разбираем его Lottie в кэш — запуск без задержки.
    private func prewarmLottie() {
        guard let engine, let config else { return }
        for egg in engine.eggs(on: currentScreen, now: Date()) {
            for variant in egg.variants {
                for case .lottie(let spec) in variant.effect.layers {
                    if let url = loader.assets.localURL(forKey: spec.asset, in: config) {
                        _ = LottieAnimation.filepath(url.path, animationCache: DefaultAnimationCache.sharedCache)
                    }
                }
            }
        }
    }

    private func appActive(_ active: Bool) {
        isActive = active
        if !active {
            cancelEffect()
            teaser = nil
        }
        updateSensors()
    }

    private func updateSensors() {
        guard let engine, isActive, effect == nil, sheet == nil, policy.allows(currentScreen) else {
            motion.configure(shake: nil, flip: nil)
            palm.isEnabled = calibrating || (effect != nil && palm.isEnabled)  // во время призраков глаза следят за пальцем
            palmEggActive = false
            shakeEggActive = false
            pullEnabled = false
            tapEnabled = false
            strokes.isEnabled = false
            return
        }
        let t = engine.activeTriggers(on: currentScreen, now: Date())
        motion.configure(shake: t[.shake], flip: t[.faceDownFlip])
        shakeEggActive = t[.shake] != nil
        if let p = t[.palm] { palm.detector.params = p.palm }
        palmEggActive = t[.palm] != nil
        palm.isEnabled = palmEggActive || calibrating
        if let p = t[.pullHold] { pull.params = p.pull }
        pullEnabled = t[.pullHold] != nil
        if let p = t[.tapSequence] { tapSeq.params = p.tap }
        tapEnabled = t[.tapSequence] != nil
        if let p = t[.spiral] { spiral.params = p.spiral }
        strokes.isEnabled = t[.spiral] != nil
    }

    /// Приложение сообщает о нажатии на элемент (одна строка в обработчике нажатия).
    func reportTap(_ target: String) {
        guard tapEnabled, effect == nil, sheet == nil, let config else { return }
        switch tapSeq.feed(target: target, time: CACurrentMediaTime()) {
        case .progress(let done, let left):
            Haptics.tick()
            if done >= 3 {
                tapHint = Template.render(config.texts.tapProgress, ["left": "\(left)"])
                tapHintTask?.cancel()
                tapHintTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 1_100_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.2)) { self?.tapHint = nil }
                }
            }
        case .triggered:
            tapHintTask?.cancel()
            tapHint = nil
            trigger(.tapSequence)
        case .none:
            break
        }
    }

    /// Палец ещё рисует: если штрих похож на спираль — показываем змейку; набрал витки — сразу запускаем.
    private func strokeMoved(_ pts: [StrokePoint]) {
        guard effect == nil, sheet == nil else { return }
        if trailActive || spiral.looksLikeSpiral(pts) {
            trail = pts
            if !trailActive { trailActive = true }
        }
        guard trailActive, case .recognized(let turns) = spiral.evaluate(pts) else { return }
        log(String(format: "spiral recognized on the fly, %.2f turns", turns))
        strokes.consumed = true
        trailActive = false
        trail = []
        pendingPortal = pts.map { CGPoint(x: $0.x, y: $0.y) }
        trigger(.spiral)
        pendingPortal = nil
    }

    /// Палец поднят: последняя проверка и гасим змейку.
    private func strokeFinished(_ pts: [StrokePoint]) {
        trailActive = false
        trail = []
        guard effect == nil, sheet == nil else { return }
        switch spiral.evaluate(pts) {
        case .recognized(let turns):
            log(String(format: "spiral recognized, %.2f turns", turns))
            pendingPortal = pts.map { CGPoint(x: $0.x, y: $0.y) }
            trigger(.spiral)
            pendingPortal = nil
        case .rejected(let why):
            if pts.count > 40 { log("stroke rejected: \(why)") }
        }
    }

    /// Снимок интерфейса приложения — он «отъезжает», открывая сцену под собой.
    private func snapshotApp() -> UIImage? {
        guard let w = appWindow else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = w.screen.scale
        return UIGraphicsImageRenderer(bounds: w.bounds, format: format).image { _ in
            w.drawHierarchy(in: w.bounds, afterScreenUpdates: false)
        }
    }

    /// Системный жест «встряхнуть» (UIKit). Дублирует CoreMotion: работает и в симуляторе
    /// (Device → Shake), и как страховка на устройстве. Двойного запуска нет — движок блокирует.
    func systemShake() {
        guard shakeEggActive else { return }
        trigger(.shake)
    }

    func reportPull(distance: Double) {
        guard pullEnabled, effect == nil else { return }
        if distance > maxPullSeen { maxPullSeen = distance }
        if distance < 5, maxPullSeen > 20 {
            log("pull released, max \(Int(maxPullSeen)) pt")
            maxPullSeen = 0
        }
        lastPullDistance = distance
        feedPull()
        // Пока ребёнок держит ленту неподвижно, список не присылает новых событий —
        // поэтому, пока лента перетянута, время удержания досчитываем сами.
        if distance >= pull.params.distance * 0.5, pullTicker == nil {
            pullTicker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    guard let self, self.pullEnabled, self.effect == nil,
                          self.lastPullDistance >= self.pull.params.distance * 0.25 else { break }
                    self.feedPull()
                }
                self?.pullTicker = nil
            }
        }
    }

    private func feedPull() {
        let distance = lastPullDistance
        let out = pull.feed(distance: distance, time: CACurrentMediaTime())
        let fraction = pull.pullFraction(distance: distance)
        if abs(fraction - pullFraction) > 0.01 || fraction == 0 { pullFraction = fraction }
        switch out {
        case .progress(let p):
            pullHold = p
        case .triggered:
            pullHold = 0
            pullFraction = 0
            log("pullHold triggered at \(Int(distance)) pt")
            NotificationCenter.default.post(name: .funLayerReleasePull, object: nil)
            lastPullDistance = 0
            trigger(.pullHold)
        case .idle:
            pullHold = 0
        }
    }

    private var palmTicker: Task<Void, Never>?

    private func palmChanged(_ p: Double) {
        guard palmEggActive, effect == nil, sheet == nil else { return }
        palmProgress = max(0.02, p)
        if palmTicker == nil {
            palmTicker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 16_000_000)
                    guard let self, self.palmProgress > 0 else { break }
                    self.palm.tick()
                }
                self?.palmTicker = nil
            }
        }
    }

    private func palmArmedNow() {
        guard palmEggActive, effect == nil, sheet == nil else { return }
        log("palm armed")
        palmProgress = 1
        palmArmed = true
        Haptics.play(.medium)
    }

    /// Телефон лежит экраном вниз: тихое «ууу» и лёгкая вибрация — призраки уже рядом.
    private func flipArmed() {
        guard let engine, let config, effect == nil, sheet == nil else { return }
        guard let egg = engine.eggs(on: currentScreen, now: Date()).first(where: { $0.triggerKinds.contains(.faceDownFlip) }),
              let sound = egg.variants.first?.effect.sound else { return }
        log("flip armed")
        Haptics.play(.light)
        sounds.play(loader.assets.localURL(forKey: sound, in: config), volume: 0.35)
    }

    private func palmTriggered() {
        let armed = palmArmed
        palmReset()
        if armed { trigger(.palm) }
    }

    private func palmReset() {
        palmTicker?.cancel()
        palmTicker = nil
        guard palmProgress > 0 || palmArmed else { return }
        withAnimation(.easeOut(duration: 0.35)) {
            palmProgress = 0
            palmArmed = false
        }
    }

    // MARK: - Эффект

    func trigger(_ kind: TriggerKind) {
        guard let engine, effect == nil, sheet == nil, isActive else { return }
        guard let d = engine.handle(kind, on: currentScreen, now: Date()) else { return }
        start(d)
    }

    /// Ручной запуск из меню отладки.
    func forcePlay(_ eggId: String) {
        guard let engine, effect == nil else { return }
        sheet = nil
        guard let d = engine.force(eggId: eggId, now: Date()) else { return }
        start(d)
    }

    private func start(_ d: PlayDecision) {
        guard let config else { return }
        traceStart = CACurrentMediaTime()
        log("play \(d.egg.id)/\(d.variant.id) first=\(d.isFirstFind) \(d.foundCount)/\(d.total)")
        toast = nil
        teaser = nil
        teaserTask?.cancel()
        let runtime = EffectRuntime(decision: d, size: overlaySize, config: config, assets: loader.assets)
        if runtime.reveal != nil { runtime.revealSnapshot = snapshotApp() }
        if let path = pendingPortal, !path.isEmpty {
            runtime.portalPath = path
            let xs = path.map(\.x), ys = path.map(\.y)
            runtime.portalCenter = CGPoint(x: (xs.max()! + xs.min()!) / 2, y: (ys.max()! + ys.min()!) / 2)
        }
        log("runtime ready")
        withAnimation(.easeOut(duration: 0.2)) { effect = runtime }
        updateSensors()
        if d.trigger == .palm { palm.isEnabled = true }
        Haptics.play(d.variant.effect.haptic)
        endTask?.cancel()
        if let reveal = runtime.reveal {
            // Сценарий сдвига: вибрации в такт механике, удар при возврате, конец — по времени сцены
            endTask = Task { [weak self] in
                var fired = Set<Int>()
                while !Task.isCancelled, let self, let effect = self.effect, effect.id == runtime.id {
                    let t = runtime.elapsed
                    func once(_ id: Int, _ at: Double, _ action: () -> Void) {
                        if t >= at, !fired.contains(id) { fired.insert(id); action() }
                    }
                    once(1, 0.16) { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                    once(2, 0.32) { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                    once(3, reveal.open) { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
                    once(4, runtime.revealCloseAt + reveal.close) {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                    if t >= runtime.revealEnd {
                        self.showToast(for: d)
                        self.finishEffect()
                        return
                    }
                    try? await Task.sleep(nanoseconds: 16_000_000)
                }
            }
            return
        }
        if runtime.hasLottie {
            // Персонаж: звук стартует вместе с анимацией (lottieStarted), конец — по её завершению
            // (lottieFinished). Таймер — только страховка, если анимация не сообщит о конце.
            let safety = runtime.duration + 2
            endTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(safety * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.showToast(for: d)
                self?.finishEffect()
            }
            return
        }
        if let s = d.variant.effect.sound { sounds.play(loader.assets.localURL(forKey: s, in: config)) }
        let duration = runtime.duration
        endTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((duration - 0.45) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.showToast(for: d)
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            self?.finishEffect()
        }
    }

    func lottieStarted(_ id: UUID) {
        guard let effect, effect.id == id, let config else { return }
        log("lottie started")
        if let s = effect.decision.variant.effect.sound { sounds.play(loader.assets.localURL(forKey: s, in: config)) }
    }

    func lottieFinished(_ id: UUID) {
        guard let effect, effect.id == id, effect.reveal == nil else { return }
        log("lottie finished")
        endTask?.cancel()
        showToast(for: effect.decision)
        finishEffect()
    }

    private func finishEffect() {
        effect = nil
        engine?.effectFinished(now: Date())
        updateSensors()
    }

    func cancelEffect() {
        endTask?.cancel()
        if effect != nil {
            effect = nil
            engine?.cancelEffect()
            sounds.stopAll()
        }
    }

    func tapEffect(at point: CGPoint) {
        guard let effect, let config else { return }
        if let reveal = effect.reveal {
            let t = effect.elapsed
            if t > reveal.open * 0.6, t < effect.revealCloseAt - 0.05 {
                effect.revealCloseAt = t
                sounds.stopAll()
                if let s = reveal.closeAt > 0 ? effect.decision.variant.effect.interactSound : nil {
                    sounds.play(loader.assets.localURL(forKey: s, in: config))
                }
            }
            return
        }
        if effect.tap(at: point) {
            Haptics.tick()
            if let s = effect.decision.variant.effect.interactSound {
                // призраки: узкий разброс, чтобы «у-у-у» не превращалось в писк
                let ghostly = effect.layers.contains { if case .ghosts = $0 { return true } else { return false } }
                sounds.playVaried(loader.assets.localURL(forKey: s, in: config), volume: ghostly ? 0.85 : 0.7,
                                  rates: ghostly ? 0.92...1.04 : 0.82...1.25)
            }
        }
    }

    // MARK: - Тост и шторка

    private func showToast(for d: PlayDecision) {
        guard let config, !ScreenPolicy.sensitive.contains(currentScreen) else { return }
        let values = ["n": "\(d.foundCount)", "total": "\(d.total)"]
        let t = config.texts
        let model = ToastModel(
            eggId: d.egg.id,
            title: Template.render(d.isFirstFind ? t.toastTitle : t.toastRepeatTitle, values),
            subtitle: t.toastSubtitle,
            isFirstFind: d.isFirstFind
        )
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { toast = model }
        if d.isFirstFind {
            Haptics.play(.success)
            if let s = config.foundSound { sounds.play(loader.assets.localURL(forKey: s, in: config), volume: 0.7) }
        }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { self?.toast = nil }
        }
    }

    func openSheet(from toast: ToastModel) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { self.toast = nil }
        cancelEffect()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { sheet = SheetModel(eggId: toast.eggId) }
        updateSensors()
    }

    func closeSheet() {
        withAnimation(.easeInOut(duration: 0.25)) { sheet = nil }
        updateSensors()
    }

    func dismissToast() {
        withAnimation(.easeIn(duration: 0.2)) { toast = nil }
    }

    func revealMoreHint(_ eggId: String) {
        engine?.revealMoreHint(for: eggId)
        progressVersion += 1
    }

    func share() {
        guard let engine, let config, let root = overlay?.rootViewController else { return }
        let found = config.eggs.filter { engine.progress.isFound($0.id) }
        let text = Template.render(config.texts.shareText, ["n": "\(found.count)", "total": "\(engine.total)"])
        let image = ShareCard.render(found: found, total: engine.total, eggs: config.eggs, text: text)
        let vc = UIActivityViewController(activityItems: [image, text], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = root.view
        root.present(vc, animated: true)
    }

    // MARK: - Тизер для самой первой пасхалки

    private func scheduleTeaser() {
        teaserTask?.cancel()
        guard let engine, let t = engine.shouldShowTeaser(on: currentScreen) else {
            log("teaser skipped on \(currentScreen)")
            return
        }
        let screen = currentScreen
        teaserTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(t.delay * 1_000_000_000))
            guard let self, !Task.isCancelled, self.currentScreen == screen,
                  self.effect == nil, self.sheet == nil, self.isActive else { return }
            self.engine?.teaserShown()
            self.log("teaser shown")
            self.teaser = TeaserRun(start: CACurrentMediaTime(), text: t.text)
            try? await Task.sleep(nanoseconds: 4_600_000_000)
            guard !Task.isCancelled, self.teaser?.poppedAt == nil else { return }
            self.teaser = nil
        }
    }

    /// Траектория пузырька-тизера (нужна и для отрисовки, и для попадания пальцем).
    func teaserPosition(at time: CFTimeInterval) -> CGPoint? {
        guard let teaser, teaser.poppedAt == nil else { return nil }
        let t = time - teaser.start
        let s = overlaySize
        return CGPoint(x: s.width * 0.74 + 14 * sin(t * 1.7),
                       y: s.height * 0.36 - t * 34)
    }

    func popTeaser() {
        guard var t = teaser, t.poppedAt == nil else { return }
        let now = CACurrentMediaTime()
        t.popPoint = teaserPosition(at: now)
        t.poppedAt = now
        teaser = t
        Haptics.tick()
        if let config, let url = loader.assets.localURL(forKey: "pop", in: config) { sounds.play(url) }
        teaserTask?.cancel()
        teaserTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { self?.teaser = nil }
        }
    }

    // MARK: - Попадание касаний в слой

    /// Окно-оверлей забирает касание, только если палец попал в интерактивный элемент.
    /// Всё остальное проходит насквозь в приложение.
    func wantsTouch(at point: CGPoint) -> Bool {
        if sheet != nil { return true }
        if effect?.reveal != nil { return true }   // сцена на весь экран: тап закрывает её досрочно
        if toast != nil, toastFrame.insetBy(dx: -6, dy: -6).contains(point) { return true }
        if let p = teaserPosition(at: CACurrentMediaTime()), hypot(p.x - point.x, p.y - point.y) < 34 { return true }
        if let effect, effect.hit(at: point) { return true }
        return false
    }
}
