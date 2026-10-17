import AVFoundation
import FunLayerCore
import UIKit

/// Звук. Категория .ambient: уважает беззвучный режим и не глушит чужую музыку.
/// В СберKids звуки и вибрация уже есть — здесь минимальная обёртка для прототипа.
@MainActor
final class SoundPlayer {
    private var players: [URL: AVAudioPlayer] = [:]
    private var configured = false

    func play(_ url: URL?, volume: Float = 0.8) {
        guard let url else { return }
        if !configured {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            configured = true
        }
        let player: AVAudioPlayer
        if let p = players[url] {
            player = p
        } else {
            guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
            p.prepareToPlay()
            players[url] = p
            player = p
        }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    /// Короткие звуки касаний (лопание, хихиканье): каждый раз новый плеер и чуть другая
    /// высота тона — быстрые касания не обрывают друг друга и не звучат одинаково.
    private var oneShots: [AVAudioPlayer] = []

    func playVaried(_ url: URL?, volume: Float = 0.7) {
        guard let url, let p = try? AVAudioPlayer(contentsOf: url) else { return }
        if !configured {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            configured = true
        }
        oneShots.removeAll { !$0.isPlaying }
        p.enableRate = true
        p.rate = Float.random(in: 0.82...1.25)
        p.volume = volume
        p.play()
        oneShots.append(p)
    }

    func stopAll() {
        players.values.forEach { $0.stop() }
        oneShots.forEach { $0.stop() }
        oneShots.removeAll()
    }
}

@MainActor
enum Haptics {
    static func play(_ h: Haptic) {
        switch h {
        case .none: break
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    static func tick() { UISelectionFeedbackGenerator().selectionChanged() }
}
