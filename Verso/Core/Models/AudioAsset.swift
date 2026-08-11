import Foundation
import SwiftData

/// A recording attached to a note, plus the map that ties playback position to
/// character offsets and stroke timestamps.
@Model
final class AudioAsset {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var duration: Double = 0
    var localOnly: Bool = false
    @Attribute(.externalStorage) var syncMap: Data = Data()
    var note: Note?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: Double = 0,
        localOnly: Bool = false,
        syncMap: Data = Data()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.localOnly = localOnly
        self.syncMap = syncMap
    }
}
