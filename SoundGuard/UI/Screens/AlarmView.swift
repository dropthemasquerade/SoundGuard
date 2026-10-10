import SwiftUI

@MainActor
struct AlarmView: View {
    @Environment(AppModel.self) private var model
    @State private var hold: Double = 0

    var body: some View {
        let snapshot = model.coordinator.activeAlarm
        let acknowledged = model.coordinator.phase == .acknowledged
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let elapsed = context.date.timeIntervalSince(snapshot?.detectedAt ?? context.date)
            ZStack {
                NeonBackground(pulse: !acknowledged)
                VStack(spacing: 18) {
                    Text(acknowledged ? "ACKNOWLEDGED" : "TARGET DETECTED")
                        .font(.system(size: 18, weight: .heavy, design: .monospaced))
                        .tracking(4)
                        .foregroundStyle(acknowledged ? SGTheme.cyan : SGTheme.red)
                        .shadow(color: SGTheme.red.opacity(acknowledged ? 0 : 0.9), radius: 12)
                        .padding(.top, 28)

                    Text(snapshot?.soundName ?? "UNKNOWN")
                        .font(.system(size: 34, weight: .heavy, design: .monospaced))
                        .foregroundStyle(SGTheme.text)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 10) {
                        metric("FIRST LOCK", Self.stamp.string(from: snapshot?.detectedAt ?? Date()))
                        metric("ELAPSED", format(elapsed))
                        metric("CONFIDENCE", String(format: "%.0f%%", (snapshot?.confidence ?? 0) * 100))
                        metric("STATE", model.coordinator.phase.codeName)
                    }
                    .padding(16)
                    .neonPanel(acknowledged ? SGTheme.cyan : SGTheme.red)

                    Text("ALARM STAYS ON UNTIL YOU ACKNOWLEDGE.\nTHE TARGET SOUND ENDING DOES NOT CLEAR THIS.")
                        .font(SGTheme.micro)
                        .foregroundStyle(SGTheme.dim)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    Spacer()

                    if acknowledged {
                        NeonButton(title: "RESET LISTENING", color: SGTheme.cyan) {
                            model.resetAlarm()
                        }
                    } else {
                        holdToAck
                        NeonButton(title: "ACKNOWLEDGE NOW", color: SGTheme.red) {
                            model.acknowledge()
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private var holdToAck: some View {
        VStack(spacing: 8) {
            Text("HOLD TO ACKNOWLEDGE")
                .font(SGTheme.micro)
                .foregroundStyle(SGTheme.dim)
            ZStack(alignment: .leading) {
                Capsule().fill(SGTheme.red.opacity(0.15)).frame(height: 16)
                Capsule().fill(SGTheme.red).frame(width: 280 * hold, height: 16)
            }
            .frame(width: 280)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        Task { @MainActor in
                            hold = min(1, hold + 0.04)
                            if hold >= 1 {
                                model.acknowledge()
                                hold = 0
                            }
                        }
                    }
                    .onEnded { _ in
                        Task { @MainActor in
                            if hold < 1 { hold = 0 }
                        }
                    }
            )
        }
    }

    private func metric(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(SGTheme.micro).foregroundStyle(SGTheme.dim)
            Spacer()
            Text(value).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(SGTheme.text)
        }
    }

    private func format(_ time: TimeInterval) -> String {
        let total = max(0, Int(time))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
