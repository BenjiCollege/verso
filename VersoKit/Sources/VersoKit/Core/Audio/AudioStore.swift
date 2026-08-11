import AVFoundation
import Foundation
import OSLog
import SwiftData

/// Where recordings live, and how much room they take.
///
/// Two places, decided by the note's own setting. A synced recording's bytes go
/// into the store as a CloudKit asset; a device-only one stays in the app
/// container and never enters the store at all — which is a stronger promise
/// than a flag the sync engine is asked to respect.
struct AudioStore {

    static let logger = Logger(subsystem: "com.verso.notes", category: "audio")

    /// AAC, 32kbps, mono — section 7's format. Roughly a quarter of a megabyte
    /// a minute, which is what makes keeping the audio at all reasonable.
    /// Computed rather than stored: `[String: Any]` is not `Sendable`, so a
    /// static `let` of one is shared mutable state as far as Swift 6 is
    /// concerned. Building it per call costs nothing — it is read once, when a
    /// recording starts.
    static var settings: [String: Any] {[
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44_100.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]}

    static let fileExtension = "m4a"

    // MARK: - Locations

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base.appending(path: "Audio", directoryHint: .isDirectory)
    }

    static func url(for assetID: UUID) -> URL {
        directory.appending(path: assetID.uuidString).appendingPathExtension(fileExtension)
    }

    static func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Reading

    /// The file to play.
    ///
    /// A synced recording arrives as bytes in the store and is written out to
    /// the container on first use, so playback is always from a file and never
    /// from memory — a long recording held as `Data` is a memory spike waiting
    /// for a bad moment.
    static func playbackURL(for asset: AudioAsset) -> URL? {
        let url = url(for: asset.id)
        if FileManager.default.fileExists(atPath: url.path()) { return url }

        guard !asset.recording.isEmpty else { return nil }
        do {
            try prepareDirectory()
            try asset.recording.write(to: url, options: .atomic)
            try excludeFromBackup(url)
            return url
        } catch {
            logger.error("Could not materialise recording: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Writing

    /// Files them according to the note's setting.
    static func save(fileAt source: URL, to asset: AudioAsset, localOnly: Bool) throws {
        try prepareDirectory()
        let destination = url(for: asset.id)

        if source != destination {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: source, to: destination)
        }
        try excludeFromBackup(destination)

        asset.localOnly = localOnly
        // Device-only means the bytes never enter the store, so there is
        // nothing for sync to carry even by accident.
        asset.recording = localOnly ? Data() : (try Data(contentsOf: destination))
    }

    /// Moves a recording between synced and device-only after the fact.
    static func setLocalOnly(_ localOnly: Bool, for asset: AudioAsset) throws {
        guard asset.localOnly != localOnly else { return }

        if localOnly {
            // Make sure the file exists locally before dropping the bytes, or
            // turning the switch on would delete the recording.
            guard playbackURL(for: asset) != nil else { throw AudioError.recordingMissing }
            asset.recording = Data()
        } else {
            guard let url = playbackURL(for: asset) else { throw AudioError.recordingMissing }
            asset.recording = try Data(contentsOf: url)
        }
        asset.localOnly = localOnly
    }

    static func delete(_ asset: AudioAsset) {
        try? FileManager.default.removeItem(at: url(for: asset.id))
        asset.recording = Data()
    }

    /// Recordings are reproducible from the store when synced, and deliberately
    /// device-only when not — either way a backup copy is wasted space.
    private static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    // MARK: - Accounting

    /// What Settings shows.
    ///
    /// Section 7 asks for iCloud storage used. Only synced recordings count
    /// toward it; device-only ones are reported separately so the number means
    /// what it says.
    struct Usage: Sendable, Equatable {
        var syncedBytes: Int
        var localOnlyBytes: Int
        var recordingCount: Int

        var totalBytes: Int { syncedBytes + localOnlyBytes }

        func formatted(_ bytes: Int) -> String {
            ByteCountFormatStyle(style: .file).format(Int64(bytes))
        }

        var syncedDescription: String { formatted(syncedBytes) }
        var localOnlyDescription: String { formatted(localOnlyBytes) }
    }

    static func usage(in context: ModelContext) -> Usage {
        let assets = (try? context.fetch(FetchDescriptor<AudioAsset>())) ?? []

        var synced = 0
        var local = 0
        for asset in assets {
            if asset.localOnly {
                local += fileSize(at: url(for: asset.id))
            } else {
                synced += asset.recording.count + asset.syncMap.count
            }
        }
        return Usage(syncedBytes: synced, localOnlyBytes: local, recordingCount: assets.count)
    }

    private static func fileSize(at url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}

enum AudioError: LocalizedError, Equatable {
    case recordingMissing
    case microphoneDenied
    case sessionUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .recordingMissing:
            String(localized: "That recording isn't on this device.")
        case .microphoneDenied:
            String(localized: "Verso hasn't been given permission to use the microphone.")
        case .sessionUnavailable(let reason):
            reason
        }
    }
}
