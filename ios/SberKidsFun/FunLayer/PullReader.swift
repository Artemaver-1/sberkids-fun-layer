import SwiftUI
import UIKit

/// Подключается к системному UIScrollView, внутри которого лежит, и сообщает,
/// насколько ленту перетянули вниз сверх начала (pt). Работает одинаково на iOS 15–27:
/// не зависит от того, как SwiftUI доставляет геометрию при прокрутке.
/// В приложении СберKids это одна строка в существующем pull-to-refresh.
extension Notification.Name {
    /// Слой сработал на удержание — ленту нужно вернуть наверх, даже если палец ещё держит.
    static let funLayerReleasePull = Notification.Name("funLayerReleasePull")
}

struct PullReader: UIViewRepresentable {
    let onPull: @MainActor (CGFloat) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let v = ProbeView()
        v.onPull = onPull
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onPull = onPull
    }

    final class ProbeView: UIView {
        var onPull: (@MainActor (CGFloat) -> Void)?
        private var observation: NSKeyValueObservation?
        private weak var scroll: UIScrollView?
        private var releaseToken: NSObjectProtocol?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            observation = nil
            guard window != nil else {
                if let releaseToken { NotificationCenter.default.removeObserver(releaseToken) }
                releaseToken = nil
                return
            }
            var v: UIView? = superview
            while let current = v, !(current is UIScrollView) { v = current.superview }
            guard let scroll = v as? UIScrollView else { return }
            self.scroll = scroll
            if releaseToken == nil {
                releaseToken = NotificationCenter.default.addObserver(forName: .funLayerReleasePull, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.release() }
                }
            }
            observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                MainActor.assumeIsolated {
                    let overscroll = -(scroll.contentOffset.y + scroll.adjustedContentInset.top)
                    self?.onPull?(max(0, overscroll))
                }
            }
        }

        /// Прерываем жест прокрутки (палец остаётся на экране, но лента его «отпускает»)
        /// и плавно возвращаем ленту в начало.
        private func release() {
            guard let scroll, window != nil else { return }
            let pan = scroll.panGestureRecognizer
            pan.isEnabled = false
            pan.isEnabled = true
            scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: true)
        }

    }
}
