import Foundation

/// Абстракция над хранилищем: iOS — UserDefaults, Android — SharedPreferences/DataStore.
public protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

public final class InMemoryStore: KeyValueStore {
    private var storage: [String: Data] = [:]
    public init() {}
    public func data(forKey key: String) -> Data? { storage[key] }
    public func set(_ data: Data?, forKey key: String) { storage[key] = data }
}

/// Прогресс живёт только на устройстве. Никаких идентификаторов, сумм и имён —
/// только какие пасхалки найдены и сколько раз показан тизер.
public final class ProgressStore {
    public struct State: Codable, Equatable, Sendable {
        public var found: [String] = []            // id в порядке нахождения
        public var foundAt: [String: Date] = [:]
        public var teaserShows = 0
        public var hintLevel: [String: Int] = [:]  // 0 — загадка, 1 — прямая подсказка
        public var plays: [String: Int] = [:]      // сколько раз запускали (для повторяемости)
    }

    public static let storageKey = "fun_layer.progress.v1"
    private let store: KeyValueStore
    public private(set) var state: State

    public init(store: KeyValueStore) {
        self.store = store
        if let data = store.data(forKey: Self.storageKey),
           let s = try? JSONDecoder().decode(State.self, from: data) {
            state = s
        } else {
            state = State()
        }
    }

    public func isFound(_ id: String) -> Bool { state.found.contains(id) }

    /// - Returns: true, если пасхалка найдена впервые.
    @discardableResult
    public func markFound(_ id: String, at date: Date) -> Bool {
        state.plays[id, default: 0] += 1
        defer { save() }
        guard !state.found.contains(id) else { return false }
        state.found.append(id)
        state.foundAt[id] = date
        return true
    }

    public func incrementTeaser() { state.teaserShows += 1; save() }

    public func hintLevel(for id: String) -> Int { state.hintLevel[id] ?? 0 }

    public func revealMoreHint(for id: String) { state.hintLevel[id] = 1; save() }

    public func reset() { state = State(); save() }

    private func save() {
        store.set(try? JSONEncoder().encode(state), forKey: Self.storageKey)
    }
}

/// Источник случайности. В тестах — детерминированный.
public protocol RandomSource: AnyObject {
    /// Равномерно в [0, 1).
    func next() -> Double
}

extension RandomSource {
    public func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
}

public final class SystemRandom: RandomSource {
    public init() {}
    public func next() -> Double { Double.random(in: 0..<1) }
}

/// SplitMix64 — простой и одинаковый на всех платформах.
public final class SeededRandom: RandomSource {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

public enum Template {
    /// «Найдено {n} из {total}» → «Найдено 1 из 5».
    public static func render(_ s: String, _ values: [String: String]) -> String {
        var out = s
        for (k, v) in values { out = out.replacingOccurrences(of: "{\(k)}", with: v) }
        return out
    }
}
