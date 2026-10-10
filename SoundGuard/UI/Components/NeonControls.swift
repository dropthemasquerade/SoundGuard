import SwiftUI

struct NeonButton: View {
    var title: String
    var color: Color = SGTheme.cyan
    var filled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(filled ? Color.black : color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(filled ? color : color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(color, lineWidth: 1)
                )
                .shadow(color: color.opacity(0.45), radius: filled ? 10 : 0)
        }
        .buttonStyle(.plain)
    }
}

struct StatusRingView: View {
    var phase: AppPhase
    var level: Float
    var confidence: Float

    var body: some View {
        let color = ringColor
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 18)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.08, min(1, level * 4))))
                .stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: 0, to: CGFloat(max(0.04, confidence)))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 6) {
                TriangleMark()
                    .stroke(color, lineWidth: 3)
                    .frame(width: 54, height: 48)
                    .shadow(color: color, radius: 8)
                Text(phase.codeName)
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundStyle(color)
                    .tracking(1.5)
            }
        }
        .frame(width: 220, height: 220)
        .animation(.easeInOut(duration: 0.2), value: level)
        .animation(.easeInOut(duration: 0.2), value: confidence)
    }

    private var ringColor: Color {
        switch phase {
        case .alarming: return SGTheme.red
        case .acknowledged, .resetting: return SGTheme.magenta
        case .monitoring: return SGTheme.cyan
        case .outsideWindow: return SGTheme.blue
        case .interrupted, .permissionDenied: return .orange
        case .idle: return SGTheme.blue
        }
    }
}

struct TriangleMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct LevelMeterView: View {
    var level: Float
    var color: Color = SGTheme.cyan

    var body: some View {
        GeometryReader { geo in
            let bars = 24
            HStack(spacing: 3) {
                ForEach(0..<bars, id: \.self) { index in
                    let on = Float(index) / Float(bars) < min(1, level * 6)
                    Capsule()
                        .fill(on ? color : color.opacity(0.12))
                        .frame(height: geo.size.height * (0.35 + 0.65 * CGFloat(index) / CGFloat(bars)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 36)
    }
}

struct SectionLabel: View {
    var text: String
    var color: Color = SGTheme.cyan

    var body: some View {
        Text(text)
            .font(SGTheme.micro)
            .tracking(3)
            .foregroundStyle(color)
    }
}

struct ConfidenceBar: View {
    var value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SGTheme.cyan.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [SGTheme.cyan, SGTheme.magenta], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, value))))
            }
        }
        .frame(height: 8)
    }
}
