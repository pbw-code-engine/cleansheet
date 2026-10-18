import SwiftUI

enum Theme {
    static let bgTop = Color(red: 0.075, green: 0.080, blue: 0.110)
    static let bgBottom = Color(red: 0.105, green: 0.100, blue: 0.145)
    static let card = Color.white.opacity(0.055)
    static let cardStroke = Color.white.opacity(0.09)
    static let text = Color.white.opacity(0.94)
    static let dim = Color.white.opacity(0.56)
    static let accentA = Color(red: 1.00, green: 0.72, blue: 0.28)
    static let accentB = Color(red: 1.00, green: 0.45, blue: 0.35)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.40)
    static let ok = Color(red: 0.40, green: 0.85, blue: 0.60)

    static var accent: LinearGradient {
        LinearGradient(colors: [accentA, accentB], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var background: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Monospaced font only for file paths.
    static func path(_ size: CGFloat = 11) -> Font { .system(size: size, design: .monospaced) }
}

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18).padding(.vertical, 9)
            .foregroundColor(.black.opacity(0.85))
            .background(Capsule().fill(Theme.accent))
            .shadow(color: Theme.accentB.opacity(enabled ? 0.35 : 0), radius: 10, y: 3)
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct GhostButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .foregroundColor(Theme.text)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0.08)))
            .overlay(Capsule().stroke(Theme.cardStroke))
            .opacity(enabled ? 1 : 0.35)
    }
}

struct CardBackground: ViewModifier {
    var highlighted = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(highlighted ? Color.white.opacity(0.10) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(highlighted ? Theme.accentA.opacity(0.7) : Theme.cardStroke, lineWidth: highlighted ? 1.5 : 1))
    }
}
extension View { func card(highlighted: Bool = false) -> some View { modifier(CardBackground(highlighted: highlighted)) } }

struct SizeBadge: View {
    let bytes: Int64
    var body: some View {
        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
            .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.09)))
    }
}

struct IconBubble: View {
    let symbol: String
    var size: CGFloat = 38
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Theme.accentA.opacity(0.14)))
    }
}

struct Hero: View {
    let symbol: String, title: String, subtitle: String
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.accentB.opacity(0.22)).frame(width: 150, height: 150).blur(radius: 30)
                Circle().fill(Color.white.opacity(0.06)).frame(width: 104, height: 104)
                    .overlay(Circle().stroke(Theme.cardStroke))
                Image(systemName: symbol).font(.system(size: 42, weight: .semibold)).foregroundStyle(Theme.accent)
            }
            Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
            Text(subtitle).font(.system(size: 13)).foregroundColor(Theme.dim).multilineTextAlignment(.center).frame(maxWidth: 380)
        }
    }
}

func categorySymbol(_ category: String) -> String {
    if category.hasPrefix("App caches") { return "archivebox.fill" }
    if category == "Logs" { return "doc.text.fill" }
    if category.hasPrefix("Xcode") { return "hammer.fill" }
    if category.hasPrefix("Simulator") { return "iphone" }
    if category.hasSuffix(".dmg") || category.contains("dmg") { return "opticaldiscdrive.fill" }
    return "shippingbox.fill"
}

func appIcon(_ path: String) -> Image { Image(nsImage: NSWorkspace.shared.icon(forFile: path)) }
