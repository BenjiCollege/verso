import Foundation
import SwiftData

/// A point-in-time snapshot of a note, replayed by the fore-edge scrubber.
@Model
final class Version {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    @Attribute(.externalStorage) var snapshot: Data = Data()
    var isFullSnapshot: Bool = true
    var note: Note?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        snapshot: Data = Data(),
        isFullSnapshot: Bool = true
    ) {
        self.id = id
        self.createdAt = createdAt
        self.snapshot = snapshot
        self.isFullSnapshot = isFullSnapshot
    }
}
