import FunLayerCore
import UIKit

/// Картинка для системного «Поделиться». Генерируется на устройстве, никуда не отправляется сама.
/// Без ссылок и QR — по правилам контента. Виральность — через «а ты сможешь?».
enum ShareCard {
    @MainActor
    static func render(found: [Egg], total: Int, eggs: [Egg], text: String) -> UIImage {
        let size = CGSize(width: 900, height: 1125)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor(red: 0.80, green: 0.76, blue: 0.95, alpha: 1).cgColor,
                          UIColor(red: 0.75, green: 0.87, blue: 0.97, alpha: 1).cgColor,
                          UIColor(red: 0.85, green: 0.97, blue: 0.73, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.55, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])

            // мягкие «пузыри» на фоне
            for (x, y, r) in [(120.0, 160.0, 90.0), (780, 260, 60), (700, 940, 120), (160, 900, 50)] {
                cg.setFillColor(UIColor.white.withAlphaComponent(0.35).cgColor)
                cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }

            let card = CGRect(x: 70, y: 150, width: size.width - 140, height: size.height - 300)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: card, cornerRadius: 64).fill()

            draw("Секреты СберKids", at: CGPoint(x: size.width / 2, y: card.minY + 70), size: 52, weight: .heavy)
            draw("\(found.count) из \(total)", at: CGPoint(x: size.width / 2, y: card.minY + 210),
                 size: 150, weight: .black, color: UIColor(red: 0.55, green: 0.45, blue: 0.95, alpha: 1))

            // слоты
            let slot: CGFloat = 104
            let gap: CGFloat = 22
            let rowWidth = CGFloat(total) * slot + CGFloat(total - 1) * gap
            var x = (size.width - rowWidth) / 2
            let y = card.minY + 430
            let foundIds = Set(found.map(\.id))
            for i in 0..<total {
                let rect = CGRect(x: x, y: y, width: slot, height: slot)
                let isFound = i < eggs.count && foundIds.contains(eggs[i].id)
                (isFound ? UIColor(red: 0.67, green: 0.99, blue: 0.32, alpha: 1) : UIColor(white: 0.94, alpha: 1)).setFill()
                UIBezierPath(ovalIn: rect).fill()
                let symbol = isFound ? "checkmark" : (i < eggs.count ? "questionmark" : "lock.fill")
                let cfg = UIImage.SymbolConfiguration(pointSize: 40, weight: .bold)
                if let img = UIImage(systemName: symbol, withConfiguration: cfg)?
                    .withTintColor(isFound ? UIColor(red: 0.1, green: 0.1, blue: 0.14, alpha: 1) : .gray, renderingMode: .alwaysOriginal) {
                    img.draw(at: CGPoint(x: rect.midX - img.size.width / 2, y: rect.midY - img.size.height / 2))
                }
                x += slot + gap
            }

            let names = found.map(\.title).joined(separator: " · ")
            if !names.isEmpty {
                draw(names, at: CGPoint(x: size.width / 2, y: y + 170), size: 30, weight: .semibold,
                     color: UIColor(white: 0.35, alpha: 1), width: card.width - 80)
            }
            draw(text, at: CGPoint(x: size.width / 2, y: card.maxY - 150), size: 38, weight: .bold, width: card.width - 100)
        }
    }

    private static func draw(_ s: String, at center: CGPoint, size: CGFloat, weight: UIFont.Weight,
                             color: UIColor = UIColor(red: 0.1, green: 0.1, blue: 0.14, alpha: 1), width: CGFloat = 760) {
        var font = UIFont.systemFont(ofSize: size, weight: weight)
        if let rounded = font.fontDescriptor.withDesign(.rounded) { font = UIFont(descriptor: rounded, size: size) }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let bounds = (s as NSString).boundingRect(with: CGSize(width: width, height: 400), options: .usesLineFragmentOrigin,
                                                  attributes: attrs, context: nil)
        (s as NSString).draw(in: CGRect(x: center.x - width / 2, y: center.y - bounds.height / 2, width: width, height: bounds.height + 4),
                             withAttributes: attrs)
    }
}
