import SwiftUI
import UIKit

@main
struct SberKidsFunApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake { FunLayer.shared.systemShake() }
    }
}

/// Даёт доступ к UIWindow из SwiftUI — нужен, чтобы поставить слой приколов поверх приложения.
struct WindowReader: UIViewRepresentable {
    let onWindow: @MainActor (UIWindow) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let v = ReaderView()
        v.onWindow = onWindow
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: ReaderView, context: Context) {}

    final class ReaderView: UIView {
        var onWindow: (@MainActor (UIWindow) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}
