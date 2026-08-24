import Foundation
import Testing
@testable import VersoKit

/// A timer as it appears outside the app.
///
/// The UI itself needs a device, but the shape handed to it does not — and the
/// shape is where the mistakes are. Paused especially: getting it wrong shows a
/// countdown ticking down for a timer that is not counting, which looks right
/// and is a lie.
@Suite("Timer Live Activity")
struct TimerLiveActivityTests {

    @Test("A timer with no name still has something to call itself")
    func unnamedTimerHasAName() {
        let attributes = TimerActivityAttributes(blockID: UUID(), label: "", duration: 90)

        #expect(attributes.displayName == "Timer")
    }

    @Test("A named timer uses its own name")
    func namedTimerKeepsIt() {
        let attributes = TimerActivityAttributes(blockID: UUID(), label: "Rest", duration: 90)

        #expect(attributes.displayName == "Rest")
    }

    /// The Island decides between a live countdown and a held figure on this
    /// one property.
    @Test("Paused is exactly whether a held remainder exists")
    func pausedIsHeldRemainder() {
        let running = TimerActivityAttributes.ContentState(endsAt: .now, remainingWhenPaused: nil)
        let paused = TimerActivityAttributes.ContentState(endsAt: .now, remainingWhenPaused: 42)

        #expect(!running.isPaused)
        #expect(paused.isPaused)
    }

    /// ActivityKit encodes and decodes the content state across a process
    /// boundary to reach the widget, so it has to survive the trip.
    @Test("The content state round-trips through Codable")
    func contentStateRoundTrips() throws {
        let original = TimerActivityAttributes.ContentState(
            endsAt: Date(timeIntervalSince1970: 1_800_000_000),
            remainingWhenPaused: 17.5
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimerActivityAttributes.ContentState.self, from: data)

        #expect(decoded == original)
        #expect(decoded.isPaused)
    }

    @Test("The whole attributes value round-trips too")
    func attributesRoundTrip() throws {
        let id = UUID()
        let original = TimerActivityAttributes(blockID: id, label: "Steep", duration: 180)
        let decoded = try JSONDecoder().decode(
            TimerActivityAttributes.self,
            from: try JSONEncoder().encode(original)
        )

        #expect(decoded.blockID == id)
        #expect(decoded.label == "Steep")
        #expect(decoded.duration == 180)
    }
}
