import Foundation
import SwiftData

@Model
final class ReferenceSoundRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var duration: Double
    var fileName: String
    var profileRaw: String
    var isActive: Bool
    var templateData: Data

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        duration: Double,
        fileName: String,
        profile: SoundProfile,
        isActive: Bool,
        templateData: Data
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.duration = duration
        self.fileName = fileName
        self.profileRaw = profile.rawValue
        self.isActive = isActive
        self.templateData = templateData
    }

    var profile: SoundProfile {
        SoundProfile(rawValue: profileRaw) ?? .custom
    }

    func asSound() -> ReferenceSound {
        ReferenceSound(
            id: id,
            name: name,
            createdAt: createdAt,
            duration: duration,
            fileName: fileName,
            profile: profile,
            isActive: isActive
        )
    }
}

@Model
final class AlarmEventRecord {
    @Attribute(.unique) var id: UUID
    var soundName: String
    var detectedAt: Date
    var acknowledgedAt: Date?
    var resetAt: Date?
    var confidence: Double
    var status: String

    init(
        id: UUID = UUID(),
        soundName: String,
        detectedAt: Date,
        acknowledgedAt: Date? = nil,
        resetAt: Date? = nil,
        confidence: Double,
        status: String
    ) {
        self.id = id
        self.soundName = soundName
        self.detectedAt = detectedAt
        self.acknowledgedAt = acknowledgedAt
        self.resetAt = resetAt
        self.confidence = confidence
        self.status = status
    }

    func asEvent() -> AlarmEvent {
        AlarmEvent(
            id: id,
            soundName: soundName,
            detectedAt: detectedAt,
            acknowledgedAt: acknowledgedAt,
            resetAt: resetAt,
            confidence: confidence,
            status: status
        )
    }
}

enum PersistenceStack {
    static func makeContainer() -> ModelContainer {
        let schema = Schema([ReferenceSoundRecord.self, AlarmEventRecord.self])
        let config = ModelConfiguration("SoundGuard", schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            let fallback = ModelConfiguration("SoundGuard-memory", schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }
}
