import SwiftUI

enum SGTheme {
    static let bg = Color(red: 0.02, green: 0.03, blue: 0.07)
    static let panel = Color(red: 0.04, green: 0.07, blue: 0.12)
    static let cyan = Color(red: 0.00, green: 0.83, blue: 1.00)
    static let blue = Color(red: 0.18, green: 0.45, blue: 1.00)
    static let magenta = Color(red: 1.00, green: 0.22, blue: 0.62)
    static let red = Color(red: 1.00, green: 0.18, blue: 0.32)
    static let text = Color.white
    static let dim = Color.white.opacity(0.55)
    static let grid = Color.cyan.opacity(0.10)

    static var mono: Font { .system(.body, design: .monospaced) }
    static var title: Font { .system(size: 28, weight: .heavy, design: .monospaced) }
    static var micro: Font { .system(size: 11, weight: .semibold, design: .monospaced) }
}

struct NeonBackground: View {
    var pulse: Bool = false

    var body: some View {
        ZStack {
            SGTheme.bg
            RadialGradient(
                colors: [SGTheme.blue.opacity(0.28), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            RadialGradient(
                colors: [SGTheme.magenta.opacity(pulse ? 0.32 : 0.12), .clear],
                center: .bottom,
                startRadius: 10,
                endRadius: 380
            )
            GridOverlay()
                .opacity(0.35)
        }
        .ignoresSafeArea()
    }
}

struct GridOverlay: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 28
            var path = Path()
            var x: CGFloat = 0
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(SGTheme.cyan.opacity(0.08)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

struct NeonStroke: ViewModifier {
    var color: Color = SGTheme.cyan
    var radius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(color.opacity(0.85), lineWidth: 1)
                    .shadow(color: color.opacity(0.55), radius: 8)
            )
    }
}

extension View {
    func neonPanel(_ color: Color = SGTheme.cyan, radius: CGFloat = 14) -> some View {
        background(SGTheme.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .modifier(NeonStroke(color: color, radius: radius))
    }
}
