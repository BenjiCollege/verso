import CoreLocation
import Foundation

/// A point on the earth, storable in a block payload.
///
/// `CLLocationCoordinate2D` is not `Codable`, so this is the persisted form and
/// the bridge lives here rather than being rewritten at every call site.
struct Coordinate: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// Rejects the (0, 0) that a half-filled payload decodes to, along with
    /// anything outside the valid ranges.
    var isValid: Bool {
        latitude >= -90 && latitude <= 90
            && longitude >= -180 && longitude <= 180
            && !(latitude == 0 && longitude == 0)
    }

    func distance(to other: Coordinate) -> CLLocationDistance {
        location.distance(from: other.location)
    }
}

/// Which crossing fires the reminder.
enum PlaceTrigger: String, Codable, CaseIterable, Sendable {
    case arrive
    case leave

    var displayName: LocalizedStringResource {
        switch self {
        case .arrive: "When I arrive"
        case .leave: "When I leave"
        }
    }
}

/// A place a reminder is attached to, whether it came from a `place` block or
/// from a checklist item.
///
/// Either a fixed coordinate or a category — "any grocery store" — which the
/// resolver turns into coordinates near wherever the user actually is.
struct PlaceTarget: Hashable, Sendable {
    var name: String
    var coordinate: Coordinate?
    /// An `MKPointOfInterestCategory.rawValue`.
    var poiCategory: String?
    var radius: CLLocationDistance
    var trigger: PlaceTrigger

    /// Below about 100m a geofence fires late, early, or not at all; above ten
    /// kilometres it stops meaning anything.
    static func clampRadius(_ radius: Double) -> CLLocationDistance {
        min(max(radius, 100), 10_000)
    }

    static let defaultRadius: CLLocationDistance = 150

    var isCategory: Bool { coordinate == nil && poiCategory != nil }

    var isResolvable: Bool {
        (coordinate?.isValid ?? false) || (poiCategory?.isEmpty == false)
    }
}
