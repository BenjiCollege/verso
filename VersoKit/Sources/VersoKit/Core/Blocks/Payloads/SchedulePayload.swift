import Foundation

/// When something is due, and when to say so.
struct SchedulePayload: BlockPayload {
    static let blockType = BlockType.schedule

    /// An offset from `dueAt`. Negative is before, which is the usual case.
    struct Alarm: Codable, Hashable, Identifiable, Sendable {
        var id: UUID
        var offset: TimeInterval

        init(id: UUID = UUID(), offset: TimeInterval = 0) {
            self.id = id
            self.offset = offset
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            self.offset = try container.decodeIfPresent(TimeInterval.self, forKey: .offset) ?? 0
        }

        var displayName: String {
            if offset == 0 { return String(localized: "At the time") }
            let magnitude = abs(offset).spokenDuration
            return offset < 0
                ? String(localized: "\(magnitude) before")
                : String(localized: "\(magnitude) after")
        }

        static let presets: [TimeInterval] = [0, -300, -900, -3600, -86_400, -604_800]
    }

    var label: String
    var dueAt: Date?
    var recurrence: Recurrence?
    var alarms: [Alarm]

    init(
        label: String = "",
        dueAt: Date? = nil,
        recurrence: Recurrence? = nil,
        alarms: [Alarm] = [Alarm()]
    ) {
        self.label = label
        self.dueAt = dueAt
        self.recurrence = recurrence
        self.alarms = alarms
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        self.dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        self.recurrence = try container.decodeIfPresent(Recurrence.self, forKey: .recurrence)
        self.alarms = try container.decodeIfPresent([Alarm].self, forKey: .alarms) ?? []
    }

    static func makeDefault() -> SchedulePayload {
        SchedulePayload(dueAt: Date().addingTimeInterval(3600))
    }

    var plainTextRepresentation: String { label }

    var isArmed: Bool { dueAt != nil && !alarms.isEmpty }
}
