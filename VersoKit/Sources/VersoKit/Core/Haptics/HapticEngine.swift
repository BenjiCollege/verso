import CoreHaptics
import Foundation
import OSLog
import UIKit

/// Plays the app's authored haptic patterns.
///
/// Core Haptics with AHAP files, not `UIImpactFeedbackGenerator` — the
/// difference is that a clasp can actually be two parts, and that the fore-edge
/// texture can be modulated by how fast the thumb is moving.
///
/// Every method is safe to call on hardware with no haptics, in the simulator,
/// or when the engine has been shut down by the system. Silence is the failure
/// mode; nothing here can interrupt what the user is doing.
@MainActor
@Observable
final class HapticEngine {

    nonisolated static let logger = Logger(subsystem: "com.verso.notes", category: "haptics")

    /// Named for the moment, not the waveform. The AHAP file is the design.
    ///
    /// The fore-edge scrub is the exception and is built in code: it is a bed
    /// modulated live by thumb velocity, so its parameters are sent rather than
    /// authored. Everything else is a file.
    enum Pattern: String, CaseIterable, Sendable {
        case checklistCheck = "checklist-check"
        case vaultClasp = "vault-clasp"
        case timerComplete = "timer-complete"
        case personalRecord = "personal-record"
        case noteDeleted = "note-deleted"
    }

    private(set) var isSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    /// The user's switch, kept apart from `isSupported` so turning haptics off
    /// and having no haptics stay distinguishable — one is a preference, the
    /// other is hardware, and Settings should not claim the second.
    var isEnabled = true

    private var canPlay: Bool { isSupported && isEnabled }

    @ObservationIgnored private var engine: CHHapticEngine?
    @ObservationIgnored private var scrubPlayer: CHHapticAdvancedPatternPlayer?

    // MARK: - Lifecycle

    /// Starting the engine costs enough to be worth doing once, ahead of the
    /// first tap, rather than on the tap itself.
    func prepare() {
        guard isSupported, engine == nil else { return }

        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true

            // The system stops the engine for its own reasons — a call, memory
            // pressure, the app going to the background. Both handlers exist so
            // the next tap silently works instead of silently not working.
            engine.stoppedHandler = { reason in
                Self.logger.debug("Haptic engine stopped: \(reason.rawValue, privacy: .public)")
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    self?.restart()
                }
            }

            try engine.start()
            self.engine = engine
        } catch {
            Self.logger.notice("Haptics unavailable: \(error.localizedDescription, privacy: .public)")
            isSupported = false
        }
    }

    private func restart() {
        scrubPlayer = nil
        do {
            try engine?.start()
        } catch {
            Self.logger.notice("Haptic engine would not restart: \(error.localizedDescription, privacy: .public)")
            engine = nil
        }
    }

    // MARK: - One-shot

    func play(_ pattern: Pattern) {
        guard canPlay else { return }
        prepare()

        guard let engine, let url = url(for: pattern) else { return }
        do {
            try engine.start()
            try engine.playPattern(from: url)
        } catch {
            Self.logger.debug("Could not play \(pattern.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Fore-edge scrub

    /// The continuous bed under a fore-edge drag.
    ///
    /// Built in code rather than loaded from an AHAP because every one of its
    /// parameters is replaced by `updateScrub` within milliseconds of it
    /// starting — authoring values that are immediately overwritten would be
    /// documentation pretending to be design.
    private static let scrubDuration: TimeInterval = 30

    func beginScrub() {
        guard canPlay else { return }
        prepare()
        guard let engine else { return }

        do {
            try engine.start()
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.25),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.45),
                ],
                relativeTime: 0,
                duration: Self.scrubDuration
            )
            let player = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [event], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
            scrubPlayer = player
        } catch {
            Self.logger.debug("Scrub haptic unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Modulates the bed by thumb speed.
    ///
    /// Slow travel is a quiet, soft texture; fast travel is louder and
    /// sharper — pages passing under a finger rather than a constant buzz.
    ///
    /// - Parameter velocity: points per second.
    func updateScrub(velocity: CGFloat) {
        guard let scrubPlayer else { return }

        let normalised = min(max(abs(velocity) / 900, 0), 1)
        let intensity = Float(0.12 + normalised * 0.55)
        let sharpness = Float(0.25 + normalised * 0.6)

        do {
            try scrubPlayer.sendParameters(
                [
                    CHHapticDynamicParameter(
                        parameterID: .hapticIntensityControl,
                        value: intensity,
                        relativeTime: 0
                    ),
                    CHHapticDynamicParameter(
                        parameterID: .hapticSharpnessControl,
                        value: sharpness,
                        relativeTime: 0
                    ),
                ],
                atTime: CHHapticTimeImmediate
            )
        } catch {
            Self.logger.debug("Scrub modulation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func endScrub() {
        try? scrubPlayer?.stop(atTime: CHHapticTimeImmediate)
        scrubPlayer = nil
    }

    // MARK: - Loading

    /// `nonisolated` because looking a file up in the bundle touches nothing
    /// the engine owns, and the tests that assert every pattern has a file
    /// have no reason to hop to the main actor to do it.
    nonisolated static func url(for pattern: Pattern) -> URL? {
        BundleResourceLoader.url(forResource: pattern.rawValue, extension: "ahap", subdirectory: "Haptics")
    }

    private func url(for pattern: Pattern) -> URL? {
        guard let url = Self.url(for: pattern) else {
            Self.logger.error("Missing haptic file \(pattern.rawValue, privacy: .public).ahap")
            return nil
        }
        return url
    }
}
