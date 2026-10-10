import Foundation

struct AudioFrameFeatures {
    var mfcc: [Float]
    var energy: Float
    var timestamp: TimeInterval
    var pitchHz: Float
    var pitchConfidence: Float
}

struct ReferenceTemplate: Codable, Equatable {
    var frames: [[Float]]
    var mean: [Float]
    var duration: TimeInterval
    var profile: SoundProfile
    /// Median fundamental of a stable tone. Zero when the reference is unpitched.
    var pitchHz: Float
    var pitched: Bool
    var featureVersion: Int

    static let currentFeatureVersion = 2

    init(
        frames: [[Float]],
        mean: [Float],
        duration: TimeInterval,
        profile: SoundProfile,
        pitchHz: Float = 0,
        pitched: Bool = false,
        featureVersion: Int = currentFeatureVersion
    ) {
        self.frames = frames
        self.mean = mean
        self.duration = duration
        self.profile = profile
        self.pitchHz = pitchHz
        self.pitched = pitched
        self.featureVersion = featureVersion
    }

    private enum CodingKeys: String, CodingKey {
        case frames, mean, duration, profile, pitchHz, pitched, featureVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frames = try container.decode([[Float]].self, forKey: .frames)
        mean = try container.decode([Float].self, forKey: .mean)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        profile = try container.decode(SoundProfile.self, forKey: .profile)
        pitchHz = try container.decodeIfPresent(Float.self, forKey: .pitchHz) ?? 0
        pitched = try container.decodeIfPresent(Bool.self, forKey: .pitched) ?? false
        featureVersion = try container.decodeIfPresent(Int.self, forKey: .featureVersion) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frames, forKey: .frames)
        try container.encode(mean, forKey: .mean)
        try container.encode(duration, forKey: .duration)
        try container.encode(profile, forKey: .profile)
        try container.encode(pitchHz, forKey: .pitchHz)
        try container.encode(pitched, forKey: .pitched)
        try container.encode(featureVersion, forKey: .featureVersion)
    }
}

struct MatchScore {
    var similarity: Float
    var energy: Float
    var timestamp: TimeInterval
}

struct DetectionResult: Equatable {
    var confidence: Double
    var timestamp: TimeInterval
}

struct DetectionParameters: Equatable {
    var similarityThreshold: Float
    var consecutiveHits: Int
    var energyRatio: Float
    var minEnergy: Float
    var cooldown: TimeInterval
    var noiseAdapt: Float

    static func `default`(for profile: SoundProfile) -> DetectionParameters {
        switch profile {
        case .beep:
            return DetectionParameters(
                similarityThreshold: 0.80,
                consecutiveHits: 3,
                energyRatio: 4.0,
                minEnergy: 8e-4,
                cooldown: 1.2,
                noiseAdapt: 0.04
            )
        case .alarm:
            return DetectionParameters(
                similarityThreshold: 0.74,
                consecutiveHits: 5,
                energyRatio: 3.0,
                minEnergy: 6e-4,
                cooldown: 1.5,
                noiseAdapt: 0.05
            )
        case .custom:
            return DetectionParameters(
                similarityThreshold: 0.78,
                consecutiveHits: 4,
                energyRatio: 3.5,
                minEnergy: 7e-4,
                cooldown: 1.5,
                noiseAdapt: 0.05
            )
        }
    }
}

struct ReferenceSound: Identifiable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var duration: TimeInterval
    var fileName: String
    var profile: SoundProfile
    var isActive: Bool
}

struct AlarmEvent: Identifiable, Equatable {
    var id: UUID
    var soundName: String
    var detectedAt: Date
    var acknowledgedAt: Date?
    var resetAt: Date?
    var confidence: Double
    var status: String

    var duration: TimeInterval {
        let end = resetAt ?? acknowledgedAt ?? Date()
        return max(0, end.timeIntervalSince(detectedAt))
    }

    var isOpen: Bool { resetAt == nil }
}
