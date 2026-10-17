import FunLayerCore
import SwiftUI

/// Скрытое меню для защиты (долгое нажатие на версию в профиле):
/// переключение конфигов «как будто CDN», загрузка с настоящего CDN, ручной запуск,
/// сброс прогресса и калибровка жеста ладони.
struct DebugScreen: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var fun = FunLayer.shared
    @AppStorage("fun_layer.debug.url") private var urlText = DebugScreen.defaultURL

    static let defaultURL = "https://YOUR_GITHUB_LOGIN.github.io/sberkids-fun-layer/fun-layer/v1/config.json"

    private let presets: [(String, String)] = [
        ("config", "Осень (по умолчанию)"),
        ("config-winter", "Зима: снег вместо пузырей"),
        ("config-party", "Праздник: золотые пузыри 50%"),
        ("config-off", "Рубильник: слой выключен"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Меню разработчика") { router.pop() }.padding(.vertical, 8)
            List {
                Section(header: Text("Активный конфиг")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fun.config?.configId ?? "выключен").font(Theme.font(17, .bold))
                        Text(fun.source.title).font(Theme.font(12)).foregroundColor(Theme.secondary)
                    }
                    ForEach(fun.warnings, id: \.self) { w in
                        Label(w, systemImage: "exclamationmark.triangle.fill").font(Theme.font(12)).foregroundColor(.orange)
                    }
                }

                Section(header: Text("Встроенные пресеты (офлайн-копии CDN)")) {
                    ForEach(presets, id: \.0) { name, title in
                        Button {
                            fun.useBundled(name)
                        } label: {
                            HStack {
                                Text(title).foregroundColor(Theme.ink)
                                Spacer()
                                if fun.source == .bundled(name) { Image(systemName: "checkmark").foregroundColor(Theme.green) }
                            }
                        }
                    }
                }

                Section(header: Text("CDN (без релиза приложения)")) {
                    TextField("https://…/config.json", text: $urlText)
                        .font(Theme.font(13))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                    Button {
                        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespaces)) else { return }
                        Task { await fun.loadRemote(url) }
                    } label: {
                        HStack {
                            Text("Загрузить конфиг с CDN")
                            if fun.isLoadingRemote { Spacer(); ProgressView() }
                        }
                    }
                }

                Section(header: Text("Пасхалки")) {
                    ForEach(fun.config?.eggs ?? []) { egg in
                        Button {
                            router.pop()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { fun.forcePlay(egg.id) }
                        } label: {
                            HStack {
                                EggBadge(pictogram: egg.pictogram, size: 34)
                                VStack(alignment: .leading) {
                                    Text(egg.title).foregroundColor(Theme.ink)
                                    Text("\(egg.screen) · \(egg.triggerKinds.map(\.rawValue).joined(separator: " / "))")
                                        .font(Theme.font(12)).foregroundColor(Theme.secondary)
                                }
                                Spacer()
                                if fun.engine?.progress.isFound(egg.id) == true {
                                    Image(systemName: "checkmark.seal.fill").foregroundColor(Theme.green)
                                }
                            }
                        }
                    }
                    Button("Сбросить прогресс", role: .destructive) { fun.resetProgress() }
                }

                Section(header: Text("Калибровка ладони"),
                        footer: Text("Положи ладонь на экран: видно число касаний и максимальный радиус пятна. По этим цифрам подбираются minTouches и minRadius в конфиге.")) {
                    HStack {
                        Text("Касаний: \(fun.calibration.touches)")
                        Spacer()
                        Text(String(format: "Радиус: %.0f pt", fun.calibration.radius))
                    }
                    .font(Theme.font(15, .semibold))
                }
            }
            .listStyle(.insetGrouped)
        }
        .onAppear { fun.calibrating = true }
        .onDisappear { fun.calibrating = false }
    }
}
