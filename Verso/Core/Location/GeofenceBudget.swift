import CoreLocation
import Foundation

/// Identifies a region back to the thing that asked for it.
///
/// Encoded into the monitoring identifier, because a geofence callback arrives
/// with nothing but a string and has to find its way home to a checklist item.
struct GeofenceIdentity: Hashable, Sendable, Codable {
    var noteID: UUID
    var blockID: UUID
    /// Set when the reminder came from a checklist item rather than a
    /// `place` block.
    var itemID: UUID?
    /// A category resolves to several nearby branches; this separates them.
    var resolutionIndex: Int

    init(noteID: UUID, blockID: UUID, itemID: UUID? = nil, resolutionIndex: Int = 0) {
        self.noteID = noteID
        self.blockID = blockID
        self.itemID = itemID
        self.resolutionIndex = resolutionIndex
    }

    var stringValue: String {
        "\(noteID.uuidString)|\(blockID.uuidString)|\(itemID?.uuidString ?? "-")|\(resolutionIndex)"
    }

    init?(stringValue: String) {
        let parts = stringValue.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 4,
              let noteID = UUID(uuidString: String(parts[0])),
              let blockID = UUID(uuidString: String(parts[1])),
              let index = Int(parts[3])
        else { return nil }

        self.init(
            noteID: noteID,
            blockID: blockID,
            itemID: UUID(uuidString: String(parts[2])),
            resolutionIndex: index
        )
    }

    /// Everything a block produced, whatever it resolved to. Used to tear a
    /// block's regions down when it changes.
    var blockScope: String {
        "\(noteID.uuidString)|\(blockID.uuidString)|"
    }
}

/// A region that *could* be monitored, and everything the budget needs to
/// decide whether it will be.
struct GeofenceCandidate: Hashable, Sendable, Identifiable {
    var id: GeofenceIdentity
    var target: PlaceTarget
    /// `nil` for a category that has not been resolved to real coordinates yet.
    var center: Coordinate?
    /// Section 7's rule: only regions attached to unchecked items in active
    /// lists. A checked-off item, or a note in the trash, is not actionable.
    var isActionable: Bool
    /// The note's modification date. Breaks ties in favour of what the user has
    /// been working on.
    var lastActivity: Date
    var noteTitle: String

    var isResolved: Bool { center?.isValid ?? false }
}

/// What a given reminder is actually doing.
enum PlaceReminderStatus: Hashable, Sendable {
    case monitoring
    /// Actionable and resolved, but past the system's region limit.
    case deferred(position: Int, limit: Int)
    /// A category with no nearby match found yet.
    case unresolved
    /// Checked off, or in a note that is finished or trashed.
    case dormant
    case unknown

    var isActive: Bool { self == .monitoring }

    /// Shown next to the reminder. Section 7: when a place reminder is
    /// inactive, say so — never fail silently.
    var message: String? {
        switch self {
        case .monitoring:
            nil
        case .deferred(let position, let limit):
            String(localized: "Not active. iOS watches \(limit) places at once, and this one is number \(position). Check off or finish a nearer list to free a slot.")
        case .unresolved:
            String(localized: "Not active yet. No matching place has been found near you.")
        case .dormant:
            String(localized: "Not active, because nothing here is still to do.")
        case .unknown:
            String(localized: "Not active.")
        }
    }
}

/// The outcome of applying the budget.
struct GeofencePlan: Sendable, Equatable {
    var monitored: [GeofenceCandidate] = []
    var deferred: [GeofenceCandidate] = []
    var unresolved: [GeofenceCandidate] = []
    var dormant: [GeofenceCandidate] = []

    var limit: Int = GeofenceBudget.systemLimit

    func status(for identity: GeofenceIdentity) -> PlaceReminderStatus {
        if monitored.contains(where: { $0.id == identity }) { return .monitoring }
        if let position = deferred.firstIndex(where: { $0.id == identity }) {
            return .deferred(position: limit + position + 1, limit: limit)
        }
        if unresolved.contains(where: { $0.id == identity }) { return .unresolved }
        if dormant.contains(where: { $0.id == identity }) { return .dormant }
        return .unknown
    }

    /// The status of whichever region a block produced fared best. A block that
    /// resolved to five branches is active if any one of them is.
    func status(forBlock blockID: UUID, noteID: UUID) -> PlaceReminderStatus {
        let scope = GeofenceIdentity(noteID: noteID, blockID: blockID).blockScope
        func matches(_ candidate: GeofenceCandidate) -> Bool {
            candidate.id.stringValue.hasPrefix(scope)
        }

        if monitored.contains(where: matches) { return .monitoring }
        if let position = deferred.firstIndex(where: matches) {
            return .deferred(position: limit + position + 1, limit: limit)
        }
        if unresolved.contains(where: matches) { return .unresolved }
        if dormant.contains(where: matches) { return .dormant }
        return .unknown
    }

    var isOverBudget: Bool { !deferred.isEmpty }
}

/// Chooses which regions to monitor.
///
/// iOS monitors at most twenty regions per app, system-wide, and silently
/// ignores the twenty-first. So the choice has to be made deliberately and the
/// losers have to be reported — this type does the first and `GeofencePlan`
/// carries the second.
///
/// Pure and free of Core Location, so the ranking is testable without a device,
/// a location, or a simulator route.
struct GeofenceBudget: Sendable {

    /// The hard system ceiling. Not a tuning knob.
    static let systemLimit = 20

    var limit: Int

    init(limit: Int = GeofenceBudget.systemLimit) {
        self.limit = max(0, min(limit, Self.systemLimit))
    }

    /// Ranks candidates and splits them at the limit.
    ///
    /// Order is nearest first, then most recently worked on, then by identity
    /// so the result is stable — the same inputs must produce the same plan on
    /// every run, or regions would churn on every refresh.
    func plan(candidates: [GeofenceCandidate], userLocation: Coordinate?) -> GeofencePlan {
        var plan = GeofencePlan(limit: limit)

        let eligible = candidates.filter(\.isActionable)
        plan.dormant = candidates.filter { !$0.isActionable }
        plan.unresolved = eligible.filter { !$0.isResolved }

        let ranked = eligible
            .filter(\.isResolved)
            .sorted { first, second in
                let a = distance(from: userLocation, to: first)
                let b = distance(from: userLocation, to: second)
                if a != b { return a < b }
                if first.lastActivity != second.lastActivity {
                    return first.lastActivity > second.lastActivity
                }
                return first.id.stringValue < second.id.stringValue
            }

        plan.monitored = Array(ranked.prefix(limit))
        plan.deferred = Array(ranked.dropFirst(limit))
        return plan
    }

    /// Unknown distances sort last, so that when the user's location is not yet
    /// known the ranking falls back to recency rather than to an accident of
    /// ordering.
    private func distance(from userLocation: Coordinate?, to candidate: GeofenceCandidate) -> CLLocationDistance {
        guard let userLocation, let center = candidate.center, center.isValid else {
            return .greatestFiniteMagnitude
        }
        return userLocation.distance(to: center)
    }
}
