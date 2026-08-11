import CoreLocation
import Foundation
import OSLog
import SwiftData
import UserNotifications

/// Owns the twenty regions iOS will let the app watch.
///
/// Refreshing is: collect every place a reminder is pinned to, resolve the
/// categories against where the user is, rank them, keep the best twenty, and
/// record what happened to the rest so every reminder can say what it is doing.
@MainActor
@Observable
final class GeofenceService {

    nonisolated static let logger = Logger(subsystem: "com.verso.notes", category: "geofence")
    private static let monitorName = "VersoPlaces"
    private static let notificationPrefix = "verso.place."

    private(set) var plan = GeofencePlan()
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?

    let authority: LocationAuthority

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var monitor: CLMonitor?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    /// What to say when a region fires, keyed by identity.
    @ObservationIgnored private var announcements: [String: (title: String, body: String)] = [:]

    init(container: ModelContainer, authority: LocationAuthority) {
        self.container = container
        self.authority = authority
    }

    // MARK: - Status

    var availability: LocationAvailability { authority.availability }

    func status(forBlock blockID: UUID, noteID: UUID) -> PlaceReminderStatus {
        guard availability.allowsMonitoring else { return .unknown }
        return plan.status(forBlock: blockID, noteID: noteID)
    }

    func status(for identity: GeofenceIdentity) -> PlaceReminderStatus {
        guard availability.allowsMonitoring else { return .unknown }
        return plan.status(for: identity)
    }

    /// The one-line summary the library shows when something the user asked for
    /// is not going to happen.
    var budgetWarning: String? {
        if let message = availability.message, !plan.monitored.isEmpty || plan.isOverBudget || !plan.unresolved.isEmpty {
            return message
        }
        guard plan.isOverBudget else { return nil }
        return String(localized: "\(plan.deferred.count) place reminders aren't active. iOS watches \(plan.limit) places at once.")
    }

    // MARK: - Refresh

    /// Rebuilds the plan and reconciles it with what is actually being watched.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; lastRefresh = Date() }

        let source = GeofenceCandidateSource(modelContainer: container)
        let raw = await source.candidates()

        let userLocation = authority.userLocation
        let resolved = await resolveCategories(in: raw, near: userLocation)

        plan = GeofenceBudget().plan(candidates: resolved, userLocation: userLocation)
        announcements = Dictionary(
            uniqueKeysWithValues: plan.monitored.map { ($0.id.stringValue, announcement(for: $0)) }
        )

        guard availability.allowsMonitoring else {
            await teardown()
            return
        }
        await synchronize(to: plan.monitored)
    }

    /// Expands each unresolved category candidate into up to a few concrete
    /// branches near the user, and drops the placeholder.
    private func resolveCategories(
        in candidates: [GeofenceCandidate],
        near userLocation: Coordinate?
    ) async -> [GeofenceCandidate] {
        var results: [GeofenceCandidate] = []

        for candidate in candidates {
            guard candidate.target.isCategory, let category = candidate.target.poiCategory else {
                results.append(candidate)
                continue
            }
            // Without a fix there is nowhere to search from. The candidate
            // stays unresolved and reports itself as such.
            guard let userLocation, candidate.isActionable else {
                results.append(candidate)
                continue
            }

            let places = await PlaceResolver.resolve(category: category, near: userLocation)
            guard !places.isEmpty else {
                results.append(candidate)
                continue
            }

            for (index, place) in places.enumerated() {
                var branch = candidate
                branch.id = GeofenceIdentity(
                    noteID: candidate.id.noteID,
                    blockID: candidate.id.blockID,
                    itemID: candidate.id.itemID,
                    resolutionIndex: index
                )
                branch.center = place.coordinate
                branch.target.name = candidate.target.name.isEmpty ? place.name : candidate.target.name
                results.append(branch)
            }
        }
        return results
    }

    // MARK: - Monitoring

    private func monitorIfNeeded() async -> CLMonitor {
        if let monitor { return monitor }
        let created = await CLMonitor(Self.monitorName)
        monitor = created
        startObservingEvents(created)
        return created
    }

    /// Adds what is missing and removes what is no longer wanted, rather than
    /// tearing everything down and rebuilding — a region removed and re-added
    /// loses its state, and can fire spuriously on the next fix.
    private func synchronize(to wanted: [GeofenceCandidate]) async {
        let monitor = await monitorIfNeeded()

        let wantedByID = Dictionary(uniqueKeysWithValues: wanted.map { ($0.id.stringValue, $0) })
        let existing = Set(await monitor.identifiers)

        for identifier in existing.subtracting(wantedByID.keys) {
            await monitor.remove(identifier)
        }

        for (identifier, candidate) in wantedByID where !existing.contains(identifier) {
            guard let center = candidate.center, center.isValid else { continue }
            let condition = CLMonitor.CircularGeographicCondition(
                center: center.clCoordinate,
                radius: PlaceTarget.clampRadius(candidate.target.radius)
            )
            await monitor.add(condition, identifier: identifier)
        }

        Self.logger.info("Monitoring \(wantedByID.count, privacy: .public) of \(self.plan.monitored.count + self.plan.deferred.count, privacy: .public) place reminders.")
    }

    private func teardown() async {
        guard let monitor else { return }
        for identifier in await monitor.identifiers {
            await monitor.remove(identifier)
        }
        eventTask?.cancel()
        eventTask = nil
        self.monitor = nil
    }

    private func startObservingEvents(_ monitor: CLMonitor) {
        eventTask?.cancel()
        eventTask = Task { @MainActor [weak self] in
            do {
                for try await event in await monitor.events {
                    guard let self, !Task.isCancelled else { return }
                    await self.handle(event)
                }
            } catch {
                // The stream ends if monitoring is revoked mid-session. The
                // next refresh rebuilds it; losing the stream must not take the
                // app down with it.
                Self.logger.notice("Region event stream ended: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func handle(_ event: CLMonitor.Event) async {
        guard let identity = GeofenceIdentity(stringValue: event.identifier) else { return }
        let candidate = plan.monitored.first { $0.id == identity }
        let trigger = candidate?.target.trigger ?? .arrive

        let matches = switch event.state {
        case .satisfied: trigger == .arrive
        case .unsatisfied: trigger == .leave
        default: false
        }
        guard matches else { return }

        await announce(identity: identity)
    }

    private func announce(identity: GeofenceIdentity) async {
        guard let announcement = announcements[identity.stringValue] else { return }

        let content = UNMutableNotificationContent()
        content.title = announcement.title
        content.body = announcement.body
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: Self.notificationPrefix + identity.stringValue,
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Self.logger.error("Place notification rejected: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func announcement(for candidate: GeofenceCandidate) -> (title: String, body: String) {
        let place = candidate.target.name.isEmpty
            ? String(localized: "here")
            : candidate.target.name
        let title = candidate.noteTitle.isEmpty ? String(localized: "Verso") : candidate.noteTitle

        return (
            title: title,
            body: candidate.target.trigger == .arrive
                ? String(localized: "You're at \(place).")
                : String(localized: "You've left \(place).")
        )
    }
}
