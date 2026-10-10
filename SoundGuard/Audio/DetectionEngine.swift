import Foundation

final class DetectionEngine {
    var parameters: DetectionParameters
    private var hits = 0
    private var noiseFloor: Float = 4e-4
    private var latched = false
    private var lastFire: TimeInterval = -1_000
    private var peakConfidence: Float = 0

    init(parameters: DetectionParameters = .default(for: .custom)) {
        self.parameters = parameters
    }

    func resetSession() {
        hits = 0
        peakConfidence = 0
        noiseFloor = 4e-4
    }

    func resetLatch() {
        latched = false
        hits = 0
        peakConfidence = 0
        lastFire = -1_000
    }

    func process(_ score: MatchScore) -> DetectionResult? {
        if score.similarity < parameters.similarityThreshold * 0.55 {
            noiseFloor = (1 - parameters.noiseAdapt) * noiseFloor + parameters.noiseAdapt * score.energy
        }

        guard !latched else { return nil }

        let energyOK = score.energy >= max(parameters.minEnergy, noiseFloor * parameters.energyRatio)
        let similar = score.similarity >= parameters.similarityThreshold
        let cooled = (score.timestamp - lastFire) >= parameters.cooldown || lastFire < 0

        if similar && energyOK && cooled {
            hits += 1
            peakConfidence = max(peakConfidence, score.similarity)
        } else if score.similarity < parameters.similarityThreshold * 0.9 {
            hits = 0
            peakConfidence = 0
        }

        guard hits >= parameters.consecutiveHits else { return nil }

        latched = true
        lastFire = score.timestamp
        let confidence = Double(max(peakConfidence, score.similarity))
        hits = 0
        peakConfidence = 0
        return DetectionResult(confidence: confidence, timestamp: score.timestamp)
    }
}
