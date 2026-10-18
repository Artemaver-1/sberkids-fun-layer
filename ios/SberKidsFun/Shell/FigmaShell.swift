import SwiftUI
import UIKit

// Демо-оболочка: экраны СберKids 1:1 из макетов Figma организаторов (tools/build_shell_assets.py).
// Каждый экран — картинка макета, кнопки — невидимые зоны поверх неё.
// Это только «приложение вокруг» для демонстрации: в продукт уходит модуль FunLayer.

@MainActor
enum FigmaAssets {
    private static var cache: [String: UIImage] = [:]

    static func image(_ name: String) -> UIImage? {
        if let img = cache[name] { return img }
        let img = Bundle.main.path(forResource: name, ofType: nil).flatMap(UIImage.init(contentsOfFile:))
        cache[name] = img
        return img
    }

    /// Верхняя строка макета — ею заливается область под статус-баром (градиент совпадает).
    static func topStrip(_ name: String) -> UIImage? {
        let key = name + "#top"
        if let img = cache[key] { return img }
        guard let cg = image(name)?.cgImage, let row = cg.cropping(to: CGRect(x: 0, y: 0, width: cg.width, height: 2)) else { return nil }
        let img = UIImage(cgImage: row)
        cache[key] = img
        return img
    }
}

enum ShellAction: Equatable {
    case push(PushedScreen)
    case pop
    case profileTab(Int)
    case debug
}

/// Кликабельная зона в пикселях макета (экспорт 2x).
struct Hotspot {
    let rect: CGRect
    let action: ShellAction

    init(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ action: ShellAction) {
        rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        self.action = action
    }
}

struct ScreenSpec {
    let image: String
    let top: Color
    let bottom: Color
    let hotspots: [Hotspot]

    static let back = Hotspot(0, 0, 200, 170, .pop)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

enum Screens {
    static let main = ScreenSpec(image: "screen_main.jpg", top: Color(hex: 0xF1F5F7), bottom: Color(hex: 0xF1F5F8), hotspots: [
        Hotspot(30, 20, 180, 160, .push(.profile)),
        Hotspot(192, 750, 480, 995, .push(.transfer)),
        Hotspot(500, 750, 780, 995, .push(.top_up)),
        Hotspot(32, 1300, 748, 1945, .push(.history)),
        Hotspot(32, 1990, 748, 2120, .push(.history)),
    ])
    static let tasks = ScreenSpec(image: "screen_tasks.jpg", top: Color(hex: 0xC7D3FA), bottom: Color(hex: 0xEDF1F4), hotspots: [
        Hotspot(30, 20, 180, 160, .push(.profile)),
        Hotspot(60, 430, 680, 580, .push(.task_create)),
        Hotspot(70, 830, 650, 1000, .push(.task_story)),
    ])
    static let content = ScreenSpec(image: "screen_content.jpg", top: Color(hex: 0xE1D6FA), bottom: Color(hex: 0xF1F5F8), hotspots: [
        Hotspot(20, 10, 160, 140, .push(.profile)),
        Hotspot(55, 200, 665, 740, .push(.content_money)),
        Hotspot(0, 790, 720, 1010, .push(.content_cyber)),
        Hotspot(40, 1660, 680, 2230, .push(.content_snail)),
    ])
    static let piggy = ScreenSpec(image: "screen_piggy.jpg", top: Color(hex: 0xF5D3C3), bottom: Color(hex: 0xF1F5F8), hotspots: [
        Hotspot(30, 20, 180, 160, .push(.profile)),
        Hotspot(40, 740, 680, 1280, .push(.piggy_new)),
        Hotspot(40, 1560, 680, 1840, .push(.piggy_goal)),
    ])
    static let profile = ScreenSpec(image: "screen_profile.jpg", top: Color(hex: 0xD9F9B7), bottom: Color(hex: 0xF1F5F8), hotspots: [
        ScreenSpec.back,
        Hotspot(400, 780, 760, 920, .profileTab(1)),
    ])
    static let settings = ScreenSpec(image: "screen_settings.jpg", top: Color(hex: 0xD9F9B7), bottom: Color(hex: 0xF1F5F8), hotspots: [
        ScreenSpec.back,
        Hotspot(20, 780, 390, 920, .profileTab(0)),
        Hotspot(40, 1170, 750, 1330, .push(.design)),
        Hotspot(100, 2190, 680, 2324, .debug),   // «Версия приложения» — долгое нажатие
    ])

    static func pushed(_ s: PushedScreen) -> ScreenSpec? {
        func spec(_ name: String, _ top: UInt32, _ bottom: UInt32) -> ScreenSpec {
            ScreenSpec(image: "screen_\(name).jpg", top: Color(hex: top), bottom: Color(hex: bottom), hotspots: [ScreenSpec.back])
        }
        switch s {
        case .design: return spec("design", 0xF1F4F8, 0xF1F5F8)
        case .history: return spec("history", 0xF1F5F8, 0xF1F5F8)
        case .content_money: return spec("content_money", 0x4E6B97, 0xF1F5F8)
        case .content_cyber: return spec("content_cyber", 0x2B1771, 0xF1F5F8)
        case .content_snail: return spec("content_snail", 0x13A1B8, 0x977C72)
        case .task_create: return spec("task_create", 0xC7D3FA, 0xF1F5F8)
        case .task_story: return spec("task_story", 0x0A185F, 0x4B3BA9)
        case .piggy_new: return spec("piggy_new", 0xF5D3C3, 0xF1F5F8)
        case .piggy_goal: return spec("piggy_goal", 0x23B23E, 0x23B23E)
        case .profile, .transfer, .top_up, .debug: return nil
        }
    }
}

/// Экран-макет: картинка в прокрутке + невидимые кнопки.
struct FigmaScreen: View {
    let spec: ScreenSpec
    var bottomInset: CGFloat = 0
    var onPull: (@MainActor (CGFloat) -> Void)?
    let onAction: (ShellAction) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let image = FigmaAssets.image(spec.image)
            let scale = image.map { width / $0.size.width } ?? 1
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if let onPull {
                        PullReader(onPull: onPull).frame(height: 0)
                    }
                    ZStack(alignment: .topLeading) {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .frame(width: width, height: image.size.height * scale)
                        }
                        ForEach(Array(spec.hotspots.enumerated()), id: \.offset) { _, spot in
                            hotspot(spot, scale: scale)
                        }
                    }
                    spec.bottom.frame(height: bottomInset)
                }
            }
            .background(
                VStack(spacing: 0) {
                    if let strip = FigmaAssets.topStrip(spec.image) {
                        Image(uiImage: strip).resizable()
                    } else {
                        spec.top
                    }
                    spec.bottom
                }
                .ignoresSafeArea()
            )
        }
    }

    @ViewBuilder
    private func hotspot(_ spot: Hotspot, scale: CGFloat) -> some View {
        let area = Color.clear
            .contentShape(Rectangle())
            .frame(width: spot.rect.width * scale, height: spot.rect.height * scale)
            .offset(x: spot.rect.minX * scale, y: spot.rect.minY * scale)
        if spot.action == .debug {
            // «Версия приложения»: быстрые тапы — пасхалка с роботами, долгое нажатие — меню разработчика.
            // В СберKids это одна строка в обработчике нажатия: FunLayer.shared.reportTap("settings.version")
            area.onTapGesture { FunLayer.shared.reportTap("settings.version") }
                .onLongPressGesture(minimumDuration: 1.0) { onAction(spot.action) }
        } else {
            area.onTapGesture { onAction(spot.action) }
                .accessibilityAddTraits(.isButton)
        }
    }
}

/// Таб-бар из макета (активная вкладка — своя картинка) с зонами нажатия.
struct FigmaTabBar: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        let key: String = {
            switch router.tab {
            case .main, .paw: return "main"
            case .piggy: return "piggy"
            case .tasks: return "tasks"
            case .content: return "content"
            }
        }()
        if let image = FigmaAssets.image("tabbar_\(key).png") {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .overlay(
                    HStack(spacing: 0) {
                        ForEach(AppTab.allCases, id: \.self) { tab in
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { if tab != .paw { router.tab = tab } }
                                .accessibilityLabel(tab.title)
                        }
                    }
                    .padding(.horizontal, 12)
                )
        }
    }
}

@MainActor
final class PullModel: ObservableObject {
    func handle(_ y: CGFloat) {
        FunLayer.shared.reportPull(distance: Double(max(0, y)))
    }
}
