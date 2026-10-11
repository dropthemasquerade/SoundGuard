import SwiftUI

@MainActor
struct CaptureEditorView: View {
    @Environment(AppModel.self) private var model
    private let samples: [Float]
    private let peaks: [Float]
    private let duration: TimeInterval
    private let truncated: Bool
    private let canRetake: Bool
    private let onCancel: () -> Void
    private let onRetake: ((String, SoundProfile) -> Void)?
    private let onSave: (String, SoundProfile, CaptureEdit) -> Void

    @State private var name: String
    @State private var profile: SoundProfile
    @State private var start: TimeInterval
    @State private var end: TimeInterval
    @State private var denoise = false
    @State private var enhance = false

    init(
        samples: [Float],
        name: String,
        profile: SoundProfile,
        truncated: Bool,
        canRetake: Bool,
        onCancel: @escaping () -> Void,
        onRetake: ((String, SoundProfile) -> Void)? = nil,
        onSave: @escaping (String, SoundProfile, CaptureEdit) -> Void
    ) {
        self.samples = samples
        self.peaks = Self.peaks(of: samples)
        self.duration = CaptureProcessor.duration(of: samples)
        self.truncated = truncated
        self.canRetake = canRetake
        self.onCancel = onCancel
        self.onRetake = onRetake
        self.onSave = onSave
        _name = State(initialValue: name)
        _profile = State(initialValue: profile)
        let initialEnd = min(self.duration, CaptureProcessor.maximumDuration)
        _start = State(initialValue: 0)
        _end = State(initialValue: initialEnd)
    }

    var body: some View {
        ZStack {
            NeonBackground()
            VStack(spacing: 16) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
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

                        SectionLabel(text: "CROP")
                        WaveformTrimView(peaks: peaks, duration: duration, start: $start, end: $end)
                            .frame(height: 112)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .neonPanel(SGTheme.cyan)

                        HStack {
                            nudge(title: "START", value: start, minus: { nudgeStart(-0.05) }, plus: { nudgeStart(0.05) })
                            Spacer()
                            nudge(title: "END", value: end, minus: { nudgeEnd(-0.05) }, plus: { nudgeEnd(0.05) })
                        }
                        Text("LENGTH  \(time(end - start))")
                            .font(SGTheme.micro)
                            .foregroundStyle(SGTheme.magenta)

                        HStack(spacing: 10) {
                            modeButton(title: "DENOISE", on: denoise, color: SGTheme.magenta) { denoise.toggle() }
                            modeButton(title: "ENHANCE", on: enhance, color: SGTheme.cyan) { enhance.toggle() }
                        }

                        Text("Drag the edges to keep the target. Denoise learns room noise from the quiet part of the crop. Enhance cuts rumble and lifts a quiet take.")
                            .font(SGTheme.micro)
                            .foregroundStyle(SGTheme.dim)
                            .fixedSize(horizontal: false, vertical: true)

                        if truncated {
                            Text("Only the first 60 seconds were loaded.")
                                .font(SGTheme.micro)
                                .foregroundStyle(SGTheme.magenta)
                        }
                        if let limitMessage {
                            Text(limitMessage)
                                .font(SGTheme.micro)
                                .foregroundStyle(SGTheme.red)
                        }
                        if let banner = model.banner {
                            Text(banner)
                                .font(SGTheme.micro)
                                .foregroundStyle(SGTheme.red)
                        }
                    }
                }

                HStack(spacing: 10) {
                    NeonButton(title: model.isPreviewingEdit ? "STOP" : "PLAY", color: SGTheme.blue, filled: false) {
                        togglePreview()
                    }
                    NeonButton(title: "SAVE", color: SGTheme.cyan) {
                        guard limitMessage == nil else { return }
                        model.stopPreview()
                        onSave(name, profile, currentEdit)
                    }
                    .disabled(limitMessage != nil)
                    .opacity(limitMessage == nil ? 1 : 0.4)
                }
            }
            .padding(20)
        }
        .onAppear { model.banner = nil }
        .onChange(of: denoise) { _, _ in model.stopPreview() }
        .onChange(of: enhance) { _, _ in model.stopPreview() }
        .onChange(of: start) { _, _ in model.stopPreview() }
        .onChange(of: end) { _, _ in model.stopPreview() }
    }

    private var header: some View {
        HStack {
            Button("CLOSE") {
                model.stopPreview()
                onCancel()
            }
            .font(SGTheme.micro)
            .foregroundStyle(SGTheme.dim)
            Spacer()
            Text("EDIT")
                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                .foregroundStyle(SGTheme.cyan)
            Spacer()
            if canRetake {
                Button("RETAKE") {
                    model.stopPreview()
                    onRetake?(name, profile)
                }
                .font(SGTheme.micro)
                .foregroundStyle(SGTheme.magenta)
            } else {
                Text(time(duration))
                    .font(SGTheme.micro)
                    .foregroundStyle(SGTheme.magenta)
            }
        }
    }

    private var currentEdit: CaptureEdit {
        CaptureEdit(start: start, end: end, denoise: denoise, enhance: enhance)
    }

    private var limitMessage: String? {
        CaptureProcessor.limitMessage(start: start, end: end)
    }

    private func togglePreview() {
        if model.isPreviewingEdit {
            model.stopPreview()
            return
        }
        let processed = CaptureProcessor.process(samples, edit: currentEdit)
        model.previewEditedSamples(processed)
    }

    private func nudgeStart(_ delta: TimeInterval) {
        let minimum = min(CaptureProcessor.minimumDuration, duration)
        let maximum = min(CaptureProcessor.maximumDuration, duration)
        var next = min(max(0, start + delta), end - minimum)
        if end - next > maximum {
            next = end - maximum
        }
        start = max(0, next)
    }

    private func nudgeEnd(_ delta: TimeInterval) {
        let minimum = min(CaptureProcessor.minimumDuration, duration)
        let maximum = min(CaptureProcessor.maximumDuration, duration)
        var next = max(min(duration, end + delta), start + minimum)
        if next - start > maximum {
            next = start + maximum
        }
        end = min(duration, next)
    }

    private func time(_ value: TimeInterval) -> String {
        String(format: "%.2fs", max(0, value))
    }

    private func nudge(title: String, value: TimeInterval, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text("\(title)  \(time(value))")
                .font(SGTheme.micro)
                .foregroundStyle(SGTheme.dim)
            Button("−", action: minus)
            Button("+", action: plus)
        }
        .font(.system(size: 13, weight: .bold, design: .monospaced))
        .foregroundStyle(SGTheme.cyan)
    }

    private func modeButton(title: String, on: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(on ? "\(title) ON" : title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(on ? Color.black : color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(on ? color : color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private static func peaks(of samples: [Float], buckets: Int = 64) -> [Float] {
        guard !samples.isEmpty else { return [0] }
        let count = max(1, min(buckets, samples.count))
        var result = [Float](repeating: 0, count: count)
        for index in 0..<samples.count {
            let bucket = min(count - 1, index * count / samples.count)
            result[bucket] = max(result[bucket], abs(samples[index]))
        }
        let peak = result.max() ?? 0
        guard peak > 1e-6 else { return result }
        return result.map { $0 / peak }
    }
}

private struct WaveformTrimView: View {
    let peaks: [Float]
    let duration: TimeInterval
    @Binding var start: TimeInterval
    @Binding var end: TimeInterval
    @State private var handle: TrimHandle?
    @State private var spanOrigin: (TimeInterval, TimeInterval)?

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                bars(height: geo.size.height)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(SGTheme.magenta, lineWidth: 1.5)
                    .frame(width: max(8, selectionWidth(in: width)), height: geo.size.height)
                    .offset(x: xPosition(start, width: width))
                handleMark
                    .offset(x: xPosition(start, width: width) - 7)
                handleMark
                    .offset(x: xPosition(end, width: width) - 7)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(drag(width: width))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Crop")
        .accessibilityValue("\(String(format: "%.2f", start)) to \(String(format: "%.2f", end)) seconds")
    }

    private func bars(height: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(peaks.indices, id: \.self) { index in
                Capsule()
                    .fill(barColor(index))
                    .frame(height: max(3, CGFloat(peaks[index]) * height))
            }
        }
    }

    private var handleMark: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(SGTheme.magenta)
            .frame(width: 14, height: 28)
            .shadow(color: SGTheme.magenta.opacity(0.7), radius: 4)
    }

    private func barColor(_ index: Int) -> Color {
        guard duration > 0, !peaks.isEmpty else { return SGTheme.cyan.opacity(0.2) }
        let fraction = (Double(index) + 0.5) / Double(peaks.count)
        let time = fraction * duration
        if time >= start && time <= end {
            return SGTheme.cyan
        }
        return SGTheme.cyan.opacity(0.18)
    }

    private func xPosition(_ time: TimeInterval, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(0, time / duration), 1)) * width
    }

    private func selectionWidth(in width: CGFloat) -> CGFloat {
        max(0, xPosition(end, width: width) - xPosition(start, width: width))
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard duration > 0 else { return }
                if handle == nil {
                    let startX = xPosition(start, width: width)
                    let endX = xPosition(end, width: width)
                    let distanceStart = abs(value.startLocation.x - startX)
                    let distanceEnd = abs(value.startLocation.x - endX)
                    if min(distanceStart, distanceEnd) <= 32 {
                        handle = distanceStart <= distanceEnd ? .start : .end
                    } else {
                        handle = .span
                        spanOrigin = (start, end)
                    }
                }
                let time = min(max(0, value.location.x / width), 1) * duration
                let minimum = min(CaptureProcessor.minimumDuration, duration)
                let maximum = min(CaptureProcessor.maximumDuration, duration)
                switch handle {
                case .start:
                    var next = min(max(0, time), end - minimum)
                    if end - next > maximum {
                        next = max(0, end - maximum)
                    }
                    start = next
                case .end:
                    var next = max(min(duration, time), start + minimum)
                    if next - start > maximum {
                        next = min(duration, start + maximum)
                    }
                    end = next
                case .span:
                    guard let origin = spanOrigin else { return }
                    let originTime = min(max(0, value.startLocation.x / width), 1) * duration
                    let delta = time - originTime
                    let length = origin.1 - origin.0
                    var nextStart = origin.0 + delta
                    var nextEnd = origin.1 + delta
                    if nextStart < 0 {
                        nextStart = 0
                        nextEnd = length
                    }
                    if nextEnd > duration {
                        nextEnd = duration
                        nextStart = duration - length
                    }
                    start = nextStart
                    end = nextEnd
                case nil:
                    break
                }
            }
            .onEnded { _ in
                handle = nil
                spanOrigin = nil
            }
    }
}

private enum TrimHandle {
    case start
    case end
    case span
}
