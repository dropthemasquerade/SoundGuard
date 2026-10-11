import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SoundsView: View {
    @Environment(AppModel.self) private var model
    @State private var showRecord = false
    @State private var showImporter = false
    @State private var capturePreset: NotificationPreset?

    var body: some View {
        ZStack {
            NeonBackground()
            VStack(alignment: .leading, spacing: 16) {
                Text("TARGETS")
                    .font(SGTheme.title)
                    .foregroundStyle(SGTheme.cyan)
                    .padding(.top, 18)
                Text("Record a beep, import a file, or capture a classic message alert.")
                    .font(SGTheme.micro)
                    .foregroundStyle(SGTheme.dim)

                HStack(spacing: 10) {
                    NeonButton(title: "RECORD", color: SGTheme.cyan) { showRecord = true }
                    NeonButton(title: "IMPORT", color: SGTheme.magenta, filled: false) { showImporter = true }
                }

                presetStrip

                if model.sounds.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(model.sounds) { sound in
                                soundCard(sound)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
        .sheet(isPresented: $showRecord, onDismiss: { model.cancelRecording() }) {
            RecordSoundView()
                .environment(model)
        }
        .sheet(item: $capturePreset, onDismiss: { model.cancelRecording() }) { preset in
            RecordSoundView(preset: preset)
                .environment(model)
        }
        .sheet(
            item: Binding(
                get: { model.libraryDraft },
                set: { draft in
                    if draft == nil {
                        model.discardLibraryDraft()
                    } else {
                        model.libraryDraft = draft
                    }
                }
            ),
            onDismiss: { model.discardLibraryDraft() }
        ) { draft in
            CaptureEditorView(
                samples: draft.samples,
                name: draft.name,
                profile: draft.profile,
                truncated: draft.truncated,
                canRetake: false,
                onCancel: { model.discardLibraryDraft() },
                onSave: { name, profile, edit in
                    model.saveLibraryDraft(name: name, profile: profile, edit: edit)
                }
            )
            .environment(model)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio, .wav, .mpeg4Audio, .mp3, .aiff],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.stageImport(from: url)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("NO REFERENCE LOADED")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(SGTheme.cyan)
            Text("Tap a message tone and play the original alert next to this iPhone.")
                .font(SGTheme.micro)
                .foregroundStyle(SGTheme.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .neonPanel(SGTheme.blue)
        .padding(.top, 20)
    }

    private var presetStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "MESSAGE TONES")
            Text("Play the original alert beside this iPhone. The recording is the target.")
                .font(SGTheme.micro)
                .foregroundStyle(SGTheme.dim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NotificationPreset.catalog) { preset in
                        presetChip(preset)
                    }
                }
            }
        }
    }

    private func presetChip(_ preset: NotificationPreset) -> some View {
        let saved = model.sounds.contains { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame }
        let active = model.activeSound?.name.caseInsensitiveCompare(preset.name) == .orderedSame
        return Button {
            if let existing = model.sounds.first(where: { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame }) {
                model.activate(existing)
            } else {
                capturePreset = preset
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(active ? SGTheme.bg : SGTheme.text)
                Text(preset.hint.uppercased())
                    .font(SGTheme.micro)
                    .foregroundStyle(active ? SGTheme.bg.opacity(0.72) : SGTheme.dim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                active ? SGTheme.cyan : (saved ? SGTheme.cyan.opacity(0.16) : SGTheme.panel),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(saved ? SGTheme.cyan : SGTheme.blue, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func soundCard(_ sound: ReferenceSound) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sound.name)
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(SGTheme.text)
                    Text("\(sound.profile.title)  ·  \(String(format: "%.1fs", sound.duration))")
                        .font(SGTheme.micro)
                        .foregroundStyle(SGTheme.dim)
                }
                Spacer()
                if sound.isActive {
                    Text("ACTIVE")
                        .font(SGTheme.micro)
                        .foregroundStyle(SGTheme.bg)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SGTheme.cyan, in: Capsule())
                }
            }
            HStack(spacing: 8) {
                Button(model.previewingID == sound.id ? "STOP" : "PLAY") {
                    if model.previewingID == sound.id {
                        model.stopPreview()
                    } else {
                        model.preview(sound)
                    }
                }
                Button("EDIT") { model.stageExisting(sound) }
                Button("ARM THIS") { model.activate(sound) }
                Spacer()
                Button("DELETE", role: .destructive) { model.delete(sound) }
            }
            .font(SGTheme.micro)
            .foregroundStyle(SGTheme.cyan)
        }
        .padding(14)
        .neonPanel(sound.isActive ? SGTheme.cyan : SGTheme.blue)
    }
}
