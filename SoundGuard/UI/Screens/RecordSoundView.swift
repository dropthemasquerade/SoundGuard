import SwiftUI

@MainActor
struct RecordSoundView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let instruction: String?
    @State private var name: String
    @State private var profile: SoundProfile

    init(preset: NotificationPreset? = nil) {
        instruction = preset?.instruction
        _name = State(initialValue: preset?.name ?? "TARGET")
        _profile = State(initialValue: preset?.profile ?? .beep)
    }

    var body: some View {
        ZStack {
            NeonBackground(pulse: model.isRecording)
            VStack(spacing: 20) {
                HStack {
                    Button("CLOSE") { model.cancelRecording(); dismiss() }
                        .font(SGTheme.micro)
                        .foregroundStyle(SGTheme.dim)
                    Spacer()
                    Text("CAPTURE")
                        .font(.system(size: 16, weight: .heavy, design: .monospaced))
                        .foregroundStyle(SGTheme.cyan)
                    Spacer()
                    Text(timeString)
                        .font(SGTheme.micro)
                        .foregroundStyle(SGTheme.magenta)
                }

                if let instruction {
                    Text(instruction)
                        .font(SGTheme.micro)
                        .foregroundStyle(SGTheme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                TextField("NAME", text: $name)
                    .textInputAutocapitalization(.characters)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .padding(12)
                    .neonPanel(SGTheme.blue)

                Picker("PROFILE", selection: $profile) {
                    ForEach(SoundProfile.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Text(profile.detail)
                    .font(SGTheme.micro)
                    .foregroundStyle(SGTheme.dim)

                Spacer()

                ZStack {
                    Circle()
                        .fill(SGTheme.red.opacity(model.isRecording ? 0.28 : 0.12))
                        .frame(width: 180, height: 180)
                    Circle()
                        .stroke(SGTheme.red, lineWidth: 3)
                        .frame(width: 160, height: 160)
                        .shadow(color: SGTheme.red.opacity(0.7), radius: 12)
                    Text(model.isRecording ? "REC" : "READY")
                        .font(.system(size: 22, weight: .heavy, design: .monospaced))
                        .foregroundStyle(SGTheme.red)
                }
                .onTapGesture {
                    if model.isRecording {
                        model.stopAndSaveRecording(name: name, profile: profile)
                        dismiss()
                    } else {
                        model.beginRecording(defaultName: name, defaultProfile: profile)
                    }
                }

                LevelMeterView(level: model.recordLevel, color: SGTheme.red)
                    .padding(.horizontal, 12)

                Text(model.isRecording ? "TAP TO STOP AND SAVE  ·  MAX 8s" : "TAP THE RING TO START  ·  0.3–8s")
                    .font(SGTheme.micro)
                    .foregroundStyle(SGTheme.dim)

                Spacer()
            }
            .padding(20)
        }
    }

    private var timeString: String {
        String(format: "%04.1fs", model.recordElapsed)
    }
}
