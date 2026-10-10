import Foundation
import SwiftData

@MainActor
final class EventStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = container.mainContext
    }

    func sounds() -> [ReferenceSound] {
        let descriptor = FetchDescriptor<ReferenceSoundRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor).map { $0.asSound() }) ?? []
    }

    func activeSound() -> ReferenceSound? {
        sounds().first(where: \.isActive)
    }

    func record(id: UUID) -> ReferenceSoundRecord? {
        let descriptor = FetchDescriptor<ReferenceSoundRecord>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    func insertSound(
        name: String,
        duration: TimeInterval,
        fileName: String,
        profile: SoundProfile,
        templateData: Data,
        makeActive: Bool
    ) throws -> ReferenceSound {
        if makeActive {
            try clearActiveFlags()
        }
        let row = ReferenceSoundRecord(
            name: name,
            duration: duration,
            fileName: fileName,
            profile: profile,
            isActive: makeActive,
            templateData: templateData
        )
        context.insert(row)
        try context.save()
        return row.asSound()
    }

    func setActive(id: UUID) throws {
        let descriptor = FetchDescriptor<ReferenceSoundRecord>()
        let rows = try context.fetch(descriptor)
        for row in rows {
            row.isActive = row.id == id
        }
        try context.save()
    }

    func rename(id: UUID, name: String) throws {
        record(id: id)?.name = name
        try context.save()
    }

    func deleteSound(id: UUID) throws -> String? {
        guard let row = record(id: id) else { return nil }
        let fileName = row.fileName
        let wasActive = row.isActive
        context.delete(row)
        if wasActive {
            let remaining = try context.fetch(FetchDescriptor<ReferenceSoundRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
            remaining.first?.isActive = true
        }
        try context.save()
        return fileName
    }

    func templateData(id: UUID) -> Data? {
        record(id: id)?.templateData
    }

    func updateTemplate(id: UUID, templateData: Data) throws {
        guard let row = record(id: id) else { return }
        row.templateData = templateData
        try context.save()
    }

    func events() -> [AlarmEvent] {
        let descriptor = FetchDescriptor<AlarmEventRecord>(sortBy: [SortDescriptor(\.detectedAt, order: .reverse)])
        return (try? context.fetch(descriptor).map { $0.asEvent() }) ?? []
    }

    func openEvent() -> AlarmEvent? {
        events().first { $0.resetAt == nil }
    }

    func insertDetection(_ snapshot: AlarmSnapshot) throws {
        if let open = try context.fetch(FetchDescriptor<AlarmEventRecord>()).first(where: { $0.resetAt == nil }) {
            // Keep a single open event; do not stack.
            _ = open
            return
        }
        let row = AlarmEventRecord(
            id: snapshot.id,
            soundName: snapshot.soundName,
            detectedAt: snapshot.detectedAt,
            confidence: snapshot.confidence,
            status: "ALARMING"
        )
        context.insert(row)
        try context.save()
    }

    func markAcknowledged(id: UUID) throws {
        let descriptor = FetchDescriptor<AlarmEventRecord>(predicate: #Predicate { $0.id == id })
        if let row = try context.fetch(descriptor).first {
            if row.acknowledgedAt == nil {
                row.acknowledgedAt = Date()
            }
            row.status = "ACKNOWLEDGED"
            try context.save()
        }
    }

    func markReset(id: UUID) throws {
        let descriptor = FetchDescriptor<AlarmEventRecord>(predicate: #Predicate { $0.id == id })
        if let row = try context.fetch(descriptor).first {
            if row.acknowledgedAt == nil {
                row.acknowledgedAt = Date()
            }
            row.resetAt = Date()
            row.status = "RESET"
            try context.save()
        }
    }

    func clearEvents() throws {
        for row in try context.fetch(FetchDescriptor<AlarmEventRecord>()) {
            context.delete(row)
        }
        try context.save()
    }

    private func clearActiveFlags() throws {
        let rows = try context.fetch(FetchDescriptor<ReferenceSoundRecord>())
        for row in rows { row.isActive = false }
    }
}
