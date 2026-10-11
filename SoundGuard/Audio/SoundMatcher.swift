import Foundation

final class SoundMatcher {
    private(set) var template: ReferenceTemplate?
    private var buffer: [[Float]] = []
    private let maxBufferFrames = 120

    func load(_ template: ReferenceTemplate) {
        self.template = template
        buffer.removeAll(keepingCapacity: true)
    }

    func clear() {
        template = nil
        buffer.removeAll(keepingCapacity: true)
    }

    func resetBuffer() {
        buffer.removeAll(keepingCapacity: true)
    }

    func score(frame: AudioFrameFeatures) -> MatchScore {
        let normalized = MFCC.l2Normalize(frame.mfcc)
        buffer.append(normalized)
        if buffer.count > maxBufferFrames {
            buffer.removeFirst(buffer.count - maxBufferFrames)
        }

        guard let template, !template.frames.isEmpty else {
            return MatchScore(similarity: 0, energy: frame.energy, timestamp: frame.timestamp, harmonicity: frame.harmonicity, partials: frame.partials)
        }

        let timbre = MFCC.cosine(normalized, template.mean)
        let partialMatch = HarmonicProfile.shapeScore(frame.partials, template.partials)
        if template.pitched {
            let similarity = PitchMatch.score(
                pitchHz: frame.pitchHz,
                confidence: frame.pitchConfidence,
                referenceHz: template.pitchHz,
                timbre: timbre
            )
            return scored(similarity, frame: frame, partialMatch: partialMatch)
        }
        let windowScore = slidingWindowScore(template.frames)
        let similarity = max(0, 0.75 * windowScore + 0.25 * max(0, timbre))
        return scored(similarity, frame: frame, partialMatch: partialMatch)
    }

    private func scored(_ similarity: Float, frame: AudioFrameFeatures, partialMatch: Float) -> MatchScore {
        MatchScore(
            similarity: similarity,
            energy: frame.energy,
            timestamp: frame.timestamp,
            harmonicity: frame.harmonicity,
            partials: frame.partials,
            partialMatch: partialMatch
        )
    }

    static func similarity(between a: ReferenceTemplate, and b: ReferenceTemplate) -> Float {
        if a.frames.isEmpty || b.frames.isEmpty { return 0 }
        let mean = max(0, MFCC.cosine(a.mean, b.mean))
        if a.pitched || b.pitched {
            guard a.pitched, b.pitched else { return mean * 0.4 }
            return PitchMatch.score(pitchHz: a.pitchHz, confidence: 1, referenceHz: b.pitchHz, timbre: mean)
        }
        let left = a.frames.count <= b.frames.count ? a.frames : b.frames
        let right = a.frames.count <= b.frames.count ? b.frames : a.frames
        var best: Float = 0
        let limit = max(1, right.count - left.count + 1)
        for offset in 0..<limit {
            var acc: Float = 0
            for i in 0..<left.count {
                acc += MFCC.cosine(left[i], right[offset + i])
            }
            best = max(best, acc / Float(left.count))
        }
        return 0.7 * best + 0.3 * mean
    }

    private func slidingWindowScore(_ templateFrames: [[Float]]) -> Float {
        let width = templateFrames.count
        guard buffer.count >= min(8, width) else { return 0 }
        let window = min(width, buffer.count)
        let start = buffer.count - window
        var acc: Float = 0
        for i in 0..<window {
            let templateIndex = templateFrames.count == window ? i : Int(round(Double(i) * Double(templateFrames.count - 1) / Double(max(window - 1, 1))))
            acc += MFCC.cosine(buffer[start + i], templateFrames[templateIndex])
        }
        return acc / Float(window)
    }
}
