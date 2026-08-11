import CoreGraphics
import Foundation
import Testing
@testable import Verso

@Suite("Fore-edge")
struct ForeEdgeModelTests {

    /// Height and density encode note length, so a longer note has to produce a
    /// denser block — that is the whole signal.
    @Test("Leaf count grows with the note")
    func lengthDrivesDensity() {
        let short = ForeEdgeModel.make(readableLength: 200, themeID: "iron-gall", isLocked: false)
        let medium = ForeEdgeModel.make(readableLength: 5_000, themeID: "iron-gall", isLocked: false)
        let long = ForeEdgeModel.make(readableLength: 120_000, themeID: "iron-gall", isLocked: false)

        #expect(short.leaves.count < medium.leaves.count)
        #expect(medium.leaves.count < long.leaves.count)
    }

    @Test("An empty note still reads as a block of pages, and a huge one stays drawable")
    func leafCountIsBounded() {
        let empty = ForeEdgeModel.make(readableLength: 0, themeID: "iron-gall", isLocked: false)
        let enormous = ForeEdgeModel.make(readableLength: 10_000_000, themeID: "iron-gall", isLocked: false)

        #expect(empty.leaves.count == ForeEdgeModel.minimumLeaves)
        #expect(enormous.leaves.count == ForeEdgeModel.maximumLeaves)
    }

    @Test("Leaves span the strip and stay inside it")
    func leavesAreWellFormed() {
        let model = ForeEdgeModel.make(readableLength: 4_000, themeID: "foxed", isLocked: false)

        #expect(model.leaves.allSatisfy { (0...1).contains($0.position) })
        #expect(model.leaves.allSatisfy { (0...1).contains($0.extent) })
        #expect(model.leaves.allSatisfy { (0...1).contains($0.emphasis) })
        #expect(model.leaves.first?.position == 0)
        #expect(model.leaves.last?.position == 1)
    }

    /// Section 6: the pattern encodes the active theme.
    @Test("The pattern follows the theme")
    func patternFollowsTheme() {
        let patterns = ThemeCatalog.shared.themes.map { ForeEdgeModel.patternIndex(forThemeID: $0.id) }
        #expect(Set(patterns).count > 1, "six themes should not all cut the same edge")
    }

    /// Two devices showing the same note must cut the same edge, which rules
    /// out Swift's per-process-seeded hashing.
    @Test("The pattern is stable across runs")
    func patternIsDeterministic() {
        for id in ["iron-gall", "midnight-oil", "cyanotype", "riso", "foxed", "linen"] {
            #expect(ForeEdgeModel.patternIndex(forThemeID: id) == ForeEdgeModel.patternIndex(forThemeID: id))
        }
    }

    @Test("The same note always cuts the same edge")
    func modelIsDeterministic() {
        let first = ForeEdgeModel.make(readableLength: 7_777, themeID: "riso", isLocked: false)
        let second = ForeEdgeModel.make(readableLength: 7_777, themeID: "riso", isLocked: false)
        #expect(first == second)
    }

    @Test("The clasp shows only when the note is locked")
    func claspFollowsLock() {
        #expect(ForeEdgeModel.make(readableLength: 100, themeID: "linen", isLocked: true).isLocked)
        #expect(!ForeEdgeModel.make(readableLength: 100, themeID: "linen", isLocked: false).isLocked)
    }
}

@Suite("Fore-edge scrubbing")
struct ForeEdgeScrubberTests {

    private let scrubber = ForeEdgeScrubber()
    private let height: CGFloat = 600

    /// Down the strip is back in time. The top is now.
    @Test("The top of the strip is the present")
    func topIsNow() {
        #expect(scrubber.versionIndex(atY: 0, height: height, versionCount: 10) == nil)
        #expect(scrubber.versionIndex(atY: 10, height: height, versionCount: 10) == nil)
    }

    @Test("Travelling down moves further back")
    func downwardsGoesBackwards() throws {
        let near = try #require(scrubber.versionIndex(atY: height * 0.2, height: height, versionCount: 10))
        let far = try #require(scrubber.versionIndex(atY: height * 0.8, height: height, versionCount: 10))
        #expect(near < far)
    }

    @Test("The bottom reaches the oldest version and never past it")
    func bottomIsTheOldest() {
        #expect(scrubber.versionIndex(atY: height, height: height, versionCount: 10) == 9)
        #expect(scrubber.versionIndex(atY: height * 5, height: height, versionCount: 10) == 9)
    }

    @Test("A note with no history never scrubs")
    func noVersionsNoScrub() {
        #expect(scrubber.versionIndex(atY: height / 2, height: height, versionCount: 0) == nil)
    }

    @Test("A zero-height strip is survivable")
    func zeroHeightIsSafe() {
        #expect(scrubber.versionIndex(atY: 10, height: 0, versionCount: 5) == nil)
    }

    @Test("A single version is reachable")
    func singleVersion() {
        #expect(scrubber.versionIndex(atY: height * 0.5, height: height, versionCount: 1) == 0)
    }

    /// Round-tripping keeps the thumb under the finger rather than drifting
    /// away from it.
    @Test("The thumb position maps back to the same version")
    func thumbPositionRoundTrips() {
        for index in 0..<12 {
            let y = scrubber.y(forVersionIndex: index, height: height, versionCount: 12)
            #expect(scrubber.versionIndex(atY: y, height: height, versionCount: 12) == index)
        }
    }

    @Test("The thumb sits at the top for the present")
    func thumbAtPresent() {
        #expect(scrubber.y(forVersionIndex: nil, height: height, versionCount: 12) == 0)
    }

    /// A touch on a fourteen-point strip is a touch. Only travel is a scrub.
    @Test("A short touch does not start a scrub")
    func activationNeedsTravel() {
        #expect(!scrubber.shouldActivate(translation: CGSize(width: 0, height: 4)))
        #expect(scrubber.shouldActivate(translation: CGSize(width: 0, height: 20)))
        #expect(scrubber.shouldActivate(translation: CGSize(width: 0, height: -20)), "upward travel counts too")
    }

    @Test("Velocity is points per second, and safe at the first sample")
    func velocity() {
        #expect(scrubber.velocity(from: nil, to: (y: 100, time: 1)) == 0)
        #expect(scrubber.velocity(from: (y: 0, time: 0), to: (y: 300, time: 1)) == 300)
        #expect(scrubber.velocity(from: (y: 0, time: 0), to: (y: 300, time: 0)) == 0, "no divide by zero")
        #expect(scrubber.velocity(from: (y: 300, time: 0), to: (y: 0, time: 1)) == -300)
    }
}

@Suite("Haptic patterns")
struct HapticPatternTests {

    /// A missing AHAP is silent failure, and silence is indistinguishable from
    /// hardware that has no haptics — so the files have to be asserted present.
    @Test("Every named pattern has a file in the bundle", arguments: HapticEngine.Pattern.allCases)
    func patternFilesExist(pattern: HapticEngine.Pattern) throws {
        _ = try #require(HapticEngine.url(for: pattern), "\(pattern.rawValue).ahap is missing")
    }

    @Test("Every pattern file is well-formed AHAP", arguments: HapticEngine.Pattern.allCases)
    func patternFilesAreValid(pattern: HapticEngine.Pattern) throws {
        let url = try #require(HapticEngine.url(for: pattern))
        let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        let dictionary = try #require(object as? [String: Any])

        #expect(dictionary["Version"] as? Int == 1)
        let events = try #require(dictionary["Pattern"] as? [[String: Any]])
        #expect(!events.isEmpty)
    }

    /// Section 6 names six moments. Five are authored files; the fore-edge
    /// scrub is a bed built in code because every parameter it starts with is
    /// replaced by thumb velocity within milliseconds.
    @Test("The five authored moments each have a pattern")
    func everyAuthoredMomentHasAPattern() {
        #expect(Set(HapticEngine.Pattern.allCases.map(\.rawValue)) == [
            "checklist-check",
            "vault-clasp",
            "timer-complete",
            "personal-record",
            "note-deleted",
        ])
    }
}
