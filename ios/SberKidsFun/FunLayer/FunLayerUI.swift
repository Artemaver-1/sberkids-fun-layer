import FunLayerCore
import SwiftUI
import UIKit

/// Цвета слоя в духе макетов СберKids (лайм, лаванда, голубой). В продукте — дизайн-система приложения.
enum FunStyle {
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.14)
    static let secondary = Color(red: 0.47, green: 0.48, blue: 0.55)
    static let lime = Color(red: 0.67, green: 0.99, blue: 0.32)
    static let aqua = Color(red: 0.53, green: 0.89, blue: 0.93)
    static let lavender = Color(red: 0.80, green: 0.76, blue: 0.95)
    static let violet = Color(red: 0.55, green: 0.45, blue: 0.95)
    static let sky = Color(red: 0.75, green: 0.87, blue: 0.97)
    static let card = Color(red: 0.96, green: 0.96, blue: 0.98)
    static let primaryGradient = LinearGradient(colors: [aqua, lime], startPoint: .leading, endPoint: .trailing)
    static let badgeGradient = LinearGradient(colors: [lavender, sky], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Тост «Пасхалка найдена! 1 из 5»

struct ToastView: View {
    let model: ToastModel
    @EnvironmentObject private var fun: FunLayer

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                EggBadge(pictogram: fun.config?.egg(id: model.eggId)?.pictogram ?? "sparkles", size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title)
                        .font(FunStyle.rounded(16, .bold))
                        .foregroundColor(FunStyle.ink)
                    Text(model.subtitle)
                        .font(FunStyle.rounded(13))
                        .foregroundColor(FunStyle.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(FunStyle.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: FunStyle.violet.opacity(0.25), radius: 18, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(model.isFirstFind ? AnyShapeStyle(FunStyle.primaryGradient) : AnyShapeStyle(Color.clear), lineWidth: 2)
            )
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { fun.toastFrame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { fun.toastFrame = $0 }
            })
            .contentShape(Rectangle())
            .onTapGesture { fun.openSheet(from: model) }
            .gesture(DragGesture(minimumDistance: 10).onEnded { v in
                if v.translation.height < -15 { fun.dismissToast() }
            })
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, fun.safeInsets.top + 6)
    }
}

// MARK: - Шторка с объяснением и подсказкой

struct HintSheetView: View {
    let model: SheetModel
    @EnvironmentObject private var fun: FunLayer
    @State private var shown = false
    @State private var drag: CGFloat = 0

    var body: some View {
        let _ = fun.progressVersion
        ZStack(alignment: .bottom) {
            Color.black.opacity(shown ? 0.35 : 0)
                .onTapGesture { close() }
            panel
                .offset(y: shown ? max(0, drag) : 700)
                .gesture(DragGesture()
                    .onChanged { drag = $0.translation.height }
                    .onEnded { v in
                        if v.translation.height > 120 { close() } else { withAnimation(.spring()) { drag = 0 } }
                    })
        }
        .onAppear { withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { shown = true } }
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.22)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { fun.closeSheet() }
    }

    @ViewBuilder private var panel: some View {
        if let config = fun.config, let engine = fun.engine {
            let egg = config.egg(id: model.eggId)
            let found = engine.foundCount
            let total = engine.total
            VStack(spacing: 16) {
                Capsule().fill(Color.black.opacity(0.12)).frame(width: 40, height: 5).padding(.top, 8)

                HStack(spacing: 14) {
                    EggBadge(pictogram: egg?.pictogram ?? "sparkles", size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(config.texts.sheetTitle).font(FunStyle.rounded(24, .heavy)).foregroundColor(FunStyle.ink)
                        if let egg { Text(egg.title).font(FunStyle.rounded(16, .semibold)).foregroundColor(FunStyle.violet) }
                    }
                    Spacer()
                }

                Text(Template.render(config.texts.sheetIntro, ["total": "\(total)", "n": "\(found)"]))
                    .font(FunStyle.rounded(16))
                    .foregroundColor(FunStyle.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                ProgressSlots(eggs: config.eggs, total: total, isFound: { engine.progress.isFound($0) })

                hintCard(config: config, engine: engine)

                HStack(spacing: 12) {
                    Button { fun.share() } label: {
                        Label(config.texts.shareButton, systemImage: "square.and.arrow.up")
                            .font(FunStyle.rounded(16, .semibold))
                            .foregroundColor(FunStyle.ink)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(FunStyle.card))
                    }
                    Button { close() } label: {
                        Text(config.texts.closeButton)
                            .font(FunStyle.rounded(17, .bold))
                            .foregroundColor(FunStyle.ink)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(FunStyle.primaryGradient))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, fun.safeInsets.bottom + 14)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.12), radius: 20, y: -4)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    @ViewBuilder
    private func hintCard(config: FunConfig, engine: EggEngine) -> some View {
        let card = engine.nextHint(now: Date())
        VStack(alignment: .leading, spacing: 12) {
            switch card.kind {
            case .next(let next):
                Text(config.texts.nextHintTitle)
                    .font(FunStyle.rounded(14, .bold))
                    .foregroundColor(FunStyle.violet)
                    .textCase(.uppercase)
                PictogramRow(keys: next.hint.pictograms)
                Text(next.hint.riddle)
                    .font(FunStyle.rounded(18, .semibold))
                    .foregroundColor(FunStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if card.level >= 1 {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill").foregroundColor(.orange)
                        Text(next.hint.help)
                            .font(FunStyle.rounded(15))
                            .foregroundColor(FunStyle.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if !next.hint.help.isEmpty {
                    Button {
                        withAnimation(.spring()) { fun.revealMoreHint(next.id) }
                    } label: {
                        Label(config.texts.moreHintButton, systemImage: "lightbulb")
                            .font(FunStyle.rounded(15, .semibold))
                            .foregroundColor(FunStyle.violet)
                    }
                }
            case .comingSoon:
                Label {
                    Text(Template.render(config.texts.comingSoonText, ["left": "\(engine.total - engine.foundCount)"]))
                        .font(FunStyle.rounded(17, .semibold))
                        .foregroundColor(FunStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "hourglass").foregroundColor(FunStyle.violet)
                }
            case .allFound:
                Text(config.texts.allFoundTitle).font(FunStyle.rounded(20, .heavy)).foregroundColor(FunStyle.ink)
                Text(config.texts.allFoundText).font(FunStyle.rounded(16)).foregroundColor(FunStyle.ink)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [FunStyle.lavender.opacity(0.45), FunStyle.sky.opacity(0.45)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}

/// Слоты коллекции: найденные — цветные, ненайденные — «?», ещё не выпущенные — замочек.
struct ProgressSlots: View {
    let eggs: [Egg]
    let total: Int
    let isFound: (String) -> Bool

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<total, id: \.self) { i in
                let egg = i < eggs.count ? eggs[i] : nil
                let found = egg.map { isFound($0.id) } ?? false
                ZStack {
                    Circle()
                        .fill(found ? AnyShapeStyle(FunStyle.badgeGradient) : AnyShapeStyle(FunStyle.card))
                    if let egg, found {
                        EggIcon(pictogram: egg.pictogram).padding(10)
                    } else if egg != nil {
                        Text("?").font(FunStyle.rounded(20, .heavy)).foregroundColor(FunStyle.secondary)
                    } else {
                        Image(systemName: "lock.fill").font(.system(size: 15, weight: .semibold))
                            .foregroundColor(FunStyle.secondary.opacity(0.6))
                    }
                }
                .frame(width: 50, height: 50)
                .overlay(Circle().stroke(found ? FunStyle.violet.opacity(0.4) : Color.clear, lineWidth: 2))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Найдено \(eggs.filter { isFound($0.id) }.count) из \(total)")
    }
}

// MARK: - Иконки пасхалок

struct EggBadge: View {
    let pictogram: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(FunStyle.badgeGradient)
            EggIcon(pictogram: pictogram).padding(size * 0.2)
        }
        .frame(width: size, height: size)
    }
}

struct EggIcon: View {
    let pictogram: String

    var body: some View {
        switch pictogram {
        case "egg.bubbles":
            GeometryReader { g in
                let s = min(g.size.width, g.size.height)
                ZStack {
                    bubble(s * 0.62).offset(x: -s * 0.14, y: s * 0.12)
                    bubble(s * 0.42).offset(x: s * 0.24, y: -s * 0.18)
                    bubble(s * 0.24).offset(x: s * 0.3, y: s * 0.3)
                }
                .frame(width: g.size.width, height: g.size.height)
            }
        case "egg.monkey":
            BananaShape()
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.3), Color(red: 0.96, green: 0.7, blue: 0.17)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(BananaShape().stroke(Color(red: 0.85, green: 0.6, blue: 0.15), lineWidth: 1.2))
                .rotationEffect(.degrees(-20))
        case "egg.ghosts":
            GhostShape()
                .fill(Color.white)
                .overlay(GhostShape().stroke(FunStyle.violet.opacity(0.5), lineWidth: 1.2))
                .overlay(
                    GeometryReader { g in
                        let w = g.size.width
                        HStack(spacing: w * 0.18) {
                            Capsule().fill(FunStyle.ink).frame(width: w * 0.12, height: w * 0.17)
                            Capsule().fill(FunStyle.ink).frame(width: w * 0.12, height: w * 0.17)
                        }
                        .frame(width: w, height: g.size.height * 0.62)
                    }
                )
        case "egg.robots":
            Image(systemName: "gearshape.2.fill").resizable().scaledToFit().foregroundColor(FunStyle.violet)
        case "egg.snow":
            Image(systemName: "snowflake").resizable().scaledToFit().foregroundColor(.white)
        default:
            Image(systemName: "sparkles").resizable().scaledToFit().foregroundColor(FunStyle.violet)
        }
    }

    private func bubble(_ d: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [.white.opacity(0.1), Color(red: 0.8, green: 0.7, blue: 1).opacity(0.7)],
                                 center: .center, startRadius: 0, endRadius: d * 0.55))
            .overlay(Circle().stroke(Color.white, lineWidth: max(1, d * 0.06)))
            .overlay(Circle().fill(Color.white.opacity(0.9)).frame(width: d * 0.22, height: d * 0.14)
                .offset(x: -d * 0.18, y: -d * 0.2))
            .frame(width: d, height: d)
    }
}

struct SpiralShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rMax = min(rect.width, rect.height) / 2
        let steps = 120
        for i in 0...steps {
            let k = Double(i) / Double(steps)
            let a = k * 2.5 * 2 * Double.pi
            let r = rMax * (1 - 0.85 * k)
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

struct BananaShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + w * 0.04, y: rect.minY + h * 0.45))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - w * 0.04, y: rect.minY + h * 0.4),
                       control: CGPoint(x: rect.midX, y: rect.maxY + h * 0.35))
        p.addLine(to: CGPoint(x: rect.maxX - w * 0.1, y: rect.minY + h * 0.25))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.12, y: rect.minY + h * 0.3),
                       control: CGPoint(x: rect.midX, y: rect.maxY - h * 0.1))
        p.closeSubpath()
        return p
    }
}

struct GhostShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = Double(rect.width) / 0.86 * 0.86
        let h = Double(rect.height)
        let path = EffectDrawing.ghostPath(w: w, h: h * 0.95, phase: 0.6)
        return path.offsetBy(dx: rect.midX, dy: rect.midY + rect.height * 0.04)
    }
}

// MARK: - Анимированные пиктограммы подсказок
// Младшие дети читают по слогам — подсказка сначала показывает, а потом говорит.

struct PictogramRow: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(keys.enumerated()), id: \.offset) { i, key in
                if i > 0 {
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold)).foregroundColor(FunStyle.secondary)
                }
                PictogramView(key: key).frame(width: 64, height: 64)
            }
        }
    }
}

struct PictogramView: View {
    let key: String

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white)
                content(t: t)
            }
        }
        .accessibilityLabel(Self.label(key))
    }

    @ViewBuilder private func content(t: Double) -> some View {
        switch key {
        case "gesture.shake":
            Image(systemName: "iphone")
                .font(.system(size: 30, weight: .medium))
                .foregroundColor(FunStyle.ink)
                .rotationEffect(.degrees(16 * sin(t * 18) * max(0, sin(t * 2.2))))
                .overlay(
                    Image(systemName: "wave.3.right").font(.system(size: 12, weight: .bold))
                        .foregroundColor(FunStyle.violet).offset(x: 20)
                        .opacity(max(0, sin(t * 2.2)))
                )
        case "gesture.pullHold":
            let cycle = t.truncatingRemainder(dividingBy: 2.4) / 2.4
            let y = cycle < 0.4 ? -14 + 28 * (cycle / 0.4) : (cycle < 0.85 ? 14 : 14 - 28 * ((cycle - 0.85) / 0.15))
            ZStack {
                RoundedRectangle(cornerRadius: 6).stroke(FunStyle.ink, lineWidth: 2).frame(width: 30, height: 46)
                Circle()
                    .trim(from: 0, to: cycle >= 0.4 && cycle < 0.85 ? (cycle - 0.4) / 0.45 : 0)
                    .stroke(FunStyle.violet, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 26, height: 26).rotationEffect(.degrees(-90)).offset(y: y)
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 20)).foregroundColor(Color(red: 0.95, green: 0.72, blue: 0.5))
                    .offset(x: 6, y: y + 10)
            }
        case "gesture.palm":
            let cycle = t.truncatingRemainder(dividingBy: 2.6) / 2.6
            let cover = cycle < 0.25 ? cycle / 0.25 : (cycle < 0.8 ? 1 : 1 - (cycle - 0.8) / 0.2)
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.08, green: 0.06, blue: 0.2).opacity(0.85 * cover))
                    .frame(width: 30, height: 46)
                RoundedRectangle(cornerRadius: 6).stroke(FunStyle.ink, lineWidth: 2).frame(width: 30, height: 46)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 30)).foregroundColor(Color(red: 0.95, green: 0.72, blue: 0.5))
                    .offset(x: 26 * (1 - cover), y: 4)
                    .opacity(0.3 + 0.7 * cover)
            }
        case "gesture.circles":
            // палец кружит по экрану
            let a = t * 2 * Double.pi * 0.9
            ZStack {
                Circle().stroke(FunStyle.violet.opacity(0.35), style: StrokeStyle(lineWidth: 2.4, dash: [4, 4]))
                    .frame(width: 34, height: 34)
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 18)).foregroundColor(Color(red: 0.95, green: 0.72, blue: 0.5))
                    .offset(x: 17 * cos(a) + 5, y: 17 * sin(a) + 7)
            }
        case "gesture.spiral":
            // спираль рисуется от края к центру
            let cycle = t.truncatingRemainder(dividingBy: 2.4) / 2.4
            let draw = min(1, cycle / 0.75)
            SpiralShape()
                .trim(from: 0, to: draw)
                .stroke(FunStyle.violet, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 16)).foregroundColor(Color(red: 0.95, green: 0.72, blue: 0.5))
                    .offset(x: 14, y: 14))
        case "gesture.tap7":
            // палец стучит, счётчик бежит 1…7
            let cycle = t.truncatingRemainder(dividingBy: 2.6)
            let n = min(7, Int(cycle / 0.22) + 1)
            let tapPhase = (cycle.truncatingRemainder(dividingBy: 0.22)) / 0.22
            ZStack {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 24)).foregroundColor(Color(red: 0.95, green: 0.72, blue: 0.5))
                    .offset(x: 6, y: 8 - (cycle < 1.54 ? 5 * sin(tapPhase * .pi) : 0))
                Text("\(n)")
                    .font(FunStyle.rounded(15, .heavy)).foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(n == 7 ? Color.green : FunStyle.violet))
                    .offset(x: -14, y: -16)
            }
        case "gesture.faceDown":
            // телефон переворачивается экраном вниз, «темнеет» и возвращается обратно
            let cycle = t.truncatingRemainder(dividingBy: 2.8) / 2.8
            let flip = cycle < 0.3 ? cycle / 0.3 : (cycle < 0.7 ? 1 : 1 - (cycle - 0.7) / 0.3)
            let eased = (1 - cos(Double.pi * flip)) / 2
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(eased > 0.5 ? Color(red: 0.12, green: 0.1, blue: 0.25) : Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(FunStyle.ink, lineWidth: 2))
                    .overlay(Image(systemName: eased > 0.5 ? "moon.stars.fill" : "sun.max.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(eased > 0.5 ? .yellow : .orange)
                        .scaleEffect(x: 1, y: eased > 0.5 ? -1 : 1))
                    .frame(width: 30, height: 46)
                    .rotation3DEffect(.degrees(180 * eased), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            }
        default:
            Image(systemName: Self.symbol(key))
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(FunStyle.violet)
        }
    }

    static func symbol(_ key: String) -> String {
        switch key {
        case "tab.main": return "house.fill"
        case "tab.content": return "play.rectangle.fill"
        case "tab.piggy": return "banknote.fill"
        case "tab.tasks": return "checkmark.circle.fill"
        case "screen.profile": return "person.crop.circle.fill"
        case "screen.settings": return "gearshape.fill"
        default: return "questionmark"
        }
    }

    static func label(_ key: String) -> String {
        switch key {
        case "tab.main": return "Главный экран"
        case "tab.content": return "Вкладка Контент"
        case "tab.piggy": return "Копилки"
        case "tab.tasks": return "Дела"
        case "screen.profile": return "Профиль"
        case "gesture.shake": return "Потряси телефон"
        case "gesture.pullHold": return "Потяни вниз и держи"
        case "gesture.palm": return "Накрой экран ладонью"
        case "gesture.faceDown": return "Положи телефон экраном вниз"
        case "gesture.tap7": return "Нажми 7 раз"
        case "gesture.spiral": return "Нарисуй спираль"
        case "gesture.circles": return "Покрути пальцем 2–3 круга"
        case "screen.settings": return "Настройки"
        default: return ""
        }
    }
}

// MARK: - Тизер: один пузырёк, чтобы первую пасхалку было легко найти

struct TeaserView: View {
    @EnvironmentObject private var fun: FunLayer
    @MainActor private static let bubble: UIImage? = Bundle.main.path(forResource: "bubble", ofType: "png").flatMap(UIImage.init(contentsOfFile:))

    var body: some View {
        TimelineView(.animation) { tl in
            let now = CACurrentMediaTime()
            let _ = tl.date
            ZStack(alignment: .topLeading) {
                Color.clear
                if let teaser = fun.teaser {
                    if let p = fun.teaserPosition(at: now) {
                        let age = now - teaser.start
                        bubbleView
                            .frame(width: 58, height: 58)
                            .scaleEffect(min(1, age / 0.4))
                            .opacity(min(1, (4.4 - age) / 0.6))
                            .position(p)
                    } else if let point = teaser.popPoint, let popped = teaser.poppedAt {
                        let age = now - popped
                        Circle().stroke(Color.white, lineWidth: 2)
                            .frame(width: 58 + 60 * age, height: 58 + 60 * age)
                            .opacity(max(0, 1 - age * 3))
                            .position(point)
                        tooltip(teaser.text)
                            .scaleEffect(min(1, 0.6 + age * 2))
                            .opacity(min(1, age * 4))
                            .position(x: min(max(point.x, 120), fun.overlaySize.width - 120), y: point.y + 64)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in fun.popTeaser() })
    }

    @ViewBuilder private var bubbleView: some View {
        if let img = Self.bubble {
            Image(uiImage: img).resizable()
        } else {
            Circle().stroke(Color.white, lineWidth: 2)
        }
    }

    private func tooltip(_ text: String) -> some View {
        HStack(spacing: 10) {
            PictogramView(key: "gesture.shake").frame(width: 44, height: 44)
            Text(text).font(FunStyle.rounded(16, .bold)).foregroundColor(FunStyle.ink)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(Color.white).shadow(color: FunStyle.violet.opacity(0.3), radius: 12, y: 6))
    }
}

// MARK: - Банан выглядывает сверху, пока ребёнок тянет ленту

struct BananaPeekView: View {
    let fraction: Double
    let hold: Double
    @EnvironmentObject private var fun: FunLayer

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let size = fun.overlaySize
            BananaShape()
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.3), Color(red: 0.96, green: 0.7, blue: 0.17)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(BananaShape().stroke(Color(red: 0.85, green: 0.6, blue: 0.15), lineWidth: 1.5))
                .frame(width: 54, height: 24)
                .rotationEffect(.degrees(-100 + sin(t * 26) * (3 + 16 * hold)))
                .position(x: size.width * 0.66, y: -20 + (fun.safeInsets.top + 34) * fraction + 10 * hold)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Под ладонью темнеет, по краям ползёт туман

struct PalmDarknessView: View {
    let progress: Double
    let armed: Bool
    @EnvironmentObject private var fun: FunLayer

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.06, blue: 0.2).opacity(0.62 * progress)
            RadialGradient(colors: [.clear, FunStyle.violet.opacity(0.55 * progress)],
                           center: .center, startRadius: 120, endRadius: 520)
            if armed {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 26)).foregroundColor(.white)
                    Text("Кто-то здесь есть… Убери ладошку!")
                        .font(FunStyle.rounded(18, .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, fun.safeInsets.top + 40)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: armed)
    }
}
