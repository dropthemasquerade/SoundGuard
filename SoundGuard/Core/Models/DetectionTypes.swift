import Foundation

enum ListenMode: String, Codable, CaseIterable, Identifiable {
    case sustained
    case single
    case harmonic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sustained: return "SUSTAINED"
        case .single: return "SINGLE"
        case .harmonic: return "HARMONIC"
        }
    }

    var detail: String {
        switch self {
        case .sustained: return "A run of similar frames can alarm"
        case .single: return "One precise sound. Repeats and steady noise stay quiet"
        case .harmonic: return "Collect the target overtones, once. The wrong stack stays quiet"
        }
    }
}

struct AudioFrameFeatures {
    var mfcc: [Float]
    var energy: Float
    var timestamp: TimeInterval
    var pitchHz: Float
    var pitchConfidence: Float
    var harmonicity: Float
    var partials: [Float]
}

struct ReferenceTemplate: Codable, Equatable {
    var frames: [[Float]]
    var mean: [Float]
    var duration: TimeInterval
    var profile: SoundProfile
    /// Median fundamental of a stable tone. Zero when the reference is unpitched.
    var pitchHz: Float
    var pitched: Bool
    /// Sum-normalized strengths of partials 1...8. Empty when the reference is not tonal.
    var partials: [Float]
    /// Fundamental used to measure `partials`. May match `pitchHz`.
    var harmonicHz: Float
    /// Share of the spectrum explained by those partials.
    var harmonicity: Float
    var featureVersion: Int

    static let currentFeatureVersion = 3

    init(
        frames: [[Float]],
        mean: [Float],
        duration: TimeInterval,
        profile: SoundProfile,
        pitchHz: Float = 0,
        pitched: Bool = false,
        partials: [Float] = [],
        harmonicHz: Float = 0,
        harmonicity: Float = 0,
        featureVersion: Int = currentFeatureVersion
    ) {
        self.frames = frames
        self.mean = mean
        self.duration = duration
        self.profile = profile
        self.pitchHz = pitchHz
        self.pitched = pitched
        self.partials = partials
        self.harmonicHz = harmonicHz
        self.harmonicity = harmonicity
        self.featureVersion = featureVersion
    }

    private enum CodingKeys: String, CodingKey {
        case frames, mean, duration, profile, pitchHz, pitched, partials, harmonicHz, harmonicity, featureVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frames = try container.decode([[Float]].self, forKey: .frames)
        mean = try container.decode([Float].self, forKey: .mean)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        profile = try container.decode(SoundProfile.self, forKey: .profile)
        pitchHz = try container.decodeIfPresent(Float.self, forKey: .pitchHz) ?? 0
        pitched = try container.decodeIfPresent(Bool.self, forKey: .pitched) ?? false
        partials = try container.decodeIfPresent([Float].self, forKey: .partials) ?? []
        harmonicHz = try container.decodeIfPresent(Float.self, forKey: .harmonicHz) ?? 0
        harmonicity = try container.decodeIfPresent(Float.self, forKey: .harmonicity) ?? 0
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
        try container.encode(partials, forKey: .partials)
        try container.encode(harmonicHz, forKey: .harmonicHz)
        try container.encode(harmonicity, forKey: .harmonicity)
        try container.encode(featureVersion, forKey: .featureVersion)
    }
}

struct MatchScore {
    var similarity: Float
    var energy: Float
    var timestamp: TimeInterval
    var harmonicity: Float = 0
    var partials: [Float] = []
    var partialMatch: Float = 0
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
