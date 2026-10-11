import Foundation

final class DetectionEngine {
    var parameters: DetectionParameters
    var mode: ListenMode = .sustained
    var referenceDuration: TimeInterval = 0.4
    var templatePartials: [Float] = []
    var templateHarmonicity: Float = 0
    private var hits = 0
    private var misses = 0
    private var sawStrong = false
    private var noiseFloor: Float = 4e-4
    private var latched = false
    private var lastFire: TimeInterval = -1_000
    private var peakConfidence: Float = 0
    private var burstGate = IsolatedBurstGate()

    /// A frame this close to the reference is the target, not a borderline spike.
    private static let strongSimilarity: Float = 0.93

    init(parameters: DetectionParameters = .default(for: .custom)) {
        self.parameters = parameters
    }

    func resetSession() {
        hits = 0
        misses = 0
        sawStrong = false
        peakConfidence = 0
        noiseFloor = 4e-4
        burstGate.reset()
    }

    func resetLatch() {
        latched = false
        hits = 0
        misses = 0
        sawStrong = false
        peakConfidence = 0
        lastFire = -1_000
        burstGate.reset()
    }

    func process(_ score: MatchScore) -> DetectionResult? {
        if score.similarity < parameters.similarityThreshold * 0.55 {
            noiseFloor = (1 - parameters.noiseAdapt) * noiseFloor + parameters.noiseAdapt * score.energy
        }

        guard !latched else { return nil }
        switch mode {
        case .sustained:
            return sustained(score)
        case .single, .harmonic:
            return isolated(score)
        }
    }

    private func sustained(_ score: MatchScore) -> DetectionResult? {
        let strong = score.similarity >= max(parameters.similarityThreshold, Self.strongSimilarity)
        // The on-screen SIM is the best frame. Room noise was also blocking that frame
        // unless it was several times louder than the floor, so 99% never latched.
        let energyFloor = strong ? parameters.minEnergy : max(parameters.minEnergy, noiseFloor * parameters.energyRatio)
        let energyOK = score.energy >= energyFloor
        let similar = score.similarity >= parameters.similarityThreshold
        let cooled = (score.timestamp - lastFire) >= parameters.cooldown || lastFire < 0

        if similar && energyOK && cooled {
            hits += 1
            misses = 0
            if strong { sawStrong = true }
            peakConfidence = max(peakConfidence, score.similarity)
        } else if score.similarity < parameters.similarityThreshold * 0.9 {
            misses += 1
            let allowedMisses = sawStrong ? 2 : 1
            if misses >= allowedMisses {
                clearStreak()
            }
        }

        let needed = sawStrong ? min(2, parameters.consecutiveHits) : parameters.consecutiveHits
        guard hits >= needed else { return nil }

        latched = true
        lastFire = score.timestamp
        let confidence = Double(max(peakConfidence, score.similarity))
        clearStreak()
        return DetectionResult(confidence: confidence, timestamp: score.timestamp)
    }

    private func isolated(_ score: MatchScore) -> DetectionResult? {
        let minDuration = 0.10
        let maxDuration = min(2.2, max(0.65, referenceDuration * 1.8))
        let decision = isolatedDecision(score)
        guard let fired = burstGate.consume(
            time: score.timestamp,
            hot: decision.hot,
            peak: decision.peak,
            shape: decision.shape,
            minDuration: minDuration,
            maxDuration: maxDuration,
            peakNeeded: decision.peakNeeded,
            shapeNeeded: decision.shapeNeeded
        ) else { return nil }
        latched = true
        lastFire = score.timestamp
        return DetectionResult(confidence: Double(fired.confidence), timestamp: fired.time)
    }

    private func isolatedDecision(_ score: MatchScore) -> (hot: Bool, peak: Float, shape: Float, peakNeeded: Float, shapeNeeded: Float) {
        let energyOK = score.energy >= parameters.minEnergy
        switch mode {
        case .single:
            let precise = min(0.97, max(parameters.similarityThreshold, 0.86))
            return (
                energyOK && score.similarity >= precise,
                score.similarity,
                1,
                min(0.99, precise + 0.03),
                0
            )
        case .harmonic:
            let shape = HarmonicProfile.shapeScore(score.partials, templatePartials)
            let usable = templateHarmonicity >= 0.22 && !templatePartials.isEmpty
            return (
                usable && energyOK && score.harmonicity >= 0.30 && shape >= 0.72,
                shape,
                shape,
                0.78,
                0.72
            )
        case .sustained:
            return (false, 0, 0, 1, 1)
        }
    }

    private func clearStreak() {
        hits = 0
        misses = 0
        sawStrong = false
        peakConfidence = 0
    }
}

/// One sound that starts after quiet and then stops.
/// A second similar sound before the hold expires is treated as a repeat and suppressed.
struct IsolatedBurstGate {
    private var started = false
    private var watchStart: TimeInterval = 0
    private var lastTime: TimeInterval = 0
    private var quietAccum: TimeInterval = 0
    private var hotAccum: TimeInterval = 0
    private var coolAccum: TimeInterval = 0
    private var inBurst = false
    private var blocked = false
    private var burstPeak: Float = 0
    private var shapeAccum: Float = 0
    private var shapeFrames = 0
    private var pendingAt: TimeInterval = -1
    private var pendingConfidence: Float = 0
    private var lastBurstStart: TimeInterval = -1
    private var suppressedUntil: TimeInterval = -1

    private static let onsetQuiet: TimeInterval = 0.28
    private static let endCool: TimeInterval = 0.16
    private static let quietBaseline: TimeInterval = 3.5
    private static let holdWithoutBaseline: TimeInterval = 3.5
    private static let holdWithBaseline: TimeInterval = 0.45
    private static let suppressDuration: TimeInterval = 6

    struct Fire {
        var confidence: Float
        var time: TimeInterval
    }

    mutating func reset() {
        self = IsolatedBurstGate()
    }

    mutating func consume(
        time: TimeInterval,
        hot: Bool,
        peak: Float,
        shape: Float,
        minDuration: TimeInterval,
        maxDuration: TimeInterval,
        peakNeeded: Float,
        shapeNeeded: Float
    ) -> Fire? {
        if !started {
            started = true
            watchStart = time
            lastTime = time
        }
        let delta = min(0.25, max(0, time - lastTime))
        lastTime = time

        if hot, pendingAt >= 0, time <= pendingAt {
            cancelPending(until: time + Self.suppressDuration)
            blocked = true
            abandonBurst()
            return nil
        }
        if pendingAt >= 0, !hot, time > pendingAt {
            let fire = Fire(confidence: pendingConfidence, time: time)
            pendingAt = -1
            pendingConfidence = 0
            return fire
        }

        if hot {
            coolAccum = 0
            if blocked {
                return nil
            }
            if inBurst {
                hotAccum += delta
                burstPeak = max(burstPeak, peak)
                shapeAccum += shape
                shapeFrames += 1
                if hotAccum > maxDuration {
                    abandonBurst()
                    blocked = true
                    quietAccum = 0
                }
                return nil
            }
            if quietAccum < Self.onsetQuiet || time < suppressedUntil {
                quietAccum = 0
                if time < suppressedUntil { blocked = true }
                return nil
            }
            inBurst = true
            hotAccum = delta
            coolAccum = 0
            burstPeak = peak
            shapeAccum = shape
            shapeFrames = 1
            quietAccum = 0
            return nil
        }

        if inBurst {
            coolAccum += delta
            if coolAccum >= Self.endCool {
                closeBurst(
                    end: time,
                    minDuration: minDuration,
                    maxDuration: maxDuration,
                    peakNeeded: peakNeeded,
                    shapeNeeded: shapeNeeded
                )
            }
            return nil
        }
        quietAccum += delta
        if blocked, quietAccum >= Self.onsetQuiet, time >= suppressedUntil {
            blocked = false
        }
        return nil
    }

    private mutating func closeBurst(
        end: TimeInterval,
        minDuration: TimeInterval,
        maxDuration: TimeInterval,
        peakNeeded: Float,
        shapeNeeded: Float
    ) {
        let duration = hotAccum
        let shape = shapeFrames > 0 ? shapeAccum / Float(shapeFrames) : 0
        let peak = burstPeak
        let burstStart = end - coolAccum - duration
        abandonBurst()
        quietAccum = 0
        let valid = duration >= minDuration
            && duration <= maxDuration
            && peak >= peakNeeded
            && shape >= shapeNeeded
        guard valid else { return }

        let previous = lastBurstStart
        lastBurstStart = burstStart
        let gap = previous < 0 ? (burstStart - watchStart) : (burstStart - previous)
        let roomWasQuiet = gap >= Self.quietBaseline && end >= suppressedUntil
        if roomWasQuiet {
            pendingConfidence = peak
            pendingAt = end + Self.holdWithBaseline
            return
        }
        if previous < 0 {
            pendingConfidence = peak
            pendingAt = end + Self.holdWithoutBaseline
            return
        }
        cancelPending(until: end + Self.suppressDuration)
        blocked = true
    }

    private mutating func cancelPending(until: TimeInterval) {
        pendingAt = -1
        pendingConfidence = 0
        suppressedUntil = max(suppressedUntil, until)
    }

    private mutating func abandonBurst() {
        inBurst = false
        hotAccum = 0
        coolAccum = 0
        burstPeak = 0
        shapeAccum = 0
        shapeFrames = 0
    }
}
