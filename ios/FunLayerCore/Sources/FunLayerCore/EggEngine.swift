import Foundation

/// Решение «играть эффект».
public struct PlayDecision: Sendable, Equatable {
    public var egg: Egg
    public var variant: Variant
    public var trigger: TriggerKind
    public var isFirstFind: Bool
    public var foundCount: Int
    public var total: Int
}

/// Что показать в шторке после находки.
public struct HintCard: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case next(Egg), comingSoon, allFound }
    public var kind: Kind
    public var level: Int
}

/// Мозг слоя приколов: какие датчики слушать на экране, можно ли сейчас играть,
/// какой вариант выбрать, что записать в прогресс, какую подсказку показать.
public final class EggEngine {
    public private(set) var config: FunConfig
    public let progress: ProgressStore
    private let rng: RandomSource
    private var lastPlayed: [String: Date] = [:]
    public private(set) var isPlaying = false

    public init(config: FunConfig, progress: ProgressStore, rng: RandomSource = SystemRandom()) {
        self.config = config
        self.progress = progress
        self.rng = rng
    }

    public func update(config: FunConfig) { self.config = config }

    public var total: Int { config.announcedTotal }
    public var foundCount: Int { config.eggs.filter { progress.isFound($0.id) }.count }

    /// Пасхалки, доступные на экране прямо сейчас (с учётом расписания).
    public func eggs(on screen: String, now: Date) -> [Egg] {
        config.eggs.filter { $0.screen == screen && ($0.schedule?.isActive(on: now) ?? true) }
    }

    /// Какие детекторы включать на экране. Пустое множество — датчики выключены целиком.
    public func activeTriggers(on screen: String, now: Date) -> [TriggerKind: Trigger] {
        var result: [TriggerKind: Trigger] = [:]
        for egg in eggs(on: screen, now: now) {
            result[egg.trigger.kind] = result[egg.trigger.kind] ?? egg.trigger
            if let f = egg.fallbackTrigger { result[f.kind] = result[f.kind] ?? f }
        }
        return result
    }

    public func handle(_ kind: TriggerKind, on screen: String, now: Date) -> PlayDecision? {
        guard !isPlaying else { return nil }
        guard let egg = eggs(on: screen, now: now).first(where: { $0.triggerKinds.contains(kind) }) else { return nil }
        if let last = lastPlayed[egg.id], now.timeIntervalSince(last) < egg.cooldown { return nil }
        return play(egg, trigger: kind, now: now)
    }

    /// Ручной запуск (меню отладки / тизер).
    public func force(eggId: String, now: Date) -> PlayDecision? {
        guard !isPlaying, let egg = config.egg(id: eggId) else { return nil }
        return play(egg, trigger: egg.trigger.kind, now: now)
    }

    private func play(_ egg: Egg, trigger: TriggerKind, now: Date) -> PlayDecision {
        let variant = WeightedPicker.pick(egg.variants.map { ($0, $0.weight) }, rng: rng) ?? egg.variants[0]
        let first = progress.markFound(egg.id, at: now)
        lastPlayed[egg.id] = now
        isPlaying = true
        return PlayDecision(egg: egg, variant: variant, trigger: trigger, isFirstFind: first,
                            foundCount: foundCount, total: total)
    }

    public func effectFinished(now: Date) {
        isPlaying = false
    }

    /// Прервать эффект (ушли на экран с деньгами, приложение свернули).
    public func cancelEffect() { isPlaying = false }

    /// Подсказка к первой ненайденной пасхалке по порядку.
    public func nextHint(now: Date) -> HintCard {
        if let next = config.eggs.first(where: { !progress.isFound($0.id) }) {
            return HintCard(kind: .next(next), level: progress.hintLevel(for: next.id))
        }
        return HintCard(kind: foundCount < total ? .comingSoon : .allFound, level: 0)
    }

    public func revealMoreHint(for eggId: String) { progress.revealMoreHint(for: eggId) }

    // MARK: Тизер

    public func shouldShowTeaser(on screen: String) -> Teaser? {
        guard let t = config.teaser, t.screen == screen,
              !progress.isFound(t.eggId), progress.state.teaserShows < t.maxShows else { return nil }
        return t
    }

    public func teaserShown() { progress.incrementTeaser() }
}

public enum WeightedPicker {
    /// Выбор по весам. Вероятность варианта = weight / сумма весов.
    /// Ребёнок ничего не тратит и ничем не рискует — это не лотерея, а разнообразие.
    public static func pick<T>(_ items: [(T, Double)], rng: RandomSource) -> T? {
        let total = items.reduce(0) { $0 + max(0, $1.1) }
        guard total > 0 else { return items.first?.0 }
        var r = rng.next() * total
        for (item, w) in items {
            r -= max(0, w)
            if r < 0 { return item }
        }
        return items.last?.0
    }
}
