import FunLayerCore
import SwiftUI

struct ProfileScreen: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var fun = FunLayer.shared

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Профиль") { router.pop() }
                .padding(.top, 8)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    AvatarView(size: 104)
                        .padding(6)
                        .background(Circle().stroke(Theme.actionGradient, lineWidth: 4))
                        .padding(.top, 12)
                    Text("Юный исследователь").font(Theme.font(24, .heavy)).foregroundColor(Theme.ink)
                    Text("Уровень 3 · 12 дел выполнено")
                        .font(Theme.font(13, .semibold)).foregroundColor(Theme.ink)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.limeSoft))

                    VStack(spacing: 0) {
                        row("Мои достижения", icon: "rosette", tint: Theme.lilac, value: "7")
                        Divider().padding(.leading, 62)
                        row("Тема оформления", icon: "paintpalette.fill", tint: Theme.sky, value: "Лайм")
                        Divider().padding(.leading, 62)
                        row("Для родителей", icon: "person.2.fill", tint: Theme.mint, value: nil)
                        Divider().padding(.leading, 62)
                        row("Поддержка", icon: "bubble.left.and.bubble.right.fill", tint: Theme.limeSoft, value: nil)
                    }
                    .card()

                    Text("Версия 1.0 (42)")
                        .font(Theme.font(12))
                        .foregroundColor(Theme.secondary)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        // скрытое меню для защиты: смена конфига CDN, ручной запуск, калибровка
                        .onLongPressGesture(minimumDuration: 1.0) { router.push(.debug) }
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(LinearGradient(colors: [Theme.lavender.opacity(0.7), Theme.bg], startPoint: .top, endPoint: .center).ignoresSafeArea())
    }

    private func row(_ title: String, icon: String, tint: Color, value: String?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.ink)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint))
            Text(title).font(Theme.font(16, .medium)).foregroundColor(Theme.ink)
            Spacer()
            if let value { Text(value).font(Theme.font(15)).foregroundColor(Theme.secondary) }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct PiggyScreen: View {
    private let goals: [(String, String, Double, String, Color)] = [
        ("Самокат", "bicycle", 0.72, "5 040 из 7 000 ₽", Theme.limeSoft),
        ("Наушники", "headphones", 0.35, "2 100 из 6 000 ₽", Theme.sky),
        ("Подарок маме", "gift.fill", 0.9, "1 800 из 2 000 ₽", Theme.lilac),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Копилки").font(Theme.font(30, .heavy)).foregroundColor(Theme.ink).padding(.top, 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text("16 158 ₽").font(Theme.font(32, .heavy)).foregroundColor(Theme.ink)
                    Text("Всего на копилках").font(Theme.font(13)).foregroundColor(Theme.secondary)
                    HStack {
                        Text("Годовой процент").font(Theme.font(14, .semibold))
                        Spacer()
                        Text("12%").font(Theme.font(14, .bold)).foregroundColor(Theme.green)
                    }
                    .padding(.top, 10)
                }
                .padding(18)
                .card()

                ForEach(goals, id: \.0) { title, icon, p, sub, tint in
                    HStack(spacing: 14) {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .semibold)).foregroundColor(Theme.ink)
                            .frame(width: 54, height: 54)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title).font(Theme.font(16, .bold)).foregroundColor(Theme.ink)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.bg)
                                    Capsule().fill(Theme.green).frame(width: g.size.width * p)
                                }
                            }
                            .frame(height: 7)
                            Text(sub).font(Theme.font(12)).foregroundColor(Theme.secondary)
                        }
                    }
                    .padding(14)
                    .card(20)
                }
                Text("+ Создать копилку")
                    .font(Theme.font(16, .bold)).foregroundColor(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.actionGradient))
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 16)
        }
        .background(LinearGradient(colors: [Color(red: 0.97, green: 0.93, blue: 0.7), Theme.bg], startPoint: .top, endPoint: .center).ignoresSafeArea())
    }
}

struct TasksScreen: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Дела").font(Theme.font(30, .heavy)).foregroundColor(Theme.ink).padding(.top, 8)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Начни делать дела").font(Theme.font(20, .heavy)).foregroundColor(Theme.ink)
                    Text("Выбери или придумай своё дело и выполни его за награду")
                        .font(Theme.font(13)).foregroundColor(Theme.secondary)
                    Text("За дело!")
                        .font(Theme.font(16, .bold)).foregroundColor(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.actionGradient))
                        .padding(.top, 6)
                }
                .padding(18)
                .card()

                Text("Чем заняться").font(Theme.font(20, .heavy)).foregroundColor(Theme.ink)
                taskRow("Собраться в школу", icon: "bag.fill", tint: Theme.sky)
                HStack(spacing: 10) {
                    tile("Отмыть стену от художеств", icon: "paintbrush.fill", tint: Theme.lilac)
                    tile("Полить цветы", icon: "drop.fill", tint: Theme.mint)
                }
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 16)
        }
        .background(LinearGradient(colors: [Theme.lavender, Theme.bg], startPoint: .top, endPoint: .center).ignoresSafeArea())
    }

    private func taskRow(_ title: String, icon: String, tint: Color) -> some View {
        HStack {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundColor(Theme.ink)
                .frame(width: 44, height: 44).background(Circle().fill(tint))
            Text(title).font(Theme.font(16, .semibold)).foregroundColor(Theme.ink)
            Spacer()
            Image(systemName: "arrow.right.circle.fill").font(.system(size: 26)).foregroundColor(Theme.blue)
        }
        .padding(14)
        .card(20)
    }

    private func tile(_ title: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(Theme.font(15, .semibold)).foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: icon).font(.system(size: 34)).foregroundColor(Theme.ink.opacity(0.7))
                .frame(maxWidth: .infinity, minHeight: 70)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(20)
    }
}

/// Экраны с деньгами. Здесь слой приколов выключен в коде: ни эффектов, ни тостов, ни шторки.
struct MoneyFormScreen: View {
    let title: String
    let field: String
    let placeholder: String
    let action: String
    @EnvironmentObject private var router: AppRouter
    @State private var input = ""
    @State private var amount = ""

    var body: some View {
        VStack(spacing: 16) {
            ScreenHeader(title: title) { router.pop() }.padding(.top, 8)
            VStack(alignment: .leading, spacing: 10) {
                Text(field).font(Theme.font(13, .semibold)).foregroundColor(Theme.secondary)
                TextField(placeholder, text: $input)
                    .font(Theme.font(18))
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.bg))
                Text("Сумма").font(Theme.font(13, .semibold)).foregroundColor(Theme.secondary)
                TextField("0 ₽", text: $amount)
                    .font(Theme.font(28, .bold))
                    .keyboardType(.numberPad)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.bg))
            }
            .padding(16)
            .card()
            .padding(.horizontal, 16)
            Spacer()
            Text(action)
                .font(Theme.font(17, .bold)).foregroundColor(Theme.ink.opacity(0.4))
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.secondary.opacity(0.3)))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }
}
