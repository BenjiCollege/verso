import Foundation
import MapKit
import OSLog

/// A concrete place a category resolved to.
struct ResolvedPlace: Hashable, Sendable {
    var name: String
    var coordinate: Coordinate
}

/// Turns "any grocery store" into coordinates.
///
/// A category reminder has no fixed point, so it has to be resolved against
/// wherever the user currently is — which means it is resolved repeatedly, and
/// the answer changes as they move. That is the feature, not a shortcoming.
enum PlaceResolver {

    static let logger = Logger(subsystem: "com.verso.notes", category: "places")

    /// `MKLocalPointsOfInterestRequest` refuses a radius above 50km.
    static let maximumSearchRadius: CLLocationDistance = 50_000

    /// How many branches one category reminder is allowed to occupy.
    ///
    /// Deliberately small: with only twenty regions for the whole app, one
    /// "any grocery store" must not swallow the budget.
    static let branchesPerCategory = 3

    static func resolve(
        category: String,
        near center: Coordinate,
        searchRadius: CLLocationDistance = 5_000,
        limit: Int = branchesPerCategory
    ) async -> [ResolvedPlace] {
        guard !category.isEmpty, center.isValid else { return [] }

        let request = MKLocalPointsOfInterestRequest(
            center: center.clCoordinate,
            radius: min(searchRadius, maximumSearchRadius)
        )
        request.pointOfInterestFilter = MKPointOfInterestFilter(
            including: [MKPointOfInterestCategory(rawValue: category)]
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems
                .compactMap { item in
                    let coordinate = Coordinate(item.location.coordinate)
                    guard coordinate.isValid else { return nil }
                    return ResolvedPlace(name: item.name ?? category, coordinate: coordinate)
                }
                .sorted { center.distance(to: $0.coordinate) < center.distance(to: $1.coordinate) }
                .prefix(limit)
                .map { $0 }
        } catch {
            // No network, no results, or a rate limit. The reminder stays
            // unresolved and says so, rather than pretending to be armed.
            logger.notice("Category “\(category, privacy: .public)” did not resolve: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// The categories offered in the place picker. A short, legible list beats
    /// every category MapKit knows about.
    static let offeredCategories: [MKPointOfInterestCategory] = [
        .foodMarket,
        .pharmacy,
        .bakery,
        .cafe,
        .restaurant,
        .gasStation,
        .bank,
        .atm,
        .postOffice,
        .laundry,
        .fitnessCenter,
        .library,
        .school,
        .hospital,
        .parking,
        .publicTransport,
    ]

    static func displayName(for category: MKPointOfInterestCategory) -> String {
        switch category {
        case .foodMarket: String(localized: "Any grocery store")
        case .pharmacy: String(localized: "Any pharmacy")
        case .bakery: String(localized: "Any bakery")
        case .cafe: String(localized: "Any café")
        case .restaurant: String(localized: "Any restaurant")
        case .gasStation: String(localized: "Any petrol station")
        case .bank: String(localized: "Any bank")
        case .atm: String(localized: "Any cash machine")
        case .postOffice: String(localized: "Any post office")
        case .laundry: String(localized: "Any laundry")
        case .fitnessCenter: String(localized: "Any gym")
        case .library: String(localized: "Any library")
        case .school: String(localized: "Any school")
        case .hospital: String(localized: "Any hospital")
        case .parking: String(localized: "Any car park")
        case .publicTransport: String(localized: "Any transit stop")
        default: category.rawValue
        }
    }
}
