import SwiftUI

enum Theme {
    static let background = Color(red: 0.086, green: 0.090, blue: 0.102)
    static let panel = Color(red: 0.118, green: 0.125, blue: 0.141)
    static let line = Color.white.opacity(0.08)
    static let amber = Color(red: 0.961, green: 0.647, blue: 0.141)
    static let text = Color.white.opacity(0.90)
    static let dim = Color.white.opacity(0.50)
    static let danger = Color(red: 0.93, green: 0.36, blue: 0.33)
    static let ok = Color(red: 0.42, green: 0.80, blue: 0.52)

    static func mono(_ size: CGFloat = 12, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

struct AmberButton: ButtonStyle {
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(12, .semibold))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundColor(prominent ? .black : Theme.amber)
            .background(prominent ? Theme.amber : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.amber, lineWidth: prominent ? 0 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
