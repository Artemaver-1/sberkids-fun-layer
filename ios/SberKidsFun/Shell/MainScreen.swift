import SwiftUI

/// Главный экран по макету: карта с балансом, быстрые действия, баннер, история.
/// Данные условные — прототип не работает с настоящими счетами.
struct MainScreen: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                HStack {
                    Button { router.push(.profile) } label: { AvatarView() }
                        .accessibilityLabel("Профиль")
                    Spacer()
                    CircleIconButton(systemName: "bell.fill")
                }
                .padding(.top, 8)

                BalanceCard()

                HStack(spacing: 10) {
                    QuickAction(title: "QR", icon: "qrcode", tint: Theme.lilac) {}
                    QuickAction(title: "Скинуть\nденег", icon: "arrow.right", tint: Theme.sky) { router.push(.transfer) }
                    QuickAction(title: "Пополнить\nмобилку", icon: "iphone", tint: Theme.mint) { router.push(.top_up) }
                }

                PromoBanner()
                HistoryCard()
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 16)
        }
        .background(
            LinearGradient(colors: [Theme.limeSoft, Theme.bg], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
    }
}

private struct BalanceCard: View {
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.86, green: 0.98, blue: 0.4), Color(red: 0.6, green: 0.9, blue: 0.3)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                // «стикеры» на карте
                Circle().fill(Color.white.opacity(0.35)).frame(width: 70).offset(x: -90, y: -20)
                Circle().fill(Theme.violet.opacity(0.35)).frame(width: 40).offset(x: 70, y: 30)
                Image(systemName: "star.fill").font(.system(size: 26)).foregroundColor(.white.opacity(0.8)).offset(x: 95, y: -35)
                Image(systemName: "heart.fill").font(.system(size: 20)).foregroundColor(Theme.red.opacity(0.6)).offset(x: -40, y: 38)
                Image(systemName: "bolt.fill").font(.system(size: 22)).foregroundColor(Theme.ink.opacity(0.6)).offset(x: 20, y: -30)
                Text("СберKids").font(Theme.font(15, .heavy)).foregroundColor(Theme.ink.opacity(0.75))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(14)
            }
            .frame(height: 150)
            .rotation3DEffect(.degrees(4), axis: (x: 0, y: 1, z: 0))
            .padding(.horizontal, 30)
            .padding(.top, 6)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("7 932").font(Theme.font(28, .heavy)).foregroundColor(Theme.ink)
                Text(",04 ₽").font(Theme.font(22, .bold)).foregroundColor(Theme.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Text("256").font(Theme.font(16, .bold))
                    Image(systemName: "star.circle.fill").foregroundColor(Theme.green)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(Theme.limeSoft))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .card(20)

            HStack(spacing: 6) {
                Capsule().fill(Theme.secondary.opacity(0.6)).frame(width: 18, height: 5)
                Circle().fill(Theme.secondary.opacity(0.3)).frame(width: 5, height: 5)
                Circle().fill(Theme.secondary.opacity(0.3)).frame(width: 5, height: 5)
            }
        }
    }
}

private struct QuickAction: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Theme.font(14, .semibold))
                    .foregroundColor(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                HStack {
                    Spacer()
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Theme.ink)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .card(20)
        }
        .buttonStyle(.plain)
    }
}

private struct PromoBanner: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Узнай свои сильные стороны").font(Theme.font(17, .bold)).foregroundColor(.white)
                Text("с тестом по профориентации").font(Theme.font(12)).foregroundColor(.white.opacity(0.85))
            }
            Spacer()
            ZStack {
                Ellipse().fill(Color(red: 0.98, green: 0.75, blue: 0.4)).frame(width: 76, height: 20).offset(y: 8)
                Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.7, blue: 0.85), Theme.violet],
                                             startPoint: .top, endPoint: .bottom)).frame(width: 48, height: 48)
                Ellipse().stroke(Color(red: 0.98, green: 0.85, blue: 0.5), lineWidth: 4).frame(width: 80, height: 22).offset(y: 6)
            }
            .frame(width: 84)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.42, blue: 0.95), Theme.lilac],
                                 startPoint: .leading, endPoint: .trailing)))
    }
}

private struct HistoryCard: View {
    private let rows: [(String, String, String, String, Color)] = [
        ("cart.fill", "Товары для дома", "Маркетплейс", "−2 292 ₽", Theme.lilac),
        ("fork.knife", "Обед в школе", "Столовая", "−186 ₽", Theme.mint),
        ("gift.fill", "От бабушки", "Перевод", "+500 ₽", Theme.limeSoft),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("История").font(Theme.font(22, .heavy)).foregroundColor(Theme.ink)
            ForEach(rows, id: \.1) { icon, title, subtitle, amount, tint in
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.ink)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(tint))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Theme.font(15, .semibold)).foregroundColor(Theme.ink)
                        Text(subtitle).font(Theme.font(12)).foregroundColor(Theme.secondary)
                    }
                    Spacer()
                    Text(amount).font(Theme.font(15, .bold))
                        .foregroundColor(amount.hasPrefix("+") ? Theme.green : Theme.ink)
                }
            }
            Text("Посмотреть историю")
                .font(Theme.font(15, .semibold))
                .foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.bg))
        }
        .padding(16)
        .card()
    }
}
