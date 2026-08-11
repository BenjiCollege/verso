import CoreLocation
import Foundation
import OSLog

/// Whether Verso can watch places at all, and why not.
enum LocationAvailability: Hashable, Sendable {
    case ready
    case notDetermined
    case needsAlwaysAuthorization
    case denied
    case restricted
    case reducedAccuracy

    var allowsMonitoring: Bool {
        self == .ready || self == .reducedAccuracy
    }

    /// Shown wherever a place reminder is. Section 7: never fail silently.
    var message: String? {
        switch self {
        case .ready:
            nil
        case .notDetermined:
            String(localized: "Verso hasn't been given permission to use your location yet.")
        case .needsAlwaysAuthorization:
            String(localized: "Place reminders need “Always” location access, so they can reach you when Verso isn't open.")
        case .denied:
            String(localized: "Location access is off, so place reminders can't run. You can turn it back on in Settings.")
        case .restricted:
            String(localized: "Location access is restricted on this device, so place reminders can't run.")
        case .reducedAccuracy:
            String(localized: "Precise Location is off. Place reminders will still work, but may arrive late or from further away.")
        }
    }

    var offersSettingsLink: Bool {
        self == .denied || self == .needsAlwaysAuthorization || self == .reducedAccuracy
    }
}

/// The Core Location authorisation and last-known-position wrapper.
///
/// Separated from the geofencing itself so that the parts which need a real
/// device — permission prompts, position fixes — are in one place, and the
/// ranking logic that decides which regions win stays testable without them.
@MainActor
@Observable
final class LocationAuthority: NSObject, CLLocationManagerDelegate {

    nonisolated static let logger = Logger(subsystem: "com.verso.notes", category: "location")

    private(set) var availability: LocationAvailability = .notDetermined
    private(set) var userLocation: Coordinate?

    @ObservationIgnored
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        updateAvailability()
    }

    /// Asks for When In Use first and Always second, which is the order iOS
    /// requires and also the order that is honest: ask for the smaller thing,
    /// then explain why the larger one is needed.
    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    /// A single fix, used to rank regions by proximity. Verso never tracks
    /// continuously — the geofences do the watching.
    func refreshLocation() {
        guard availability.allowsMonitoring else { return }
        manager.requestLocation()
    }

    private func updateAvailability() {
        availability = switch manager.authorizationStatus {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedWhenInUse: .needsAlwaysAuthorization
        case .authorizedAlways:
            manager.accuracyAuthorization == .reducedAccuracy ? .reducedAccuracy : .ready
        @unknown default: .notDetermined
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            updateAvailability()
            if availability.allowsMonitoring { refreshLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let coordinate = Coordinate(latest.coordinate)
        Task { @MainActor in
            userLocation = coordinate
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // A failed fix is not fatal: the budget falls back to ranking by
        // recency, and every reminder still says what it is doing.
        Self.logger.notice("Location fix failed: \(error.localizedDescription, privacy: .public)")
    }
}
