import AVFoundation
import Foundation
import OSLog
import UserNotifications

/// A running countdown.
///
/// Wall-clock, not a tick count: the end is a `Date`, so the remaining time is
/// correct however long the app was suspended, killed, or in someone's pocket.
/// A timer that loses time in the background is not a rest timer.
struct RestTimerState: Codable, Hashable, Sendable {
    var blockID: UUID
    var endsAt: Date
    var duration: TimeInterval
    /// Set while paused; the countdown resumes from here.
    var remainingWhenPaused: TimeInterval?

    var isPaused: Bool { remainingWhenPaused != nil }

    func remaining(at now: Date = Date()) -> TimeInterval {
        if let remainingWhenPaused { return remainingWhenPaused }
        return max(0, endsAt.timeIntervalSince(now))
    }

    func isFinished(at now: Date = Date()) -> Bool {
        !isPaused && endsAt <= now
    }

    var fractionElapsed: Double {
        guard duration > 0 else { return 0 }
        return min(max(1 - remaining() / duration, 0), 1)
    }
}

/// Owns every running timer.
///
/// State is deliberately local and never synced. A rest timer counting down on
/// your phone starting itself on your iPad would be a bug, not a feature, so
/// this writes to `UserDefaults` rather than to the note.
@MainActor
@Observable
final class RestTimerService {

    nonisolated static let logger = Logger(subsystem: "com.verso.notes", category: "timers")
    private static let storageKey = "timers.running"
    private static let notificationPrefix = "verso.timer."

    private(set) var running: [UUID: RestTimerState] = [:]
    /// Advances once a second while anything is running, to drive the display.
    private(set) var tick: Date = Date()
    /// Timers that reached zero while the app was open, awaiting acknowledgement.
    private(set) var justFinished: Set<UUID> = []

    private let defaults: UserDefaults
    private let notifications: UNUserNotificationCenter?
    private var ticker: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, notifications: UNUserNotificationCenter? = .current()) {
        self.defaults = defaults
        self.notifications = notifications
        restore()
    }

    // MARK: - Control

    func start(blockID: UUID, duration: TimeInterval, sound: TimerPayload.Sound, label: String) {
        let state = RestTimerState(
            blockID: blockID,
            endsAt: Date().addingTimeInterval(duration),
            duration: duration
        )
        running[blockID] = state
        justFinished.remove(blockID)
        persist()
        scheduleNotification(for: state, sound: sound, label: label)
        // The Lock Screen face of the same countdown. Best-effort by design —
        // see TimerLiveActivity — so nothing below depends on it working.
        TimerLiveActivity.start(state, label: label)
        activateAudioSession()
        startTicking()
    }

    func pause(blockID: UUID) {
        guard var state = running[blockID], !state.isPaused else { return }
        state.remainingWhenPaused = state.remaining()
        running[blockID] = state
        persist()
        cancelNotification(for: blockID)
        TimerLiveActivity.update(state)
    }

    func resume(blockID: UUID, sound: TimerPayload.Sound, label: String) {
        guard var state = running[blockID], let remaining = state.remainingWhenPaused else { return }
        state.endsAt = Date().addingTimeInterval(remaining)
        state.remainingWhenPaused = nil
        running[blockID] = state
        persist()
        scheduleNotification(for: state, sound: sound, label: label)
        TimerLiveActivity.update(state)
        startTicking()
    }

    func stop(blockID: UUID) {
        running[blockID] = nil
        justFinished.remove(blockID)
        persist()
        cancelNotification(for: blockID)
        // Stopped by hand: take it off the Lock Screen at once. Leaving it to
        // linger would show a countdown for something already cancelled.
        TimerLiveActivity.end(blockID: blockID)
        stopTickingIfIdle()
    }

    func acknowledge(blockID: UUID) {
        justFinished.remove(blockID)
    }

    func state(for blockID: UUID) -> RestTimerState? {
        running[blockID]
    }

    // MARK: - Ticking

    /// One task drives every timer. A `Timer` per block would keep the CPU
    /// awake in proportion to how many timers a note happens to contain.
    private func startTicking() {
        guard ticker == nil else { return }
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick = Date()
                self.harvestFinished()

                // Nothing left to count. Drop the task and the audio session
                // rather than waking up four times a second for no one.
                if self.running.isEmpty || self.running.values.allSatisfy(\.isPaused) {
                    self.ticker = nil
                    self.deactivateAudioSession()
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopTickingIfIdle() {
        guard running.isEmpty, let ticker else { return }
        ticker.cancel()
        self.ticker = nil
        deactivateAudioSession()
    }

    private func harvestFinished() {
        let now = Date()
        var changed = false
        for (blockID, state) in running where state.isFinished(at: now) {
            running[blockID] = nil
            justFinished.insert(blockID)
            // If we were backgrounded the notification has already fired;
            // cancelling a delivered request is harmless, and cancelling a
            // pending one stops the user being told twice.
            cancelNotification(for: blockID)
            // Lingers a few seconds rather than vanishing, so a timer that
            // reached zero on a table is still readable when it is picked up.
            TimerLiveActivity.finish(blockID: blockID)
            changed = true
        }
        if changed { persist() }
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(Array(running.values)) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func restore() {
        // Runs even when there is nothing stored. A previous launch that
        // crashed mid-timer leaves a Live Activity behind with no state to
        // match it, and it would otherwise sit on the Lock Screen counting
        // down to nothing until the system reaped it hours later.
        defer { TimerLiveActivity.endOrphans(keeping: Set(running.keys)) }

        guard let data = defaults.data(forKey: Self.storageKey),
              let states = try? JSONDecoder().decode([RestTimerState].self, from: data)
        else { return }

        let now = Date()
        for state in states {
            if state.isFinished(at: now) {
                // It ran out while the app was gone. The notification already
                // told the user; the block shows a finished state rather than
                // a timer that appears to be counting.
                justFinished.insert(state.blockID)
            } else {
                running[state.blockID] = state
            }
        }
        persist()
        if !running.isEmpty { startTicking() }
    }

    // MARK: - Notifications

    /// The reliable half of "survives backgrounding": a suspended app cannot
    /// play a sound, but a scheduled notification will.
    private func scheduleNotification(for state: RestTimerState, sound: TimerPayload.Sound, label: String) {
        guard let notifications, sound != .silent else { return }
        let interval = state.remaining()
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = label.isEmpty ? String(localized: "Timer finished") : label
        content.body = String(localized: "\(state.duration.spokenDuration) is up.")
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: Self.notificationPrefix + state.blockID.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )

        notifications.add(request) { error in
            if let error {
                Self.logger.error("Timer notification rejected: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func cancelNotification(for blockID: UUID) {
        notifications?.removePendingNotificationRequests(
            withIdentifiers: [Self.notificationPrefix + blockID.uuidString]
        )
    }

    func requestNotificationPermission() async {
        guard let notifications else { return }
        // `.timeSensitive` is not requested here: it was deprecated in iOS 15
        // in favour of the Time Sensitive Notifications entitlement, which the
        // app declares and `ios-release.yml` verifies was actually signed in.
        // Asking for it as an option on a build that holds the entitlement is
        // redundant; asking for it on one that does not would not help.
        _ = try? await notifications.requestAuthorization(options: [.alert, .sound])
    }

    // MARK: - Audio session

    /// Makes the completion sound audible over music and with the ringer
    /// switch off — which is exactly the situation a rest timer is used in.
    ///
    /// Note the absence of a `UIBackgroundModes: audio` entitlement. Verso does
    /// not play continuous audio, and claiming that mode for a notes app is an
    /// App Review rejection waiting to happen. Background delivery is the
    /// notification's job; this session only covers the foreground case.
    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
            Self.logger.error("Audio session unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            Self.logger.debug("Audio session deactivation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
