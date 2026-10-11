import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        ZStack {
            NeonBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("SYSTEM")
                        .font(SGTheme.title)
                        .foregroundStyle(SGTheme.blue)
                        .padding(.top, 18)

                    panel("MATCHING") {
                        Text("LISTEN MODE")
                            .font(SGTheme.micro)
                            .foregroundStyle(SGTheme.dim)
                        ForEach(ListenMode.allCases) { mode in
                            Button {
                                settings.listenMode = mode
                                model.applyDetectionSettings()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.title)
                                            .font(SGTheme.micro)
                                            .foregroundStyle(settings.listenMode == mode ? SGTheme.cyan : SGTheme.text)
                                        Text(mode.detail)
                                            .font(SGTheme.micro)
                                            .foregroundStyle(SGTheme.dim)
                                    }
                                    Spacer()
                                    if settings.listenMode == mode {
                                        Text("ON")
                                            .font(SGTheme.micro)
                                            .foregroundStyle(SGTheme.bg)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(SGTheme.cyan, in: Capsule())
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Text("SINGLE is for a sound that happens once. It must match closely, then stop. A repeating similar sound and steady noise stay quiet. HARMONIC collects the target's overtones and uses that same one-sound rule, so the wrong stack does not alarm. Just after you arm, those two modes wait to see that the sound does not repeat. After the room has been quiet, they alarm shortly after it ends. Crop the reference to the one sound you want. HARMONIC needs a tone. SUSTAINED is the earlier streak match.")
                            .font(SGTheme.micro)
                            .foregroundStyle(SGTheme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                        labeled("SIMILARITY  \(Int(settings.similarityThreshold * 100))%") {
                            Slider(value: $settings.similarityThreshold, in: 0.62...0.94, step: 0.01)
                                .tint(SGTheme.cyan)
                                .onChange(of: settings.similarityThreshold) { _, _ in
                                    model.applyDetectionSettings()
                                }
                        }
                        if settings.listenMode == .sustained {
                            labeled("CONSECUTIVE HITS  \(settings.consecutiveHits)") {
                                Stepper("", value: $settings.consecutiveHits, in: 2...8)
                                    .onChange(of: settings.consecutiveHits) { _, _ in
                                        model.applyDetectionSettings()
                                    }
                            }
                        } else if settings.listenMode == .single {
                            Text("SINGLE STAYS AT OR ABOVE 86%, EVEN IF THE SLIDER IS LOWER.")
                                .font(SGTheme.micro)
                                .foregroundStyle(SGTheme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("HARMONIC MATCHES THE OVERTONE MIX. THE SIMILARITY SLIDER DOES NOT GATE IT.")
                                .font(SGTheme.micro)
                                .foregroundStyle(SGTheme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    panel("ALARM") {
                        Toggle("HAPTICS", isOn: $settings.hapticsEnabled)
                        Toggle("NOTIFICATIONS", isOn: $settings.notificationsEnabled)
                        labeled("VOLUME  \(Int(settings.alarmVolume * 100))%") {
                            Slider(value: $settings.alarmVolume, in: 0.2...1.0)
                                .tint(SGTheme.magenta)
                        }
                        Text("ALARM TONE")
                            .font(SGTheme.micro)
                            .foregroundStyle(SGTheme.dim)
                        ForEach(AlarmTone.allCases) { tone in
                            Button {
                                settings.alarmTone = tone
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tone.title)
                                            .font(SGTheme.micro)
                                            .foregroundStyle(settings.alarmTone == tone ? SGTheme.cyan : SGTheme.text)
                                        Text(tone.detail)
                                            .font(SGTheme.micro)
                                            .foregroundStyle(SGTheme.dim)
                                    }
                                    Spacer()
                                    if settings.alarmTone == tone {
                                        Text("ON")
                                            .font(SGTheme.micro)
                                            .foregroundStyle(SGTheme.bg)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(SGTheme.cyan, in: Capsule())
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Button(model.previewingTone == settings.alarmTone ? "STOP TONE" : "PREVIEW TONE") {
                            model.previewAlarmTone(settings.alarmTone)
                        }
                        .font(SGTheme.micro)
                        .foregroundStyle(SGTheme.magenta)
                        .disabled(model.coordinator.phase.isAlarmSurface)
                        Text("CLASSIC keeps the original loop. The other tones are generated on this phone.")
                            .font(SGTheme.micro)
                            .foregroundStyle(SGTheme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tint(SGTheme.cyan)

                    panel("HANDHELD QUIET") {
                        Toggle("SILENCE ALARM WHILE HELD", isOn: $settings.handheldQuietEnabled)
                            .onChange(of: settings.handheldQuietEnabled) { _, _ in
                                model.applyQuietSettings()
                            }
                        if settings.handheldQuietEnabled {
                            Toggle("KEEP HAPTICS WHILE QUIET", isOn: $settings.handheldQuietHapticsEnabled)
                                .onChange(of: settings.handheldQuietHapticsEnabled) { _, _ in
                                    model.applyQuietSettings()
                                }
                            labeled("RESUME DELAY  \(Int(settings.resumeDelaySeconds))s") {
                                Slider(value: $settings.resumeDelaySeconds, in: 0...15, step: 1)
                                    .tint(SGTheme.magenta)
                                    .onChange(of: settings.resumeDelaySeconds) { _, _ in
                                        model.applyQuietSettings()
                                    }
                            }
                            ForEach(QuietModeBehavior.allCases) { behavior in
                                Button {
                                    settings.quietModeBehavior = behavior
                                    model.applyQuietSettings()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(behavior.title)
                                                .font(SGTheme.micro)
                                                .foregroundStyle(settings.quietModeBehavior == behavior ? SGTheme.cyan : SGTheme.text)
                                            Text(behavior.detail)
                                                .font(SGTheme.micro)
                                                .foregroundStyle(SGTheme.dim)
                                        }
                                        Spacer()
                                        if settings.quietModeBehavior == behavior {
                                            Text("ON")
                                                .font(SGTheme.micro)
                                                .foregroundStyle(SGTheme.bg)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(SGTheme.cyan, in: Capsule())
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            Text("This is an estimate from motion, not a guarantee the phone is in a hand. A brief shake does not count. Unknown or a stopped sensor does not mute. Listening keeps running, and a match is still logged. After the phone seems set down, an open alarm waits RESUME DELAY, then sounds again. Lock-screen audio can continue, but motion updates can stop in the background. When they stop, the alarm is not left silent. Force-quit or reboot stops both.")
                                .font(SGTheme.micro)
                                .foregroundStyle(SGTheme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(SGTheme.cyan)

                    panel("ACTIVE HOURS") {
                        Toggle("LIMIT LISTENING TO A WINDOW", isOn: $settings.scheduleEnabled)
                            .onChange(of: settings.scheduleEnabled) { _, _ in
                                model.applySchedule()
                            }
                        if settings.scheduleEnabled {
                            labeled("START  \(MonitoringWindow.clock(settings.windowStartMinutes))") {
                                DatePicker(
                                    "START",
                                    selection: minutesBinding(\.windowStartMinutes),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                            }
                            labeled("END  \(MonitoringWindow.clock(settings.windowEndMinutes))") {
                                DatePicker(
                                    "END",
                                    selection: minutesBinding(\.windowEndMinutes),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                            }
                            Text("Listening runs only from START until END, including a range that passes midnight. The same start and end means all day. An alarm that already fired stays on until you acknowledge or stop it. Stop turns listening off. Reset listens again. While armed outside the window, SoundGuard stays awake so the microphone can start on time. Force-quit or reboot still stops it.")
                                .font(SGTheme.micro)
                                .foregroundStyle(SGTheme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(SGTheme.cyan)

                    panel("RESUME") {
                        Toggle("RESUME AFTER RESET", isOn: $settings.resumeAfterReset)
                        Toggle("RESUME AFTER INTERRUPT", isOn: $settings.resumeAfterInterrupt)
                    }
                    .tint(SGTheme.cyan)

                    panel("LIMITS") {
                        Text("Feature matching works for stable beeps, chimes, and repeating alerts. It is not a general speech or open-set classifier. Background listening needs an active audio session and stops if you force-quit, reboot, or iOS suspends the process. Notifications are best-effort and are not a guaranteed alarm channel.")
                            .font(SGTheme.micro)
                            .foregroundStyle(SGTheme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("SOUNDGUARD  ·  LOCAL ONLY  ·  iOS 17+")
                        .font(SGTheme.micro)
                        .foregroundStyle(SGTheme.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func panel(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: title)
            content()
        }
        .padding(16)
        .neonPanel(SGTheme.blue)
    }

    private func minutesBinding(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = model.settings[keyPath: keyPath]
                return Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                model.settings[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                model.applySchedule()
            }
        )
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(SGTheme.micro)
                .foregroundStyle(SGTheme.dim)
            content()
        }
    }
}
