import Foundation
import SwiftData

/// Every numeric observation in the app lands here, whatever produced it.
///
/// `seriesID` is load-bearing: charting bench press over six months and
/// charting water intake must be the same query. Nothing should ever write a
/// number into a block payload *instead of* here.
@Model
final class MetricEntry {
    var id: UUID = UUID()
    var seriesID: String = ""        // "bench-press", "water", "bodyweight"
    var groupID: String?             // groups sets within one exercise
    var label: String = ""
    var value: Double = 0
    var unit: String = ""
    var recordedAt: Date = Date()
    var noteID: UUID?

    init(
        id: UUID = UUID(),
        seriesID: String = "",
        groupID: String? = nil,
        label: String = "",
        value: Double = 0,
        unit: String = "",
        recordedAt: Date = Date(),
        noteID: UUID? = nil
    ) {
        self.id = id
        self.seriesID = seriesID
        self.groupID = groupID
        self.label = label
        self.value = value
        self.unit = unit
        self.recordedAt = recordedAt
        self.noteID = noteID
    }
}
