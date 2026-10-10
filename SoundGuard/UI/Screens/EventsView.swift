import SwiftUI

@MainActor
struct EventsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            NeonBackground()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("EVENT LOG")
                        .font(SGTheme.title)
                        .foregroundStyle(SGTheme.magenta)
                    Spacer()
                    if !model.eventLog.isEmpty {
                        Button("PURGE") { model.clearHistory() }
                            .font(SGTheme.micro)
                            .foregroundStyle(SGTheme.dim)
                    }
                }
                .padding(.top, 18)

                if model.eventLog.isEmpty {
                    VStack(spacing: 8) {
                        Text("NO ALARMS RECORDED")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(SGTheme.cyan)
                        Text("Detections stay listed with confidence, acknowledge time, and duration.")
                            .font(SGTheme.micro)
                            .foregroundStyle(SGTheme.dim)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .neonPanel(SGTheme.blue)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(model.eventLog) { event in
                                eventCard(event)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func eventCard(_ event: AlarmEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(event.soundName)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(SGTheme.text)
                Spacer()
                Text(event.status)
                    .font(SGTheme.micro)
                    .foregroundStyle(event.status == "ALARMING" ? SGTheme.red : SGTheme.cyan)
            }
            row("DETECTED", Self.stamp.string(from: event.detectedAt))
            if let ack = event.acknowledgedAt {
                row("ACK", Self.stamp.string(from: ack))
            }
            if let reset = event.resetAt {
                row("RESET", Self.stamp.string(from: reset))
            }
            row("CONFIDENCE", String(format: "%.0f%%", event.confidence * 100))
            row("DURATION", String(format: "%.0fs", event.duration))
            ConfidenceBar(value: event.confidence)
        }
        .padding(14)
        .neonPanel(event.isOpen ? SGTheme.red : SGTheme.blue)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(SGTheme.micro).foregroundStyle(SGTheme.dim)
            Spacer()
            Text(value).font(SGTheme.micro).foregroundStyle(SGTheme.text)
        }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss  yyyy-MM-dd"
        return formatter
    }()
}
