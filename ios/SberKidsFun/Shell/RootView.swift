import SwiftUI

enum AppTab: String, CaseIterable {
    case main, piggy, paw, tasks, content

    var title: String {
        switch self {
        case .main: return "Главный"
        case .piggy: return "Копилки"
        case .paw: return "Помощник"
        case .tasks: return "Дела"
        case .content: return "Контент"
        }
    }
}

enum PushedScreen: String, Equatable {
    case profile, transfer, top_up, debug, history, design
    case content_money, content_cyber, content_snail
    case task_create, task_story
    case piggy_new, piggy_goal

    /// Идентификатор экрана для слоя приколов.
    var screenId: String {
        switch self {
        case .profile, .transfer, .top_up, .debug, .history, .design: return rawValue
        case .content_money, .content_cyber, .content_snail: return "content_detail"
        case .task_create, .task_story: return "tasks_detail"
        case .piggy_new, .piggy_goal: return "piggy_detail"
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var tab: AppTab = .main
    @Published private(set) var stack: [PushedScreen] = []
    @Published var profileTab = 0

    /// Идентификатор видимого экрана — его получает слой приколов.
    var screenId: String {
        if let top = stack.last {
            return top == .profile && profileTab == 1 ? "settings" : top.screenId
        }
        return tab == .paw ? AppTab.main.rawValue : tab.rawValue
    }

    func push(_ s: PushedScreen) {
        if s == .profile { profileTab = 0 }
        withAnimation(.easeInOut(duration: 0.28)) { stack.append(s) }
    }

    func pop() { withAnimation(.easeInOut(duration: 0.28)) { _ = stack.popLast() } }

    func perform(_ action: ShellAction) {
        switch action {
        case .push(let s): push(s)
        case .pop: pop()
        case .profileTab(let i): withAnimation(.easeInOut(duration: 0.2)) { profileTab = i }
        case .debug: push(.debug)
        }
    }
}

struct RootView: View {
    @StateObject private var router = AppRouter()
    @StateObject private var pull = PullModel()

    var body: some View {
        GeometryReader { geo in
            let tabInset = geo.size.width * 264 / 720 * 0.9
            ZStack {
                Theme.bg.ignoresSafeArea()

                Group {
                    switch router.tab {
                    case .main, .paw:
                        FigmaScreen(spec: Screens.main, bottomInset: tabInset, onAction: router.perform)
                    case .piggy:
                        FigmaScreen(spec: Screens.piggy, bottomInset: tabInset, onAction: router.perform)
                    case .tasks:
                        FigmaScreen(spec: Screens.tasks, bottomInset: tabInset, onAction: router.perform)
                    case .content:
                        FigmaScreen(spec: Screens.content, bottomInset: tabInset,
                                    onPull: { [pull] in pull.handle($0) }, onAction: router.perform)
                    }
                }
                .id(router.tab)

                VStack(spacing: 0) {
                    Spacer()
                    FigmaTabBar()
                        .padding(.bottom, max(0, geo.safeAreaInsets.bottom - 18))
                        .background(
                            LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg.opacity(0.95), Theme.bg],
                                           startPoint: .top, endPoint: .bottom)
                                .padding(.top, 40)
                        )
                }
                .ignoresSafeArea(edges: .bottom)

                if let top = router.stack.last {
                    pushed(top)
                        .background(Theme.bg.ignoresSafeArea())
                        .transition(.move(edge: .trailing))
                        .zIndex(1)
                }
            }
        }
        .environmentObject(router)
        .background(WindowReader { FunLayer.shared.install(on: $0) })
        .onAppear {
            // Аргументы запуска для проверки экранов на устройстве: -tab content, -push profile
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-tab"), i + 1 < args.count, let t = AppTab(rawValue: args[i + 1]) { router.tab = t }
            if let i = args.firstIndex(of: "-push"), i + 1 < args.count, let p = PushedScreen(rawValue: args[i + 1]) { router.push(p) }
            if args.contains("-settings") { router.profileTab = 1 }
            FunLayer.shared.setScreen(router.screenId)
        }
        .onChange(of: router.screenId) { FunLayer.shared.setScreen($0) }
    }

    @ViewBuilder private func pushed(_ s: PushedScreen) -> some View {
        switch s {
        case .profile:
            FigmaScreen(spec: router.profileTab == 0 ? Screens.profile : Screens.settings, onAction: router.perform)
                .id(router.profileTab)
        case .transfer:
            MoneyFormScreen(title: "Перевод", field: "Кому", placeholder: "Номер телефона", action: "Перевести")
        case .top_up:
            MoneyFormScreen(title: "Пополнить мобилку", field: "Номер", placeholder: "+7", action: "Пополнить")
        case .debug:
            DebugScreen()
        default:
            if let spec = Screens.pushed(s) {
                FigmaScreen(spec: spec, onAction: router.perform)
            }
        }
    }
}
