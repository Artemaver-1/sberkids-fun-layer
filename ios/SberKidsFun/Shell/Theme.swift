import SwiftUI

/// Палитра макетов СберKids (сняты с Figma): лайм, лаванда, небесный, мятный.
enum Theme {
    static let bg = Color(red: 0.95, green: 0.95, blue: 0.97)
    static let card = Color.white
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.14)
    static let secondary = Color(red: 0.55, green: 0.56, blue: 0.62)
    static let lime = Color(red: 0.67, green: 0.99, blue: 0.32)
    static let limeSoft = Color(red: 0.85, green: 0.97, blue: 0.73)
    static let aqua = Color(red: 0.53, green: 0.89, blue: 0.93)
    static let lavender = Color(red: 0.80, green: 0.76, blue: 0.95)
    static let lilac = Color(red: 0.83, green: 0.75, blue: 0.95)
    static let violet = Color(red: 0.55, green: 0.45, blue: 0.95)
    static let sky = Color(red: 0.75, green: 0.87, blue: 0.97)
    static let blue = Color(red: 0.24, green: 0.55, blue: 0.9)
    static let mint = Color(red: 0.45, green: 0.89, blue: 0.66)
    static let green = Color(red: 0.13, green: 0.63, blue: 0.22)
    static let red = Color(red: 0.93, green: 0.33, blue: 0.33)

    static let actionGradient = LinearGradient(colors: [aqua, lime], startPoint: .leading, endPoint: .trailing)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

struct CardBackground: ViewModifier {
    var radius: CGFloat = 24
    func body(content: Content) -> some View {
        content.background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.card))
    }
}

extension View {
    func card(_ radius: CGFloat = 24) -> some View { modifier(CardBackground(radius: radius)) }
}

/// Аватар ребёнка (условный, без фото — никаких персональных данных).
struct AvatarView: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Theme.lime, Theme.aqua], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "face.smiling")
                .resizable()
                .scaledToFit()
                .padding(size * 0.2)
                .foregroundColor(Theme.ink)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.white, lineWidth: size * 0.06))
        .shadow(color: Theme.violet.opacity(0.2), radius: 6, y: 3)
    }
}

struct CircleIconButton: View {
    let systemName: String
    var tint: Color = Theme.ink
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white))
        }
    }
}

struct ScreenHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            CircleIconButton(systemName: "chevron.left", action: onBack)
            Spacer()
            Text(title).font(Theme.font(18, .bold)).foregroundColor(Theme.ink)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
    }
}
