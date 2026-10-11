import SwiftUI

@MainActor
struct MonitorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let phase = model.coordinator.phase
        ZStack {
            NeonBackground(pulse: phase == .monitoring)
            VStack(spacing: 22) {
                header
                Spacer()
                StatusRingView(
                    phase: phase,
                    level: model.coordinator.liveLevel,
                    confidence: model.coordinator.liveConfidence
                )
                Text(statusLine)
                    .font(SGTheme.micro)
                    .tracking(3)
                    .foregroundStyle(SGTheme.dim)
                if let quietLine {
                    Text(quietLine)
                        .font(SGTheme.micro)
                        .tracking(2)
                        .foregroundStyle(model.coordinator.quietPosture == .handheldQuiet ? SGTheme.magenta : SGTheme.cyan)
                }
                LevelMeterView(level: model.coordinator.liveLevel)
                    .padding(.horizontal, 28)
                Spacer()
                targetCard
                actionButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 8)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("SOUNDGUARD")
                .font(SGTheme.title)
                .foregroundStyle(
                    LinearGradient(colors: [SGTheme.cyan, SGTheme.magenta], startPoint: .leading, endPoint: .trailing)
                )
                .shadow(color: SGTheme.cyan.opacity(0.6), radius: 10)
            Text("HEAR  ·  ALERT  ·  PROTECT")
                .font(SGTheme.micro)
                .tracking(4)
                .foregroundStyle(SGTheme.dim)
        }
    }

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "ACTIVE TARGET")
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.activeSound?.name ?? "NO TARGET")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(SGTheme.text)
                    Text(model.activeSound.map { "\($0.profile.title)  ·  \(String(format: "%.1fs", $0.duration))" } ?? "Record or import a reference")
                        .font(SGTheme.micro)
                        .foregroundStyle(SGTheme.dim)
                }
                Spacer()
                Text(String(format: "SIM %.0f%%", model.coordinator.liveConfidence * 100))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(SGTheme.cyan)
            }
            ConfidenceBar(value: Double(model.coordinator.liveConfidence))
        }
        .padding(16)
        .neonPanel(SGTheme.blue)
    }

    private var actionButton: some View {
        Group {
            if model.coordinator.phase == .monitoring
                || model.coordinator.phase == .interrupted
                || model.coordinator.phase == .outsideWindow {
                NeonButton(title: "DISARM LISTENING", color: SGTheme.magenta) {
                    model.disarm()
                }
            } else if model.coordinator.phase == .alarming {
                VStack(spacing: 10) {
                    NeonButton(title: "ACKNOWLEDGE ALARM", color: SGTheme.red) {
                        model.acknowledge()
                    }
                    NeonButton(title: "STOP", color: SGTheme.magenta, filled: false) {
                        model.stopAlarm()
                    }
                }
            } else if model.coordinator.phase == .acknowledged {
                VStack(spacing: 10) {
                    NeonButton(title: "RESET LISTENING", color: SGTheme.cyan) {
                        model.resetAlarm()
                    }
                    NeonButton(title: "STOP", color: SGTheme.magenta, filled: false) {
                        model.stopAlarm()
                    }
                }
            } else if model.coordinator.phase == .permissionDenied {
                NeonButton(title: "GRANT MICROPHONE", color: .orange) {
                    model.arm()
                }
            } else {
                NeonButton(title: "ARM LISTENING", color: SGTheme.cyan) {
                    model.arm()
                }
            }
        }
    }

    private var statusLine: String {
        switch model.coordinator.phase {
        case .idle:
            if model.settings.scheduleEnabled {
                return "STANDBY · WINDOW \(model.settings.monitoringWindow.label)"
            }
            return "SYSTEM STANDBY"
        case .monitoring:
            if model.settings.scheduleEnabled {
                return "LIVE MATCHING · \(model.settings.monitoringWindow.label)"
            }
            return "LIVE MATCHING  ·  16 kHz MONO"
        case .outsideWindow:
            return "ARMED · OUTSIDE \(model.settings.monitoringWindow.label)"
        case .interrupted: return "AUDIO SESSION INTERRUPTED"
        case .permissionDenied: return "MICROPHONE ACCESS REQUIRED"
        case .alarming: return "TARGET LOCK"
        case .acknowledged: return "ALARM ACKNOWLEDGED"
        case .resetting: return "RESETTING"
        }
    }

    private var quietLine: String? {
        guard model.settings.handheldQuietEnabled else { return nil }
        switch model.coordinator.quietPosture {
        case .off:
            return nil
        case .handheldQuiet:
            if model.coordinator.phase == .alarming {
                return "HANDHELD QUIET · EVENT LOGGED"
            }
            return "HANDHELD QUIET"
        case .alertsOn:
            return "ALERTS ON"
        case .uncertain:
            return "HOLD STATE UNCERTAIN"
        }
    }
}
