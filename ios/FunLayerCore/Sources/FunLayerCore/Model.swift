import Foundation

// Проверенная модель конфига. Сюда попадают только валидные, уже ограниченные
// значения: код рендеринга не обязан ничего перепроверять.

public struct FunConfig: Sendable, Equatable {
    public var configId: String
    public var announcedTotal: Int
    public var foundSound: String?
    public var texts: FunTexts
    public var teaser: Teaser?
    public var eggs: [Egg]
    public var assets: [String: AssetRef]

    public func egg(id: String) -> Egg? { eggs.first { $0.id == id } }
}

public struct FunTexts: Sendable, Equatable {
    public var toastTitle = "Пасхалка найдена! {n} из {total}"
    public var toastSubtitle = "Нажми, чтобы узнать секрет"
    public var toastRepeatTitle = "Секретов найдено: {n} из {total}"
    public var sheetTitle = "Это пасхалка!"
    public var sheetIntro = "В СберKids спрятано {total} секретов. Исследуй приложение и найди их все!"
    public var nextHintTitle = "Где искать дальше?"
    public var moreHintButton = "Ещё подсказка"
    public var shareButton = "Похвастаться"
    public var closeButton = "Понятно"
    public var shareText = "У меня {n} из {total} секретов СберKids! Сможешь найти все?"
    public var lockedSlot = "?"
    public var allFoundTitle = "Все секреты найдены!"
    public var allFoundText = "Ты настоящий исследователь. Скоро здесь спрячутся новые пасхалки."
    public var comingSoonText = "Новые пасхалки уже прячутся. Загляни позже!"

    public init() {}
}

public struct Teaser: Sendable, Equatable {
    public var screen: String
    public var eggId: String
    public var delay: TimeInterval
    public var maxShows: Int
    public var text: String
}

public struct Egg: Sendable, Equatable, Identifiable {
    public var id: String
    public var order: Int
    public var title: String
    public var pictogram: String
    public var screen: String
    public var trigger: Trigger
    public var fallbackTrigger: Trigger?
    public var schedule: Schedule?
    public var cooldown: TimeInterval
    public var variants: [Variant]
    public var hint: Hint

    /// Триггеры, которые слушаются для этой пасхалки.
    public var triggerKinds: [TriggerKind] {
        [trigger.kind] + (fallbackTrigger.map { [$0.kind] } ?? [])
    }

    public func trigger(of kind: TriggerKind) -> Trigger? {
        if trigger.kind == kind { return trigger }
        if fallbackTrigger?.kind == kind { return fallbackTrigger }
        return nil
    }
}

public enum TriggerKind: String, Sendable, CaseIterable {
    case shake          // тряска (акселерометр)
    case pullHold       // потянуть список вниз и задержать
    case palm           // накрыть экран ладонью
    case faceDownFlip   // положить экраном вниз и перевернуть (запасной для palm)
}

public struct Trigger: Sendable, Equatable {
    public var kind: TriggerKind
    public var shake = ShakeParams()
    public var pull = PullHoldParams()
    public var palm = PalmParams()
    public var flip = FlipParams()
}

public struct ShakeParams: Sendable, Equatable {
    public var threshold: Double = 1.3   // g, линейное ускорение без гравитации
    public var peaks: Int = 3
    public var window: TimeInterval = 1.0
    public init() {}
}

public struct PullHoldParams: Sendable, Equatable {
    public var distance: Double = 90     // pt
    public var hold: TimeInterval = 1.0
    public init() {}
}

public struct PalmParams: Sendable, Equatable {
    public var minTouches: Int = 3
    public var minRadius: Double = 30    // pt, majorRadius одного касания
    public var hold: TimeInterval = 1.2
    public var maxMovement: Double = 70  // pt — больше значит свайп, а не ладонь
    public var maxHold: TimeInterval = 6 // дольше — телефон просто лежит
    public init() {}
}

public struct FlipParams: Sendable, Equatable {
    public var down: TimeInterval = 0.8
    public var maxDown: TimeInterval = 6
    public init() {}
}

public struct Schedule: Sendable, Equatable {
    public var from: DateComponents?
    public var to: DateComponents?
    public var months: Set<Int>?

    public func isActive(on date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        if let months, let m = day.month, !months.contains(m) { return false }
        if let from, Schedule.compare(day, from) < 0 { return false }
        if let to, Schedule.compare(day, to) > 0 { return false }
        return true
    }

    static func compare(_ a: DateComponents, _ b: DateComponents) -> Int {
        let ka = (a.year ?? 0) * 10_000 + (a.month ?? 0) * 100 + (a.day ?? 0)
        let kb = (b.year ?? 0) * 10_000 + (b.month ?? 0) * 100 + (b.day ?? 0)
        return ka == kb ? 0 : (ka < kb ? -1 : 1)
    }
}

public struct Hint: Sendable, Equatable {
    public var riddle: String
    public var help: String
    public var pictograms: [String]
}

public struct Variant: Sendable, Equatable {
    public var id: String
    public var weight: Double
    public var effect: Effect
}

public struct Effect: Sendable, Equatable {
    public var duration: TimeInterval
    public var dimColor: RGBA
    public var dimOpacity: Double
    public var layers: [EffectLayer]
    public var sound: String?
    public var interactSound: String?
    public var haptic: Haptic
}

public enum Haptic: String, Sendable {
    case none, light, medium, success
}

public enum EffectLayer: Sendable, Equatable {
    case particles(ParticleSpec)
    case lottie(LottieSpec)
    case fog(FogSpec)
    case ghosts(GhostSpec)
}

public struct ParticleSpec: Sendable, Equatable {
    public enum Direction: String, Sendable { case up, down }
    public var asset: String
    public var count: Int = 22
    public var sizeMin: Double = 34
    public var sizeMax: Double = 86
    public var speedMin: Double = 70
    public var speedMax: Double = 150
    public var direction: Direction = .up
    public var wobble: Double = 18
    public var wobbleSpeed: Double = 1.6
    public var spin: Double = 0.4
    public var spawn: TimeInterval = 2.5
    public var tapToPop = true
    public var opacity: Double = 1

    public init(asset: String) { self.asset = asset }
}

public struct LottieSpec: Sendable, Equatable {
    public enum Placement: String, Sendable { case fullscreen, bottom }
    public var asset: String
    public var speed: Double = 1
    public var placement: Placement = .fullscreen
}

public struct FogSpec: Sendable, Equatable {
    public var asset: String
    public var colors: [RGBA]
    public var opacity: Double = 0.55
    public var drift: Double = 14   // pt/s
    public var stars: Int = 24
}

public struct GhostSpec: Sendable, Equatable {
    public var count: Int = 4
    public var sizeMin: Double = 70
    public var sizeMax: Double = 110
    public var palette: [RGBA]
    public var tapToVanish = true
    public var followFinger = true
}

public struct AssetRef: Sendable, Equatable {
    public var key: String
    /// Путь из конфига как есть — по имени файла ищется копия, зашитая в сборку.
    public var path: String
    /// Абсолютный https-адрес на CDN; nil — ресурс только из сборки.
    public var url: URL?
    public var sha256: String?
    public var bytes: Int?

    public var fileName: String { (path as NSString).lastPathComponent }
}

/// Цвет без зависимостей от UIKit/Android: «#RRGGBB» или «#RRGGBBAA».
public struct RGBA: Sendable, Equatable {
    public var r: Double, g: Double, b: Double, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            self.init(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255,
                      b: Double(v & 0xFF) / 255)
        } else {
            self.init(r: Double((v >> 24) & 0xFF) / 255, g: Double((v >> 16) & 0xFF) / 255,
                      b: Double((v >> 8) & 0xFF) / 255, a: Double(v & 0xFF) / 255)
        }
    }
}
