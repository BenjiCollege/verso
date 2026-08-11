import AVFoundation
import Foundation
import OSLog
import PencilKit
import SwiftData

/// Recording, and the sync map being built as it goes.
///
/// One object owns both, because the timestamps only mean anything relative to
/// the recording's own start — separating them would mean passing that date
/// around and hoping everyone used the same one.
@MainActor
@Observable
final class RecordingSession {

    nonisolated static let logger = Logger(subsystem: "com.verso.notes", category: "audio")

    enum State: Equatable, Sendable {
        case idle
        case recording
        case denied(String)
    }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    /// Which note is being recorded into, so the editor knows to sample.
    private(set) var noteID: UUID?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var map = SyncMapRecorder()
    @ObservationIgnored private var ticker: Task<Void, Never>?

    var isRecording: Bool { state == .recording }

    func isRecording(into note: Note) -> Bool {
        isRecording && noteID == note.id
    }

    // MARK: - Control

    func start(for note: Note) async {
        guard state != .recording else { return }

        guard await AVAudioApplication.requestRecordPermission() else {
            state = .denied(AudioError.microphoneDenied.localizedDescription)
            return
        }

        do {
            try AudioStore.prepareDirectory()
            let session = AVAudioSession.sharedInstance()
            // `.default` rather than `.measurement`: this is somebody talking
            // over their own note, not a measurement, and the processing makes
            // a phone in a pocket sound less like a wind tunnel.
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)

            let url = URL.temporaryDirectory
                .appending(path: UUID().uuidString)
                .appendingPathExtension(AudioStore.fileExtension)

            let recorder = try AVAudioRecorder(url: url, settings: AudioStore.settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                state = .denied(String(localized: "Recording couldn't be started."))
                return
            }

            self.recorder = recorder
            self.startedAt = Date()
            self.noteID = note.id
            self.map = SyncMapRecorder()
            self.elapsed = 0
            self.state = .recording
            startTicking()
        } catch {
            Self.logger.error("Recording failed to start: \(error.localizedDescription, privacy: .public)")
            state = .denied(error.localizedDescription)
        }
    }

    /// Stops, files the recording, and attaches an `AudioAsset` to the note.
    @discardableResult
    func stop(for note: Note, in context: ModelContext, localOnly: Bool) -> AudioAsset? {
        guard let recorder, let startedAt else { return nil }

        let duration = recorder.currentTime
        let url = recorder.url
        recorder.stop()
        teardown()

        // A recording of nothing is not worth an asset, a file, or a row in the
        // storage total.
        guard duration >= 0.5 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        let asset = AudioAsset(createdAt: startedAt, duration: duration)
        context.insert(asset)
        asset.note = note
        note.audio = (note.audio ?? []) + [asset]

        do {
            try AudioStore.save(fileAt: url, to: asset, localOnly: localOnly)
            asset.syncMap = try map.map(duration: duration).encoded()
        } catch {
            Self.logger.error("Could not file recording: \(error.localizedDescription, privacy: .public)")
        }

        // The block that plays it. Appended rather than inserted, so a
        // recording lands where the note ended, which is where it stopped.
        if let block = try? Block(AudioPayload(assetID: asset.id)) {
            context.insert(block)
            note.append(block)
        }
        note.touch()

        return asset
    }

    func cancel() {
        recorder?.stop()
        if let url = recorder?.url { try? FileManager.default.removeItem(at: url) }
        teardown()
    }

    // MARK: - Sampling

    /// Called by the editor as the caret moves.
    func sampleCaret(blockID: UUID, characterOffset: Int) {
        guard isRecording, let startedAt else { return }
        map.sample(
            blockID: blockID,
            characterOffset: characterOffset,
            at: Date().timeIntervalSince(startedAt)
        )
    }

    /// Called when a drawing changes. `PKStroke` already carries its own
    /// timestamps, so this only has to convert them into the recording's clock.
    func sampleInk(blockID: UUID, drawing: PKDrawing) {
        guard isRecording, let startedAt else { return }
        map.record(strokes: InkTimeline.marks(in: drawing, blockID: blockID, recordingStartedAt: startedAt))
    }

    // MARK: - Private

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRecording, let recorder = self.recorder else { return }
                self.elapsed = recorder.currentTime
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func teardown() {
        ticker?.cancel()
        ticker = nil
        recorder = nil
        startedAt = nil
        noteID = nil
        elapsed = 0
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Playing a recording back, with the page following along.
@MainActor
@Observable
final class ReplaySession {

    private(set) var assetID: UUID?
    private(set) var time: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var map = SyncMap()

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    func isPlaying(_ asset: AudioAsset) -> Bool {
        isPlaying && assetID == asset.id
    }

    /// True while a recording that touched this block is playing, so the block
    /// can render itself as it was rather than as it is.
    func isReplaying(blockID: UUID) -> Bool {
        isPlaying && map.blockIDs.contains(blockID)
    }

    func start(_ asset: AudioAsset) {
        stop()
        guard let url = AudioStore.playbackURL(for: asset) else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            player.prepareToPlay()
            player.play()

            self.player = player
            self.assetID = asset.id
            self.duration = player.duration
            self.map = SyncMap.decode(asset.syncMap) ?? SyncMap()
            self.isPlaying = true
            startTicking()
        } catch {
            AudioStore.logger.error("Playback failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        ticker?.cancel()
    }

    func resume() {
        guard player != nil else { return }
        player?.play()
        isPlaying = true
        startTicking()
    }

    func stop() {
        player?.stop()
        player = nil
        ticker?.cancel()
        ticker = nil
        isPlaying = false
        assetID = nil
        time = 0
        map = SyncMap()
    }

    /// Section 7: tap any word or stroke to seek playback.
    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(time, 0), player.duration)
        self.time = player.currentTime
        if !isPlaying {
            player.play()
            isPlaying = true
            startTicking()
        }
    }

    func seek(toCharacterOffset offset: Int, in blockID: UUID) {
        guard let target = map.time(forCharacterOffset: offset, in: blockID) else { return }
        seek(to: target)
    }

    func seek(toStrokeIndex index: Int, in blockID: UUID) {
        guard let target = map.time(forStrokeIndex: index, in: blockID) else { return }
        seek(to: target)
    }

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player else { return }
                self.time = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    return
                }
                // Fine enough for ink to appear in time with the voice
                // describing it.
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
