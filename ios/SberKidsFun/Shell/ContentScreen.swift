import SwiftUI

private struct PullOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Лента «Контент» со стандартным pull-to-refresh.
/// Единственная интеграция с приколами — `FunLayer.shared.reportPull(distance:)`:
/// лента сообщает, насколько её перетянули. Остальное делает слой.
@MainActor
final class PullModel: ObservableObject {
    @Published var refreshing = false

    func handle(_ y: CGFloat) {
        FunLayer.shared.reportPull(distance: Double(max(0, y)))
        if y > 80 && !refreshing {
            withAnimation { refreshing = true }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation { self?.refreshing = false }
            }
        }
    }
}

struct ContentScreen: View {
    @StateObject private var pull = PullModel()
    @State private var chip = "Все"
    private let chips = ["Все", "Деньги", "Безопасность", "Игры", "Мультики"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            GeometryReader { g in
                Color.clear.preference(key: PullOffsetKey.self, value: g.frame(in: .named("feed")).minY)
            }
            .frame(height: 0)

            if pull.refreshing {
                ProgressView().padding(.top, 8).transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Контент").font(Theme.font(30, .heavy)).foregroundColor(Theme.ink).padding(.top, 8)

                HeroCard()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ContentTile(title: "Квиз дня", icon: "questionmark.circle.fill", colors: [Theme.blue, Theme.sky])
                        ContentTile(title: "Песни", icon: "music.note", colors: [Color(red: 1, green: 0.6, blue: 0.8), Theme.lilac])
                        ContentTile(title: "Игры", icon: "gamecontroller.fill", colors: [Theme.mint, Theme.lime])
                        ContentTile(title: "Сказки", icon: "book.fill", colors: [Color(red: 1, green: 0.8, blue: 0.4), Color(red: 1, green: 0.6, blue: 0.4)])
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips, id: \.self) { c in
                            Text(c)
                                .font(Theme.font(14, .semibold))
                                .foregroundColor(Theme.ink)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Capsule().fill(c == chip ? Color.white : Color.white.opacity(0.55)))
                                .overlay(Capsule().stroke(c == chip ? Theme.ink : .clear, lineWidth: 1.5))
                                .onTapGesture { chip = c }
                        }
                    }
                }

                ForEach(FeedItem.samples) { item in
                    FeedCard(item: item)
                }
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 16)
        }
        .coordinateSpace(name: "feed")
        .onPreferenceChange(PullOffsetKey.self) { [pull] y in
            MainActor.assumeIsolated { pull.handle(y) }
        }
        .background(LinearGradient(colors: [Theme.lavender.opacity(0.6), Theme.bg], startPoint: .top, endPoint: .center).ignoresSafeArea())
    }

}

private struct HeroCard: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.45, blue: 0.7), Theme.violet],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "sparkles")
                .font(.system(size: 90))
                .foregroundColor(.white.opacity(0.35))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(18)
            VStack(alignment: .leading, spacing: 6) {
                Label("Видео", systemImage: "play.fill")
                    .font(Theme.font(12, .bold)).foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.25)))
                Text("Агент Kids: тайна копилки").font(Theme.font(22, .heavy)).foregroundColor(.white)
            }
            .padding(18)
        }
        .frame(height: 190)
    }
}

private struct ContentTile: View {
    let title: String
    let icon: String
    let colors: [Color]

    var body: some View {
        VStack(alignment: .leading) {
            Image(systemName: icon).font(.system(size: 30, weight: .bold)).foregroundColor(.white)
            Spacer()
            Text(title).font(Theme.font(14, .bold)).foregroundColor(.white)
        }
        .padding(12)
        .frame(width: 96, height: 110, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}

struct FeedItem: Identifiable {
    let id = UUID()
    let kind: String
    let title: String
    let icon: String
    let colors: [Color]
    let progress: Double
    let likes: String

    static let samples: [FeedItem] = [
        FeedItem(kind: "Курс", title: "Как копить на мечту и не сдаваться", icon: "banknote.fill",
                 colors: [Theme.limeSoft, Theme.mint], progress: 0.6, likes: "12 тыс"),
        FeedItem(kind: "Видео", title: "Почему нельзя говорить код из СМС", icon: "lock.shield.fill",
                 colors: [Theme.sky, Theme.lilac], progress: 0.2, likes: "31 тыс"),
        FeedItem(kind: "Курс", title: "Что такое вклад — объясняем на яблоках", icon: "leaf.fill",
                 colors: [Color(red: 1, green: 0.85, blue: 0.6), Color(red: 1, green: 0.7, blue: 0.7)], progress: 0, likes: "8 тыс"),
        FeedItem(kind: "Игра", title: "Хватит ли денег на поход в кино?", icon: "ticket.fill",
                 colors: [Theme.lavender, Color(red: 0.95, green: 0.75, blue: 0.95)], progress: 0.9, likes: "5 тыс"),
    ]
}

private struct FeedCard: View {
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: item.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: item.icon).font(.system(size: 54, weight: .bold)).foregroundColor(.white.opacity(0.9))
            }
            .frame(height: 150)
            Label(item.kind, systemImage: item.kind == "Видео" ? "play.circle.fill" : "graduationcap.fill")
                .font(Theme.font(12, .semibold)).foregroundColor(Theme.secondary)
            Text(item.title).font(Theme.font(17, .bold)).foregroundColor(Theme.ink)
            HStack {
                Label(item.likes, systemImage: "heart.fill").font(Theme.font(12)).foregroundColor(Theme.secondary)
                Spacer()
                if item.progress > 0 {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.bg).frame(width: 90, height: 6)
                        Capsule().fill(Theme.violet).frame(width: 90 * item.progress, height: 6)
                    }
                }
            }
        }
        .padding(12)
        .card()
    }
}
