import FunLayerCore
import Lottie
import SwiftUI
import UIKit

/// Отдельное окно над приложением. Существующие экраны не меняются вообще:
/// слой живёт поверх и пропускает все касания, кроме попавших в пузырь, призрака,
/// тост или открытую ребёнком шторку.
final class OverlayWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard FunLayer.shared.wantsTouch(at: point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

struct OverlayRootView: View {
    @EnvironmentObject private var fun: FunLayer

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.allowsHitTesting(false)

            if fun.palmProgress > 0 {
                PalmDarknessView(progress: fun.palmProgress, armed: fun.palmArmed)
                    .transition(.opacity)
            }
            if fun.trailActive {
                SnakeTrailView()
                    .transition(.opacity)
            }
            if let effect = fun.effect {
                EffectView(runtime: effect)
                    .id(effect.id)
                    .transition(.opacity)
            }
            if fun.pullFraction > 0.05 {
                BananaPeekView(fraction: fun.pullFraction, hold: fun.pullHold)
                    .transition(.opacity)
            }
            if fun.teaser != nil {
                TeaserView()
            }
            if let hint = fun.tapHint {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "wrench.and.screwdriver.fill").foregroundColor(FunStyle.violet)
                        Text(hint).font(FunStyle.rounded(15, .bold)).foregroundColor(FunStyle.ink)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Color.white).shadow(color: .black.opacity(0.15), radius: 10, y: 4))
                    .padding(.bottom, fun.safeInsets.bottom + 40)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            if let toast = fun.toast {
                ToastView(model: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let sheet = fun.sheet {
                HintSheetView(model: sheet)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea(.all, edges: .all)
        .animation(.easeOut(duration: 0.2), value: fun.palmProgress > 0)
    }
}

// MARK: - Эффект

struct EffectView: View {
    let runtime: EffectRuntime
    @EnvironmentObject private var fun: FunLayer

    var body: some View {
        ZStack {
            TimelineView(.animation) { timeline in
                let t = runtime.elapsed
                let env = EffectEnvelope.alpha(time: t, duration: runtime.duration)
                let _ = timeline.date
                ZStack {
                    if runtime.effect.dimOpacity > 0 {
                        Color(rgba: runtime.effect.dimColor).opacity(runtime.effect.dimOpacity * env)
                    }
                    Canvas { ctx, size in
                        runtime.update(to: t)
                        for layer in runtime.layers {
                            switch layer {
                            case .fog(let spec, let image):
                                EffectDrawing.fog(&ctx, size: size, spec: spec, image: image, t: t, alpha: env)
                            case .particles(let field, let image):
                                EffectDrawing.particles(&ctx, field: field, image: image, alpha: env)
                            case .ghosts(let field):
                                if let path = runtime.portalPath {
                                    EffectDrawing.portal(&ctx, path: path, center: runtime.portalCenter, t: t, alpha: env)
                                }
                                EffectDrawing.ghosts(&ctx, field: field, look: runtime.lookTarget, t: t, alpha: env)
                            case .lottie:
                                break
                            }
                        }
                    }
                }
            }
            ForEach(Array(runtime.layers.enumerated()), id: \.offset) { _, layer in
                // (сцена под интерфейсом рисуется первой, панель интерфейса — поверх)
                if case .lottie(let spec, let url) = layer, let url {
                    LottieLayerView(url: url, speed: spec.speed,
                                    onStart: { [id = runtime.id] in fun.lottieStarted(id) },
                                    onFinish: { [id = runtime.id] in fun.lottieFinished(id) })
                }
            }
        }
        .overlay(revealPanel)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { v in
                    if v.translation == .zero { fun.tapEffect(at: v.location) }
                }
        )
        .ignoresSafeArea()
    }
}

extension EffectView {
    /// Снимок интерфейса, который механически отъезжает и с ударом возвращается.
    @ViewBuilder var revealPanel: some View {
        if let reveal = runtime.reveal, let snapshot = runtime.revealSnapshot {
            TimelineView(.animation) { timeline in
                let _ = timeline.date
                let o = runtime.revealOffset(at: runtime.elapsed, width: Double(runtime.size.width))
                RevealPanel(image: snapshot, toRight: reveal.direction == .right)
                    .offset(x: o.x, y: o.y)
                    .rotationEffect(.degrees(o.rotation))
            }
            .allowsHitTesting(false)
        }
    }
}

/// Интерфейс как «стальная панель»: снимок экрана + металлический торец с болтами и тень на сцене.
struct RevealPanel: View {
    let image: UIImage
    let toRight: Bool

    var body: some View {
        ZStack(alignment: toRight ? .leading : .trailing) {
            Image(uiImage: image)
                .resizable()
                .shadow(color: .black.opacity(0.55), radius: 22, x: toRight ? -10 : 10)
            edge
                .frame(width: 14)
                .offset(x: toRight ? -14 : 14)
        }
        .ignoresSafeArea()
    }

    private var edge: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.55), Color(white: 0.92), Color(white: 0.5)],
                           startPoint: .leading, endPoint: .trailing)
            VStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { _ in
                    Spacer()
                    Circle()
                        .fill(RadialGradient(colors: [Color(white: 0.95), Color(white: 0.4)], center: .topLeading,
                                             startRadius: 0, endRadius: 6))
                        .frame(width: 6, height: 6)
                }
                Spacer()
            }
        }
    }
}

/// Светящаяся змейка за пальцем: яркая голова, хвост тает примерно за 0,4 с.
struct SnakeTrailView: View {
    @EnvironmentObject private var fun: FunLayer
    private static let life = 0.42

    var body: some View {
        TimelineView(.animation) { timeline in
            let _ = timeline.date
            let now = ProcessInfo.processInfo.systemUptime
            Canvas { ctx, _ in
                let pts = fun.trail.filter { now - $0.t < Self.life }
                guard pts.count > 1 else { return }
                let violet = Color(red: 0.62, green: 0.48, blue: 1)
                for i in 1..<pts.count {
                    let a = pts[i - 1], b = pts[i]
                    let k = max(0, 1 - (now - b.t) / Self.life)      // 1 у головы, 0 у хвоста
                    var seg = Path()
                    seg.move(to: CGPoint(x: a.x, y: a.y))
                    seg.addLine(to: CGPoint(x: b.x, y: b.y))
                    ctx.stroke(seg, with: .color(violet.opacity(0.35 * k)),
                               style: StrokeStyle(lineWidth: 6 + 16 * k, lineCap: .round))
                    ctx.stroke(seg, with: .color(.white.opacity(0.9 * k)),
                               style: StrokeStyle(lineWidth: 1.5 + 3 * k, lineCap: .round))
                }
                if let head = pts.last {
                    ctx.fill(Path(ellipseIn: CGRect(x: head.x - 9, y: head.y - 9, width: 18, height: 18)),
                             with: .color(.white.opacity(0.85)))
                    ctx.fill(Path(ellipseIn: CGRect(x: head.x - 18, y: head.y - 18, width: 36, height: 36)),
                             with: .color(violet.opacity(0.3)))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// Lottie уже есть в стеке СберKids на обеих платформах. Core Animation-движок Lottie
/// отдаёт анимацию системному рендер-серверу — почти ноль нагрузки на CPU.
struct LottieLayerView: UIViewRepresentable {
    let url: URL
    let speed: Double
    let onStart: @MainActor () -> Void
    let onFinish: @MainActor () -> Void

    func makeUIView(context: Context) -> Host {
        let host = Host()
        host.isUserInteractionEnabled = false
        host.backgroundColor = .clear
        // разобранная заранее анимация из кэша; движок mainThread стартует без «разгона»
        let view = LottieAnimationView(animation: LottieAnimation.filepath(url.path, animationCache: DefaultAnimationCache.sharedCache),
                                       configuration: LottieConfiguration(renderingEngine: .mainThread))
        view.contentMode = .scaleAspectFill
        view.loopMode = .playOnce
        view.animationSpeed = speed
        view.backgroundBehavior = .pauseAndRestore
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        host.lottie = view
        host.onStart = onStart
        host.onFinish = onFinish
        return host
    }

    func updateUIView(_ uiView: Host, context: Context) {}

    static func dismantleUIView(_ uiView: Host, coordinator: ()) {
        uiView.lottie?.stop()
    }

    /// Запускает анимацию, только когда она реально на экране (а не в момент создания),
    /// и сообщает о старте и окончании — по ним синхронизируются звук и длительность эффекта.
    final class Host: UIView {
        var lottie: LottieAnimationView?
        var onStart: (@MainActor () -> Void)?
        var onFinish: (@MainActor () -> Void)?
        private var started = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, !started, let lottie else { return }
            started = true
            layoutIfNeeded()
            onStart?()
            lottie.play { [weak self] finished in
                guard finished else { return }
                MainActor.assumeIsolated { self?.onFinish?() }
            }
        }
    }
}

extension Color {
    init(rgba c: RGBA) {
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }
}

// MARK: - Рисование

enum EffectDrawing {
    static func particles(_ ctx: inout GraphicsContext, field: ParticleField, image: UIImage?, alpha: Double) {
        let resolved = image.map { ctx.resolve(Image(uiImage: $0)) }
        for p in field.particles where p.alive && p.spawned {
            var c = ctx
            let pop = p.popProgress
            c.opacity = alpha * field.spec.opacity * (1 - pop)
            c.translateBy(x: p.position.x, y: p.position.y)
            c.rotate(by: .radians(p.rotation))
            let grow = 1 + 0.3 * pop
            c.scaleBy(x: p.scaleX * grow, y: p.scaleY * grow)
            let r = CGRect(x: -p.size / 2, y: -p.size / 2, width: p.size, height: p.size)
            if let resolved {
                c.draw(resolved, in: r)
            } else {
                c.stroke(Path(ellipseIn: r), with: .color(.white.opacity(0.8)), lineWidth: 2)
            }
            if pop > 0 {
                var ring = ctx
                ring.opacity = alpha * (1 - pop)
                let rr = r.offsetBy(dx: p.position.x, dy: p.position.y).insetBy(dx: -p.size * 0.35 * pop, dy: -p.size * 0.35 * pop)
                ring.stroke(Path(ellipseIn: rr), with: .color(.white), lineWidth: 2.5 * (1 - pop) + 0.5)
            }
        }
        for d in field.droplets {
            var c = ctx
            c.opacity = alpha * d.alpha
            let r = CGRect(x: d.position.x - d.size / 2, y: d.position.y - d.size / 2, width: d.size, height: d.size)
            c.fill(Path(ellipseIn: r), with: .color(Color(red: 0.92, green: 0.9, blue: 1)))
        }
    }

    static func fog(_ ctx: inout GraphicsContext, size: CGSize, spec: FogSpec, image: UIImage?, t: Double, alpha: Double) {
        let colors = spec.colors.map { Color(rgba: $0) }
        // туманность: большие мягкие пятна цвета медленно плывут
        for (i, color) in colors.enumerated() {
            let fi = Double(i)
            let center = CGPoint(x: size.width * (0.5 + 0.35 * sin(t * 0.21 + fi * 2.1)),
                                 y: size.height * (0.42 + 0.28 * cos(t * 0.17 + fi * 1.7)))
            let radius = size.width * 0.85
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [color.opacity(0.34 * alpha), color.opacity(0)]),
                                           center: center, startRadius: 0, endRadius: radius))
        }
        // текстура тумана в два слоя с параллаксом
        if let image {
            let resolved = ctx.resolve(Image(uiImage: image))
            let tile: CGFloat = 520
            for k in 0..<2 {
                var c = ctx
                c.opacity = alpha * spec.opacity * (k == 0 ? 0.9 : 0.65)
                c.addFilter(.colorMultiply(colors[k % colors.count].opacity(1)))
                let speed = spec.drift * (k == 0 ? 1 : 1.8)
                let ox = CGFloat((t * speed).truncatingRemainder(dividingBy: Double(tile)))
                let oy = CGFloat((t * speed * 0.35).truncatingRemainder(dividingBy: Double(tile)))
                let scale: CGFloat = k == 0 ? 1 : 0.7
                let ts = tile * scale
                var y = -ts + oy * scale
                while y < size.height {
                    var x = -ts + (k == 0 ? ox : -ox) * scale
                    while x < size.width {
                        c.draw(resolved, in: CGRect(x: x, y: y, width: ts + 1, height: ts + 1))
                        x += ts
                    }
                    y += ts
                }
            }
        }
        // туман стелется снизу
        ctx.fill(Path(CGRect(x: 0, y: size.height * 0.55, width: size.width, height: size.height * 0.45)),
                 with: .linearGradient(Gradient(colors: [.clear, (colors.first ?? .purple).opacity(0.45 * alpha)]),
                                       startPoint: CGPoint(x: 0, y: size.height * 0.55),
                                       endPoint: CGPoint(x: 0, y: size.height)))
        // мерцающие звёздочки
        for i in 0..<spec.stars {
            let h1 = hash(i), h2 = hash(i + 101), h3 = hash(i + 211)
            let twinkle = 0.5 + 0.5 * sin(t * (1.5 + 2.5 * h3) + Double(i))
            var c = ctx
            c.opacity = alpha * twinkle * 0.9
            let s = 2.5 + 4 * h3
            c.translateBy(x: size.width * h1, y: size.height * 0.85 * h2)
            c.fill(starPath(size: s), with: .color(.white))
        }
    }

    /// Нарисованная спираль вспыхивает от начала к концу, затем гаснет; в центре — светящийся портал.
    static func portal(_ ctx: inout GraphicsContext, path pts: [CGPoint], center: CGPoint, t: Double, alpha: Double) {
        var p = Path()
        p.addLines(pts)
        let draw = Ease.outCubic(t / 0.5)
        let fade = 1 - Ease.clamp01((t - 0.9) / 1.4)
        guard fade > 0 else { return }
        let trimmed = p.trimmedPath(from: 0, to: draw)
        let violet = Color(red: 0.62, green: 0.48, blue: 1)
        var c = ctx
        c.opacity = alpha * fade
        c.stroke(trimmed, with: .color(violet.opacity(0.28)), style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
        c.stroke(trimmed, with: .color(violet.opacity(0.55)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
        c.stroke(trimmed, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        // искра на «голове» линии
        if draw < 1, let head = trimmed.currentPoint {
            c.fill(Path(ellipseIn: CGRect(x: head.x - 9, y: head.y - 9, width: 18, height: 18)), with: .color(.white.opacity(0.9)))
        }
        // портал: вращающееся кольцо и свечение в центре
        let open = Ease.outBack((t - 0.35) / 0.6)
        if t > 0.35 {
            let r = 46 * open
            var g = ctx
            g.opacity = alpha * fade
            g.fill(Path(ellipseIn: CGRect(x: center.x - r * 1.6, y: center.y - r * 1.6, width: r * 3.2, height: r * 3.2)),
                   with: .radialGradient(Gradient(colors: [violet.opacity(0.55), violet.opacity(0)]), center: center,
                                         startRadius: 0, endRadius: r * 1.6))
            g.translateBy(x: center.x, y: center.y)
            g.rotate(by: .radians(t * 3))
            g.stroke(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.85)),
                     style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
        }
    }

    static func ghosts(_ ctx: inout GraphicsContext, field: GhostField, look: CGPoint?, t: Double, alpha: Double) {
        let target = look.map { Vec2($0.x, $0.y) }
        for g in field.ghosts where !g.gone && g.alpha > 0.01 {
            let color = Color(rgba: field.spec.palette[g.colorIndex % field.spec.palette.count])
            var c = ctx
            c.opacity = alpha * g.alpha
            c.translateBy(x: g.position.x, y: g.position.y)
            c.rotate(by: .radians(g.tilt))
            c.scaleBy(x: g.scale, y: g.scale)
            let look = field.spec.followFinger ? GhostField.pupilOffset(ghost: g, target: target) : Vec2(0, 0)
            drawGhost(&c, size: g.size, color: color, tailPhase: g.tailPhase, eyesClosed: g.eyesClosed,
                      look: look, armWave: sin(t * 3 + g.phase))
        }
    }

    /// Добрый мультяшный призрак: купол, волнистый подол, большие глаза, румянец.
    static func drawGhost(_ c: inout GraphicsContext, size s: Double, color: Color, tailPhase: Double,
                          eyesClosed: Bool, look: Vec2, armWave: Double) {
        let w = s * 0.86, h = s * 1.05
        let body = ghostPath(w: w, h: h, phase: tailPhase)
        // мягкое свечение
        for (k, o) in [(1.16, 0.10), (1.08, 0.16)] {
            var g = c
            g.scaleBy(x: k, y: k)
            g.fill(body, with: .color(color.opacity(o)))
        }
        // ручки
        for side in [-1.0, 1.0] {
            var a = c
            a.translateBy(x: side * w * 0.47, y: h * 0.06)
            a.rotate(by: .radians(side * (0.5 + 0.35 * armWave * side)))
            a.fill(Path(ellipseIn: CGRect(x: -w * 0.09, y: -w * 0.05, width: w * 0.18, height: w * 0.11)),
                   with: .color(color))
        }
        c.fill(body, with: .linearGradient(Gradient(colors: [.white, color]),
                                           startPoint: CGPoint(x: 0, y: -h * 0.6), endPoint: CGPoint(x: 0, y: h * 0.5)))
        c.stroke(body, with: .color(Color(red: 0.62, green: 0.56, blue: 0.95).opacity(0.35)), lineWidth: 1.2)

        let ink = Color(red: 0.17, green: 0.13, blue: 0.3)
        let eyeY = -h * 0.14 + look.y * w * 0.03
        let eyeDX = w * 0.17
        let lx = look.x * w * 0.04
        for side in [-1.0, 1.0] {
            let cx = side * eyeDX + lx
            if eyesClosed {
                var p = Path()
                p.move(to: CGPoint(x: cx - w * 0.06, y: eyeY))
                p.addQuadCurve(to: CGPoint(x: cx + w * 0.06, y: eyeY), control: CGPoint(x: cx, y: eyeY + w * 0.05))
                c.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            } else {
                let er = CGRect(x: cx - w * 0.065, y: eyeY - w * 0.085, width: w * 0.13, height: w * 0.17)
                c.fill(Path(ellipseIn: er), with: .color(ink))
                let hl = CGRect(x: cx - w * 0.03 + look.x * w * 0.015, y: eyeY - w * 0.06, width: w * 0.05, height: w * 0.05)
                c.fill(Path(ellipseIn: hl), with: .color(.white))
            }
            c.fill(Path(ellipseIn: CGRect(x: side * w * 0.29 - w * 0.06 + lx * 0.5, y: -h * 0.03, width: w * 0.12, height: w * 0.07)),
                   with: .color(Color(red: 1, green: 0.55, blue: 0.65).opacity(0.55)))
        }
        c.fill(Path(ellipseIn: CGRect(x: -w * 0.045 + lx, y: h * 0.0, width: w * 0.09, height: w * 0.1)),
               with: .color(Color(red: 0.55, green: 0.2, blue: 0.35)))
    }

    static func ghostPath(w: Double, h: Double, phase: Double) -> Path {
        var p = Path()
        let top = -h * 0.55
        let cy = -h * 0.12
        let r = w / 2
        let k = 0.5523 * r
        p.move(to: CGPoint(x: -r, y: cy))
        p.addCurve(to: CGPoint(x: 0, y: top), control1: CGPoint(x: -r, y: cy - k * 1.3), control2: CGPoint(x: -k, y: top))
        p.addCurve(to: CGPoint(x: r, y: cy), control1: CGPoint(x: k, y: top), control2: CGPoint(x: r, y: cy - k * 1.3))
        let base = h * 0.4
        p.addLine(to: CGPoint(x: r, y: base + 4 * sin(phase)))
        let bumps = 3
        for i in 0..<bumps {
            let x0 = r - Double(i) * w / Double(bumps)
            let x1 = x0 - w / Double(bumps)
            let wave = 5 * sin(phase + Double(i + 1) * 1.3)
            p.addQuadCurve(to: CGPoint(x: x1, y: base + wave),
                           control: CGPoint(x: (x0 + x1) / 2, y: base + h * 0.2 + wave))
        }
        p.closeSubpath()
        return p
    }

    static func starPath(size s: Double) -> Path {
        var p = Path()
        let q = s * 0.28
        let pts = [(0.0, -s), (q, -q), (s, 0), (q, q), (0, s), (-q, q), (-s, 0), (-q, -q)]
        p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for pt in pts.dropFirst() { p.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
        p.closeSubpath()
        return p
    }

    static func hash(_ i: Int) -> Double {
        let x = sin(Double(i) * 12.9898) * 43758.5453
        return x - floor(x)
    }
}
