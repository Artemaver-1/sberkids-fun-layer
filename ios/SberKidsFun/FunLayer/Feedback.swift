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

    func stopAll() {
        players.values.forEach { $0.stop() }
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
