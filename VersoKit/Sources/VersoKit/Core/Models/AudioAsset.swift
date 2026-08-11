import Foundation
import SwiftData

/// A recording attached to a note, plus the map that ties playback position to
/// character offsets and stroke timestamps.
///
/// **`recording` is an addition to the model in section 4, and the only one in
/// the project.** Section 7 asks for a per-note "keep audio on this device
/// only" toggle and for iCloud storage to be shown in Settings — both of which
/// presuppose that audio otherwise syncs, and the only sanctioned sync is
/// CloudKit through this store. Without somewhere to put the bytes, `localOnly`
/// has nothing to mean. It is `.externalStorage`, so CloudKit ships it as an
/// asset rather than a record field, exactly as `syncMap` does.
///
/// Reverting is one property and one line in `AudioStore.save`; audio would
/// then live only in the app container and never reach another device.
@Model
final class AudioAsset {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var duration: Double = 0
    var localOnly: Bool = false
    @Attribute(.externalStorage) var syncMap: Data = Data()

    /// AAC, 32kbps, mono. Empty when `localOnly` is set — the bytes stay in
    /// the app container and never enter the store at all, which is a stronger
    /// promise than a flag the sync engine is asked to respect.
    @Attribute(.externalStorage) var recording: Data = Data()

    var note: Note?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: Double = 0,
        localOnly: Bool = false,
        syncMap: Data = Data(),
        recording: Data = Data()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.localOnly = localOnly
        self.syncMap = syncMap
        self.recording = recording
    }
}
