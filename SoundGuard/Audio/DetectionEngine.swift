import Foundation

final class DetectionEngine {
    var parameters: DetectionParameters
    private var hits = 0
    private var misses = 0
    private var sawStrong = false
    private var noiseFloor: Float = 4e-4
    private var latched = false
    private var lastFire: TimeInterval = -1_000
    private var peakConfidence: Float = 0

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
    }

    func resetLatch() {
        latched = false
        hits = 0
        misses = 0
        sawStrong = false
        peakConfidence = 0
        lastFire = -1_000
    }

    func process(_ score: MatchScore) -> DetectionResult? {
        if score.similarity < parameters.similarityThreshold * 0.55 {
            noiseFloor = (1 - parameters.noiseAdapt) * noiseFloor + parameters.noiseAdapt * score.energy
        }

        guard !latched else { return nil }

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

    private func clearStreak() {
        hits = 0
        misses = 0
        sawStrong = false
        peakConfidence = 0
    }
}
