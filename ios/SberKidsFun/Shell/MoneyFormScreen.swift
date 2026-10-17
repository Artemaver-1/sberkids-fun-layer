import SwiftUI

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
