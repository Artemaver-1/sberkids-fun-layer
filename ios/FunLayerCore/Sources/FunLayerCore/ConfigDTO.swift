import Foundation

// «Сырые» структуры JSON-конфига, как он лежит в CMS / на CDN.
// Все поля опциональны: отсутствующее поле получает значение по умолчанию
// на этапе валидации (ConfigValidator), неизвестные поля игнорируются.
// Так старое приложение спокойно читает новый конфиг, и наоборот.

public struct ConfigDTO: Codable, Sendable {
    public var schemaVersion: Int?
    public var configId: String?
    public var enabled: Bool?
    public var announcedTotal: Int?
    public var foundSound: String?
    public var texts: TextsDTO?
    public var teaser: TeaserDTO?
    public var eggs: [EggDTO]?
    public var assets: [String: AssetDTO]?
}

public struct TextsDTO: Codable, Sendable {
    public var toastTitle: String?
    public var toastSubtitle: String?
    public var toastRepeatTitle: String?
    public var sheetTitle: String?
    public var sheetIntro: String?
    public var nextHintTitle: String?
    public var moreHintButton: String?
    public var shareButton: String?
    public var closeButton: String?
    public var shareText: String?
    public var lockedSlot: String?
    public var allFoundTitle: String?
    public var allFoundText: String?
    public var comingSoonText: String?
}

public struct TeaserDTO: Codable, Sendable {
    public var enabled: Bool?
    public var screen: String?
    public var eggId: String?
    public var delayMs: Int?
    public var maxShows: Int?
    public var text: String?
}

public struct EggDTO: Codable, Sendable {
    public var id: String?
    public var order: Int?
    public var enabled: Bool?
    public var title: String?
    public var pictogram: String?
    public var screen: String?
    public var trigger: TriggerDTO?
    public var fallbackTrigger: TriggerDTO?
    public var schedule: ScheduleDTO?
    public var cooldownMs: Int?
    public var variants: [VariantDTO]?
    public var hint: HintDTO?
}

public struct TriggerDTO: Codable, Sendable {
    public var type: String?
    // shake
    public var threshold: Double?
    public var peaks: Int?
    public var windowMs: Int?
    // pullHold
    public var distance: Double?
    public var holdMs: Int?
    // palm
    public var minTouches: Int?
    public var minRadius: Double?
    public var maxMovement: Double?
    public var maxHoldMs: Int?
    // faceDownFlip
    public var downMs: Int?
}

public struct ScheduleDTO: Codable, Sendable {
    public var from: String?
    public var to: String?
    public var months: [Int]?
}

public struct HintDTO: Codable, Sendable {
    public var riddle: String?
    public var help: String?
    public var pictograms: [String]?
}

public struct VariantDTO: Codable, Sendable {
    public var id: String?
    public var weight: Double?
    public var effect: EffectDTO?
}

public struct EffectDTO: Codable, Sendable {
    public var durationMs: Int?
    public var dim: DimDTO?
    public var layers: [LayerDTO]?
    public var sound: String?
    public var interactSound: String?
    public var haptic: String?
}

public struct DimDTO: Codable, Sendable {
    public var color: String?
    public var opacity: Double?
}

/// Один слой эффекта. Поле `type` определяет, какие поля читаются.
/// Неизвестный `type` → слой пропускается (старое приложение не падает на новом контенте).
public struct LayerDTO: Codable, Sendable {
    public var type: String?
    // общие
    public var asset: String?
    public var opacity: Double?
    // particles
    public var count: Int?
    public var sizeMin: Double?
    public var sizeMax: Double?
    public var speedMin: Double?
    public var speedMax: Double?
    public var direction: String?
    public var wobble: Double?
    public var wobbleSpeed: Double?
    public var spin: Double?
    public var spawnMs: Int?
    public var tapToPop: Bool?
    // lottie
    public var speed: Double?
    public var placement: String?
    // fog
    public var colors: [String]?
    public var drift: Double?
    public var stars: Int?
    // ghosts
    public var palette: [String]?
    public var tapToVanish: Bool?
    public var followFinger: Bool?
}

public struct AssetDTO: Codable, Sendable {
    public var url: String?
    public var sha256: String?
    public var bytes: Int?
}
