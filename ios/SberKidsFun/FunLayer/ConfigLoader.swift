import CryptoKit
import Foundation
import FunLayerCore

/// Откуда берётся конфиг.
enum ConfigSource: Equatable, Sendable {
    /// Копия, зашитая в сборку (работает без сети).
    case bundled(String)
    /// «Новый ключ в CMS» — здесь статический JSON на CDN.
    case remote(URL)

    var title: String {
        switch self {
        case .bundled(let name): return "Встроенный: \(name)"
        case .remote(let url): return url.absoluteString
        }
    }
}

/// Ресурсы эффектов: копия в сборке → кэш на устройстве → загрузка с CDN.
/// Каждый скачанный файл сверяется по sha256 — подменённый файл не используется.
@MainActor
final class AssetStore {
    private let fm = FileManager.default
    private let cacheDir: URL
    private var bundleHashes: [String: String] = [:]

    init() {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = base.appendingPathComponent("FunLayer/assets", isDirectory: true)
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Локальный файл ресурса или nil, если его ещё нужно скачать.
    func localURL(for asset: AssetRef) -> URL? {
        if let sha = asset.sha256 {
            let cached = cacheURL(asset)
            if fm.fileExists(atPath: cached.path) { return cached }
            if let b = bundleURL(asset), bundleHash(b) == sha { return b }
            return nil
        }
        return bundleURL(asset)
    }

    func localURL(forKey key: String, in config: FunConfig) -> URL? {
        guard let asset = config.assets[key] else { return nil }
        return localURL(for: asset)
    }

    /// Скачивает недостающие ресурсы. true — всё на месте, конфиг можно включать.
    func prefetch(_ config: FunConfig) async -> Bool {
        var ok = true
        for asset in config.assets.values where localURL(for: asset) == nil {
            guard let url = asset.url, url.scheme == "https" || url.isFileURL else { ok = false; continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 { ok = false; continue }
                if let sha = asset.sha256, Self.hex(SHA256.hash(data: data)) != sha {
                    ok = false; continue  // целостность не сошлась — файл не используем
                }
                try data.write(to: cacheURL(asset), options: .atomic)
            } catch {
                ok = false
            }
        }
        return ok
    }

    func clear() {
        try? fm.removeItem(at: cacheDir)
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private func cacheURL(_ asset: AssetRef) -> URL {
        let ext = (asset.fileName as NSString).pathExtension
        return cacheDir.appendingPathComponent("\(asset.sha256 ?? asset.key).\(ext)")
    }

    private func bundleURL(_ asset: AssetRef) -> URL? {
        let name = (asset.fileName as NSString).deletingPathExtension
        let ext = (asset.fileName as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext)
    }

    private func bundleHash(_ url: URL) -> String? {
        if let h = bundleHashes[url.path] { return h }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let h = Self.hex(SHA256.hash(data: data))
        bundleHashes[url.path] = h
        return h
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Загрузка и активация конфига. Принцип: новый конфиг включается только целиком —
/// когда он прошёл валидацию И все его ресурсы скачаны. Иначе работает предыдущий.
@MainActor
final class ConfigLoader {
    struct Loaded {
        var config: FunConfig?
        var source: ConfigSource
        var warnings: [String]
        var disabled = false
    }

    private let policy: ScreenPolicy
    let assets = AssetStore()
    private let defaults = UserDefaults.standard
    private let storeDir: URL

    private enum Key {
        static let source = "fun_layer.source"
        static let etag = "fun_layer.etag"
    }

    init(policy: ScreenPolicy) {
        self.policy = policy
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storeDir = base.appendingPathComponent("FunLayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
    }

    var savedSource: ConfigSource {
        get {
            guard let raw = defaults.string(forKey: Key.source) else { return .bundled("config") }
            if raw.hasPrefix("bundled:") { return .bundled(String(raw.dropFirst(8))) }
            if let url = URL(string: raw) { return .remote(url) }
            return .bundled("config")
        }
        set {
            switch newValue {
            case .bundled(let n): defaults.set("bundled:\(n)", forKey: Key.source)
            case .remote(let u): defaults.set(u.absoluteString, forKey: Key.source)
            }
        }
    }

    /// Быстрый синхронный старт: последний активный удалённый конфиг из кэша
    /// или встроенный. Сеть на старте не трогаем — запуск не замедляется.
    func loadOnLaunch() -> Loaded {
        if case .remote(let url) = savedSource, let data = try? Data(contentsOf: cachedConfigURL) {
            let r = ConfigValidator.decode(data, policy: policy, baseURL: url)
            if let c = r.config, c.assets.values.allSatisfy({ assets.localURL(for: $0) != nil }) {
                return Loaded(config: c, source: .remote(url), warnings: r.warnings)
            }
        }
        if case .bundled(let name) = savedSource {
            return loadBundled(name)
        }
        return loadBundled("config")
    }

    func loadBundled(_ name: String) -> Loaded {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return Loaded(config: nil, source: .bundled(name), warnings: ["Нет встроенного конфига \(name)"])
        }
        let r = ConfigValidator.decode(data, policy: policy, baseURL: nil)
        return Loaded(config: r.config, source: .bundled(name), warnings: r.warnings, disabled: r.disabledByConfig)
    }

    /// Загрузка с CDN (ETag → 304 не качаем повторно), валидация, докачка ресурсов, атомарная активация.
    func fetchRemote(_ url: URL) async -> Loaded? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        if let etag = defaults.string(forKey: Key.etag + url.absoluteString) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            var body = data
            if http?.statusCode == 304, let cached = try? Data(contentsOf: cachedConfigURL) {
                body = cached
            } else if let code = http?.statusCode, code != 200 {
                return Loaded(config: nil, source: .remote(url), warnings: ["CDN ответил \(code)"])
            }
            let r = ConfigValidator.decode(body, policy: policy, baseURL: url)
            guard let config = r.config else {
                // выключатель (enabled=false) — валидный ответ: слой гасится
                if r.disabledByConfig { try? body.write(to: cachedConfigURL, options: .atomic) }
                return Loaded(config: nil, source: .remote(url), warnings: r.warnings, disabled: r.disabledByConfig)
            }
            guard await assets.prefetch(config) else {
                return Loaded(config: nil, source: .remote(url), warnings: r.warnings + ["Не все ресурсы скачались — остаёмся на текущем конфиге"])
            }
            try? body.write(to: cachedConfigURL, options: .atomic)
            if let etag = http?.value(forHTTPHeaderField: "ETag") {
                defaults.set(etag, forKey: Key.etag + url.absoluteString)
            }
            return Loaded(config: config, source: .remote(url), warnings: r.warnings)
        } catch {
            return Loaded(config: nil, source: .remote(url), warnings: ["Сеть: \(error.localizedDescription)"])
        }
    }

    private var cachedConfigURL: URL { storeDir.appendingPathComponent("active-config.json") }
}
