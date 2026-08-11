import CoreLocation
import Foundation

/// Somewhere a reminder is pinned to.
///
/// Either a fixed coordinate or a point-of-interest *category*. "Any grocery
/// store" is the useful case and the harder one: it has no coordinate until the
/// resolver finds the nearest ones to wherever the user is standing.
struct PlacePayload: BlockPayload {
    static let blockType = BlockType.place

    var name: String
    var coordinate: Coordinate?
    /// An `MKPointOfInterestCategory.rawValue`. Mutually exclusive with a
    /// coordinate in practice; a coordinate wins if both are set.
    var poiCategory: String?
    var radius: CLLocationDistance
    var trigger: PlaceTrigger

    init(
        name: String = "",
        coordinate: Coordinate? = nil,
        poiCategory: String? = nil,
        radius: CLLocationDistance = PlaceTarget.defaultRadius,
        trigger: PlaceTrigger = .arrive
    ) {
        self.name = name
        self.coordinate = coordinate
        self.poiCategory = poiCategory
        self.radius = PlaceTarget.clampRadius(radius)
        self.trigger = trigger
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let coordinate = try container.decodeIfPresent(Coordinate.self, forKey: .coordinate)
        let rawTrigger = try container.decodeIfPresent(String.self, forKey: .trigger) ?? PlaceTrigger.arrive.rawValue

        self.init(
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            // A half-written payload decodes to (0, 0), which is a real place
            // in the Atlantic and never what anybody meant.
            coordinate: (coordinate?.isValid ?? false) ? coordinate : nil,
            poiCategory: try container.decodeIfPresent(String.self, forKey: .poiCategory),
            radius: try container.decodeIfPresent(Double.self, forKey: .radius) ?? PlaceTarget.defaultRadius,
            trigger: PlaceTrigger(rawValue: rawTrigger) ?? .arrive
        )
    }

    static func makeDefault() -> PlacePayload {
        PlacePayload()
    }

    var plainTextRepresentation: String { name }

    var target: PlaceTarget {
        PlaceTarget(
            name: name,
            coordinate: coordinate,
            poiCategory: poiCategory,
            radius: radius,
            trigger: trigger
        )
    }
}

extension ChecklistPayload.ItemPlace {
    /// Checklist items carry the same idea in a flatter shape, from Phase 1.
    /// One conversion here keeps the geofence layer from knowing about two.
    func target(named name: String) -> PlaceTarget {
        let coordinate = latitude.flatMap { latitude in
            longitude.map { Coordinate(latitude: latitude, longitude: $0) }
        }
        return PlaceTarget(
            name: name,
            coordinate: (coordinate?.isValid ?? false) ? coordinate : nil,
            poiCategory: poiCategory,
            radius: PlaceTarget.clampRadius(radius),
            trigger: .arrive
        )
    }
}
