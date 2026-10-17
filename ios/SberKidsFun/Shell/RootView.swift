import SwiftUI

enum AppTab: String, CaseIterable {
    case main, piggy, paw, tasks, content

    var title: String {
        switch self {
        case .main: return "Главный"
        case .piggy: return "Копилки"
        case .paw: return ""
        case .tasks: return "Дела"
        case .content: return "Контент"
        }
    }

    var icon: String {
        switch self {
        case .main: return "house.fill"
        case .piggy: return "banknote.fill"
        case .paw: return "pawprint.fill"
        case .tasks: return "checkmark.circle.fill"
        case .content: return "sparkles"
        }
    }
}

enum PushedScreen: String, Equatable {
    case profile, transfer, top_up, debug
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var tab: AppTab = .main
    @Published private(set) var stack: [PushedScreen] = []

    /// Идентификатор видимого экрана — его получает слой приколов.
    var screenId: String { stack.last?.rawValue ?? tab.rawValue }

    func push(_ s: PushedScreen) { withAnimation(.easeInOut(duration: 0.28)) { stack.append(s) } }
    func pop() { withAnimation(.easeInOut(duration: 0.28)) { _ = stack.popLast() } }
}

struct RootView: View {
    @StateObject private var router = AppRouter()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            Group {
                switch router.tab {
                case .main, .paw: MainScreen()
                case .piggy: PiggyScreen()
                case .tasks: TasksScreen()
                case .content: ContentScreen()
                }
            }

            VStack {
                Spacer()
                TabBar()
            }
            .ignoresSafeArea(.keyboard)

            if let top = router.stack.last {
                pushed(top)
                    .background(Theme.bg.ignoresSafeArea())
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .environmentObject(router)
        .background(WindowReader { FunLayer.shared.install(on: $0) })
        .onAppear { FunLayer.shared.setScreen(router.screenId) }
        .onChange(of: router.screenId) { FunLayer.shared.setScreen($0) }
    }

    @ViewBuilder private func pushed(_ s: PushedScreen) -> some View {
        switch s {
        case .profile: ProfileScreen()
        case .transfer: MoneyFormScreen(title: "Перевод", field: "Кому", placeholder: "Номер телефона", action: "Перевести")
        case .top_up: MoneyFormScreen(title: "Пополнить мобилку", field: "Номер", placeholder: "+7", action: "Пополнить")
        case .debug: DebugScreen()
        }
    }
}

struct TabBar: View {
    @EnvironmentObject private var router: AppRouter
    @State private var pawBounce = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                if tab == .paw {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) { pawBounce.toggle() }
                    } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Theme.ink)
                            .frame(width: 58, height: 58)
                            .background(Circle().fill(LinearGradient(colors: [Theme.lilac, Theme.sky],
                                                                     startPoint: .top, endPoint: .bottom)))
                            .scaleEffect(pawBounce ? 1.08 : 1)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Помощник")
                } else {
                    Button { router.tab = tab } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon).font(.system(size: 20, weight: .semibold))
                            Text(tab.title).font(Theme.font(11, .medium))
                        }
                        .foregroundColor(router.tab == tab ? Theme.green : Theme.secondary)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 16, y: 4)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}
