import Foundation

/// A countdown.
///
/// The payload holds only the *setting* — how long, what it is called, whether
/// it starts on its own. Whether a timer is running right now is not a property
/// of the note, so it lives in `RestTimerService` and syncs to nothing: a rest
/// timer counting down on your phone should not start counting on your iPad.
struct TimerPayload: BlockPayload {
    static let blockType = BlockType.timer

    enum Sound: String, Codable, CaseIterable, Sendable {
        case chime
        case bell
        case silent

        var displayName: LocalizedStringResource {
            switch self {
            case .chime: "Chime"
            case .bell: "Bell"
            case .silent: "Silent"
            }
        }
    }

    var label: String
    /// Seconds.
    var duration: TimeInterval
    /// Starts the moment the block appears — which is what makes a rest timer
    /// on a template useful rather than one more thing to tap.
    var autoStart: Bool
    var sound: Sound

    init(
        label: String = "",
        duration: TimeInterval = 90,
        autoStart: Bool = false,
        sound: Sound = .chime
    ) {
        self.label = label
        self.duration = duration
        self.autoStart = autoStart
        self.sound = sound
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        self.duration = max(1, try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 90)
        self.autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        let rawSound = try container.decodeIfPresent(String.self, forKey: .sound) ?? Sound.chime.rawValue
        self.sound = Sound(rawValue: rawSound) ?? .chime
    }

    static func makeDefault() -> TimerPayload {
        TimerPayload()
    }

    var plainTextRepresentation: String { label }
}

extension TimeInterval {
    /// `m:ss`, or `h:mm:ss` past an hour. Used for both the countdown and
    /// VoiceOver, so it has to read aloud sensibly as well as fit.
    var timerClockText: String {
        let total = Int(rounded())
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    var spokenDuration: String {
        Duration.seconds(Int(rounded())).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}
