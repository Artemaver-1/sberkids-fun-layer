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

// MARK: - Тост «Пасхалка найдена! 1 из 4»

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
            // робот машет только в шторке последней пасхалки — «Цех роботов»
            let showRobot = egg?.pictogram == "egg.robots"
            VStack(alignment: .leading, spacing: 18) {
                Capsule().fill(Color.black.opacity(0.12)).frame(width: 40, height: 5)
                    .frame(maxWidth: .infinity).padding(.top, 8)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        EggBadge(pictogram: egg?.pictogram ?? "sparkles", size: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(config.texts.sheetTitle)
                                .font(FunStyle.rounded(26, .heavy)).foregroundColor(FunStyle.ink)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            if let egg {
                                Text(egg.title).font(FunStyle.rounded(17, .semibold)).foregroundColor(FunStyle.violet)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                        }
                    }
                    Text(Template.render(config.texts.sheetIntro, ["total": "\(total)", "n": "\(found)"]))
                        .font(FunStyle.rounded(15.5))
                        .foregroundColor(FunStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, showRobot ? -14 : 0)
                }
                .padding(.trailing, showRobot ? 100 : 0)   // справа машет робот

                ProgressSlots(found: config.eggs.filter { engine.progress.isFound($0.id) }, newest: model.eggId, total: total)

                hintCard(config: config, engine: engine)

                HStack(spacing: 12) {
                    Button { fun.share() } label: {
                        Label(config.texts.shareButton, systemImage: "square.and.arrow.up")
                            .font(FunStyle.rounded(17, .semibold))
                            .foregroundColor(FunStyle.ink)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(red: 0.95, green: 0.95, blue: 0.98)))
                    }
                    Button { close() } label: {
                        Text(config.texts.closeButton)
                            .font(FunStyle.rounded(18, .bold))
                            .foregroundColor(FunStyle.ink)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(FunStyle.primaryGradient))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, fun.safeInsets.bottom + 14)
            .background(sheetBackground)
            .overlay(alignment: .topTrailing) {
                if showRobot {
                    RobotMascot()
                        .frame(width: 130, height: 152)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
        }
    }

    /// Белая шторка с лавандовым сиянием в углу, где машет маскот.
    private var sheetBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(RadialGradient(colors: [Color(red: 0.86, green: 0.84, blue: 1).opacity(0.85), Color(red: 0.9, green: 0.94, blue: 1).opacity(0.35), .clear],
                                         center: .topTrailing, startRadius: 10, endRadius: 330))
            )
            .shadow(color: .black.opacity(0.12), radius: 20, y: -4)
            .ignoresSafeArea(edges: .bottom)
    }

    private static let cardFill = LinearGradient(
        colors: [Color(red: 0.93, green: 0.92, blue: 1.0), Color(red: 0.90, green: 0.95, blue: 1.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    @ViewBuilder
    private func hintCard(config: FunConfig, engine: EggEngine) -> some View {
        let card = engine.nextHint(now: Date())
        Group {
            switch card.kind {
            case .next(let next):
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 15, weight: .bold)).foregroundColor(FunStyle.violet)
                        Text(config.texts.nextHintTitle)
                            .font(FunStyle.rounded(14, .bold))
                            .foregroundColor(FunStyle.violet)
                            .textCase(.uppercase)
                    }
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
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(Color.white.opacity(0.8)))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .comingSoon:
                HStack(spacing: 14) {
                    GlossyOrb(size: 56) {
                        Image(systemName: "hourglass").font(.system(size: 22, weight: .bold)).foregroundColor(FunStyle.violet)
                    }
                    Text(Template.render(config.texts.comingSoonText, ["left": "\(engine.total - engine.foundCount)"]))
                        .font(FunStyle.rounded(16, .semibold))
                        .foregroundColor(FunStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .allFound:
                HStack(spacing: 12) {
                    TreasureChest().frame(width: 92, height: 84)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(config.texts.allFoundTitle)
                            .font(FunStyle.rounded(20, .heavy)).foregroundColor(FunStyle.ink)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Text(config.texts.allFoundText)
                            .font(FunStyle.rounded(15)).foregroundColor(FunStyle.ink.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Self.cardFill))
    }
}

/// Коллекция без спойлеров: показываем только найденные пасхалки — глянцевые шарики с их иконками.
/// Ненайденных в ряду нет совсем, сколько осталось — только числом «Найдено N из 4».
struct ProgressSlots: View {
    let found: [Egg]
    let newest: String
    let total: Int

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                HStack(spacing: 14) {
                    ForEach(found, id: \.id) { egg in
                        GlossyOrb(size: 60) {
                            EggIcon(pictogram: egg.pictogram).padding(14)
                        }
                        .scaleEffect(egg.id == newest ? 1 + 0.04 * sin(t * 3.2) : 1)
                    }
                }
            }
            Text("Найдено \(found.count) из \(total)")
                .font(FunStyle.rounded(14, .semibold))
                .foregroundColor(FunStyle.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Найдено \(found.count) из \(total)")
    }
}

// MARK: - Иконки пасхалок

struct EggBadge: View {
    let pictogram: String
    let size: CGFloat

    var body: some View {
        GlossyOrb(size: size) {
            EggIcon(pictogram: pictogram).padding(size * 0.22)
        }
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
            .fill(RadialGradient(colors: [.white.opacity(0.05), .white.opacity(0.35)], center: .center, startRadius: 0, endRadius: d * 0.55))
            .overlay(Circle().stroke(Color.white, lineWidth: max(1.5, d * 0.09)))
            .overlay(Circle().trim(from: 0.55, to: 0.72).stroke(Color.white, style: StrokeStyle(lineWidth: max(1, d * 0.07), lineCap: .round))
                .padding(d * 0.2))
            .frame(width: d, height: d)
            .shadow(color: FunStyle.violet.opacity(0.25), radius: 1.5)
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
        case "gesture.hold":
            // палец прижат к аватарке, вокруг набирается кольцо-таймер
            let cycle = t.truncatingRemainder(dividingBy: 3.2) / 3.2
            let fill = min(1, cycle / 0.8)
            ZStack {
                Circle().stroke(FunStyle.violet.opacity(0.2), lineWidth: 3).frame(width: 38, height: 38)
                Circle().trim(from: 0, to: fill)
                    .stroke(FunStyle.violet, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 38, height: 38)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 22)).foregroundColor(FunStyle.violet.opacity(0.75))
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 18)).foregroundColor(Color(red: 0.95, green: 0.72, blue: 0.5))
                    .offset(x: 8, y: 12)
                    .scaleEffect(cycle < 0.8 ? 0.94 : 1)
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
        case "gesture.hold": return "Зажми аватарку на 5 секунд"
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

// MARK: - Удержание аватарки: туман сгущается вокруг пальца

/// Пока ребёнок держит аватарку, вокруг пальца клубится туман, а ближе к концу из него выглядывают глазки.
/// Первую секунду ничего не видно — обычное нажатие никто не заметит.
struct HoldFogView: View {
    let progress: Double
    let point: CGPoint

    private static let colors: [Color] = [
        Color(red: 0.56, green: 0.49, blue: 1), Color(red: 0.35, green: 0.85, blue: 0.9), Color(red: 0.77, green: 0.61, blue: 1),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let p = progress
                let ease = p * p * (3 - 2 * p)
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(red: 0.08, green: 0.06, blue: 0.2).opacity(0.34 * ease)))
                for i in 0..<8 {
                    let k = Double(i)
                    let a = k / 8 * 2 * .pi + t * (0.32 + 0.06 * Double(i % 3))
                    let orbit = (26 + 110 * ease) * (0.65 + 0.35 * sin(t * 0.8 + k * 1.7))
                    let c = CGPoint(x: point.x + orbit * cos(a), y: point.y + orbit * sin(a) * 0.85)
                    let r = 46 + 104 * ease
                    let col = Self.colors[i % 3]
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                             with: .radialGradient(Gradient(colors: [col.opacity(0.42 * ease), col.opacity(0)]),
                                                   center: c, startRadius: 0, endRadius: r))
                }
                // глазки выглядывают из тумана и моргают
                guard p > 0.45 else { return }
                let eyesAlpha = min(1, (p - 0.45) / 0.35)
                for j in 0..<3 {
                    let k = Double(j)
                    let a = -2.2 + k * 2.1 + 0.15 * sin(t * 0.7 + k)
                    let d = 92 + 40 * ease + 6 * sin(t * 1.3 + k * 2)
                    let c = CGPoint(x: point.x + d * cos(a), y: point.y + d * sin(a))
                    let blink = sin(t * 1.9 + k * 2.4) > 0.94 ? 0.15 : 1.0
                    var e = ctx
                    e.opacity = eyesAlpha * (j == 2 ? max(0, (p - 0.7) / 0.3) : 1)
                    for dx in [-9.0, 9.0] {
                        let eye = CGRect(x: c.x + dx - 5, y: c.y - 7 * blink, width: 10, height: 14 * blink)
                        e.fill(Path(ellipseIn: eye.insetBy(dx: -3, dy: -3)), with: .color(Color.white.opacity(0.35)))
                        e.fill(Path(ellipseIn: eye), with: .color(.white))
                        let look = CGPoint(x: (point.x - c.x) / max(1, d) * 1.6, y: (point.y - c.y) / max(1, d) * 2.2)
                        let pupil = CGRect(x: c.x + dx - 2.6 + look.x, y: c.y - 3.6 * blink + look.y, width: 5.2, height: 7.2 * blink)
                        e.fill(Path(ellipseIn: pupil), with: .color(Color(red: 0.14, green: 0.1, blue: 0.3)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Глянцевый шарик (слоты коллекции, значок пасхалки)

struct GlossyOrb<Content: View>: View {
    let size: CGFloat
    var muted = false
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(
                colors: muted
                    ? [Color(red: 0.97, green: 0.97, blue: 1), Color(red: 0.91, green: 0.90, blue: 0.98), Color(red: 0.84, green: 0.83, blue: 0.95)]
                    : [Color(red: 0.97, green: 0.96, blue: 1), Color(red: 0.86, green: 0.83, blue: 1), Color(red: 0.72, green: 0.67, blue: 0.98)],
                center: UnitPoint(x: 0.38, y: 0.3), startRadius: size * 0.04, endRadius: size * 0.74))
            // светлый ободок, как у стеклянной бусины
            Circle().fill(RadialGradient(colors: [.white.opacity(0), .white.opacity(0.55)],
                                         center: .center, startRadius: size * 0.34, endRadius: size * 0.5))
            content
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.52, height: size * 0.26)
                .offset(y: -size * 0.28)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.95), lineWidth: max(1, size * 0.025)))
        .shadow(color: FunStyle.violet.opacity(muted ? 0.1 : 0.25), radius: size * 0.12, y: size * 0.06)
    }
}

/// Четырёхлучевая искорка.
struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let w = rect.width / 2, h = rect.height / 2
        let k: CGFloat = 0.18
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - h))
        p.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y), control: CGPoint(x: c.x + w * k, y: c.y - h * k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + h), control: CGPoint(x: c.x + w * k, y: c.y + h * k))
        p.addQuadCurve(to: CGPoint(x: c.x - w, y: c.y), control: CGPoint(x: c.x - w * k, y: c.y + h * k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - h), control: CGPoint(x: c.x - w * k, y: c.y - h * k))
        p.closeSubpath()
        return p
    }
}

private struct Twinkle: View {
    let color: Color
    let size: CGFloat
    let phase: Double
    let t: Double

    var body: some View {
        let k = 0.5 + 0.5 * sin(t * 2.6 + phase)
        SparkleShape()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(0.7 + 0.35 * k)
            .opacity(0.55 + 0.45 * k)
            .shadow(color: color.opacity(0.5), radius: 3)
    }
}

// MARK: - Маскот: добрый робот машет сердечком

/// Нарисован кодом (векторно, без картинок): покачивается, моргает, сердечко бьётся.
struct RobotMascot: View {
    private static let shell = LinearGradient(colors: [.white, Color(red: 0.89, green: 0.87, blue: 1), Color(red: 0.78, green: 0.74, blue: 0.98)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let purple = LinearGradient(colors: [Color(red: 0.74, green: 0.56, blue: 1), Color(red: 0.5, green: 0.3, blue: 0.92)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let cyan = Color(red: 0.32, green: 0.95, blue: 0.96)

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                let s = min(g.size.width / 130, g.size.height / 152)
                ZStack(alignment: .topLeading) {
                    Twinkle(color: Color(red: 0.62, green: 0.5, blue: 1), size: 18 * s, phase: 0, t: t).position(x: 14 * s, y: 22 * s)
                    Twinkle(color: Color(red: 0.62, green: 0.5, blue: 1), size: 11 * s, phase: 1.7, t: t).position(x: 34 * s, y: 50 * s)
                    accents(s).position(x: 14 * s, y: 102 * s)
                    robot(s, t: t).offset(y: 2.5 * s * sin(t * 2))
                }
            }
        }
    }

    private func accents(_ s: CGFloat) -> some View {
        ZStack {
            Capsule().fill(Color(red: 1, green: 0.84, blue: 0.2)).frame(width: 12 * s, height: 4 * s).rotationEffect(.degrees(-30)).offset(y: -6 * s)
            Capsule().fill(Color(red: 1, green: 0.84, blue: 0.2)).frame(width: 10 * s, height: 4 * s).rotationEffect(.degrees(15)).offset(x: 2 * s, y: 5 * s)
        }
    }

    @ViewBuilder
    private func robot(_ s: CGFloat, t: Double) -> some View {
        let blink = (t.truncatingRemainder(dividingBy: 3.4)) < 0.14
        ZStack(alignment: .topLeading) {
            // антенна
            Path { p in
                p.move(to: CGPoint(x: 82 * s, y: 40 * s))
                p.addLine(to: CGPoint(x: 88 * s, y: 15 * s))
            }
            .stroke(Color(red: 0.72, green: 0.7, blue: 0.86), style: StrokeStyle(lineWidth: 3.5 * s, lineCap: .round))
            Circle().fill(Self.purple)
                .overlay(Circle().fill(Color.white.opacity(0.7)).frame(width: 5 * s, height: 4 * s).offset(x: -2.5 * s, y: -3 * s))
                .frame(width: 17 * s, height: 17 * s)
                .shadow(color: Color(red: 0.6, green: 0.4, blue: 1).opacity(0.4 + 0.3 * sin(t * 3)), radius: 6 * s)
                .position(x: 89 * s, y: 12 * s)
            // корпус с фиолетовой кнопкой
            RoundedRectangle(cornerRadius: 20 * s, style: .continuous).fill(Self.shell)
                .frame(width: 70 * s, height: 44 * s)
                .shadow(color: FunStyle.violet.opacity(0.2), radius: 6 * s, y: 3 * s)
                .position(x: 90 * s, y: 132 * s)
            Circle().stroke(Self.purple, lineWidth: 4 * s)
                .background(Circle().fill(Color(red: 0.85, green: 0.78, blue: 1)))
                .frame(width: 17 * s, height: 17 * s)
                .position(x: 110 * s, y: 135 * s)
            // голова
            RoundedRectangle(cornerRadius: 34 * s, style: .continuous).fill(Self.shell)
                .overlay(RoundedRectangle(cornerRadius: 34 * s, style: .continuous).stroke(Color.white, lineWidth: 1.5 * s))
                .frame(width: 96 * s, height: 82 * s)
                .shadow(color: FunStyle.violet.opacity(0.25), radius: 10 * s, y: 5 * s)
                .position(x: 78 * s, y: 77 * s)
            // ушко
            RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
                .fill(Color(red: 0.76, green: 0.72, blue: 0.96))
                .frame(width: 9 * s, height: 26 * s)
                .position(x: 30 * s, y: 78 * s)
            // экран-лицо
            RoundedRectangle(cornerRadius: 24 * s, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.14, green: 0.13, blue: 0.22), Color(red: 0.03, green: 0.03, blue: 0.07)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    Ellipse().fill(Color.white.opacity(0.14)).frame(width: 34 * s, height: 12 * s)
                        .rotationEffect(.degrees(-12)).offset(x: -16 * s, y: -15 * s)
                )
                .frame(width: 76 * s, height: 56 * s)
                .position(x: 80 * s, y: 79 * s)
            // глаза-улыбки
            ForEach([63.0, 97.0], id: \.self) { x in
                ZStack {
                    eyeArc(s).blur(radius: 3 * s).opacity(0.9)
                    eyeArc(s)
                }
                .scaleEffect(x: 1, y: blink ? 0.2 : 1)
                .position(x: x * s, y: 82 * s)
            }
            // ручка с сердечком
            Path { p in
                p.move(to: CGPoint(x: 58 * s, y: 132 * s))
                p.addQuadCurve(to: CGPoint(x: 34 * s, y: 122 * s), control: CGPoint(x: 42 * s, y: 136 * s))
            }
            .stroke(Self.shell, style: StrokeStyle(lineWidth: 11 * s, lineCap: .round))
            Image(systemName: "heart.fill")
                .font(.system(size: 22 * s, weight: .bold))
                .foregroundStyle(Self.purple)
                .shadow(color: Color(red: 0.6, green: 0.4, blue: 1).opacity(0.45), radius: 4 * s)
                .scaleEffect(1 + 0.08 * max(0, sin(t * 6)))
                .rotationEffect(.degrees(-18 + 6 * sin(t * 2)))
                .position(x: 30 * s, y: 114 * s)
        }
    }

    private func eyeArc(_ s: CGFloat) -> some View {
        Path { p in
            p.addArc(center: CGPoint(x: 10 * s, y: 12 * s), radius: 9 * s, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        }
        .stroke(Self.cyan, style: StrokeStyle(lineWidth: 5 * s, lineCap: .round))
        .frame(width: 20 * s, height: 16 * s)
    }
}

// MARK: - Сундук с сокровищем: «Все секреты найдены!»

struct TreasureChest: View {
    private static let purple = LinearGradient(colors: [Color(red: 0.7, green: 0.55, blue: 1), Color(red: 0.46, green: 0.3, blue: 0.88)],
                                               startPoint: .top, endPoint: .bottom)
    private static let strap = Color(red: 0.8, green: 0.72, blue: 1)

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                let s = min(g.size.width / 92, g.size.height / 84)
                ZStack(alignment: .topLeading) {
                    // сияние из сундука
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 1, green: 0.95, blue: 0.6).opacity(0.9), Color(red: 1, green: 0.9, blue: 0.5).opacity(0)],
                                             center: .center, startRadius: 2, endRadius: 34 * s))
                        .frame(width: 70 * s, height: 70 * s)
                        .scaleEffect(0.92 + 0.08 * sin(t * 2.4))
                        .position(x: 46 * s, y: 36 * s)
                    // откинутая крышка
                    RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.4, blue: 0.95), Color(red: 0.38, green: 0.24, blue: 0.78)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 3 * s).fill(Self.strap).frame(width: 6 * s).offset(x: -18 * s))
                        .overlay(RoundedRectangle(cornerRadius: 3 * s).fill(Self.strap).frame(width: 6 * s).offset(x: 18 * s))
                        .frame(width: 62 * s, height: 24 * s)
                        .rotationEffect(.degrees(-10), anchor: .bottom)
                        .position(x: 44 * s, y: 26 * s)
                    // звезда
                    Image(systemName: "star.fill")
                        .font(.system(size: 30 * s, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.5), Color(red: 1, green: 0.72, blue: 0.18)],
                                                        startPoint: .top, endPoint: .bottom))
                        .shadow(color: Color(red: 1, green: 0.8, blue: 0.2).opacity(0.8), radius: 7 * s)
                        .offset(y: -2.5 * s * sin(t * 2.4))
                        .position(x: 46 * s, y: 34 * s)
                    // короб
                    RoundedRectangle(cornerRadius: 10 * s, style: .continuous)
                        .fill(Self.purple)
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: 4 * s).fill(Self.strap).frame(height: 7 * s).padding(.horizontal, 2 * s)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 3 * s).fill(Self.strap.opacity(0.8)).frame(width: 6 * s).offset(x: -21 * s))
                        .overlay(RoundedRectangle(cornerRadius: 3 * s).fill(Self.strap.opacity(0.8)).frame(width: 6 * s).offset(x: 21 * s))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4 * s).fill(Color(red: 0.95, green: 0.92, blue: 1))
                                .overlay(Circle().fill(FunStyle.violet).frame(width: 4 * s, height: 4 * s))
                                .frame(width: 13 * s, height: 15 * s).offset(y: 2 * s)
                        )
                        .frame(width: 66 * s, height: 38 * s)
                        .shadow(color: FunStyle.violet.opacity(0.3), radius: 6 * s, y: 3 * s)
                        .position(x: 46 * s, y: 60 * s)
                    Twinkle(color: Color(red: 1, green: 0.84, blue: 0.25), size: 13 * s, phase: 0.4, t: t).position(x: 10 * s, y: 18 * s)
                    Twinkle(color: Color(red: 0.7, green: 0.6, blue: 1), size: 11 * s, phase: 2.1, t: t).position(x: 82 * s, y: 12 * s)
                    Twinkle(color: Color(red: 1, green: 0.84, blue: 0.25), size: 10 * s, phase: 3.3, t: t).position(x: 84 * s, y: 52 * s)
                    Twinkle(color: Color(red: 0.7, green: 0.6, blue: 1), size: 8 * s, phase: 4.4, t: t).position(x: 6 * s, y: 62 * s)
                }
            }
        }
    }
}
