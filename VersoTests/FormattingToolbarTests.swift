import Testing
@testable import VersoKit

/// The formatting bar sheds controls into a menu as the text size grows. What
/// it is *not* allowed to shed is the reason these exist: an overflow rule is
/// exactly the kind of thing that looks fine in a screenshot at the default
/// size and quietly buries italic at AX5.
@Suite("The formatting bar's overflow")
struct FormattingToolbarTests {

    @Test("Bold and italic stay on the bar at every density")
    func boldAndItalicAreNeverBuried() {
        for density in FormattingDensity.allCases {
            #expect(density.inlineControls.contains(.style(.bold)))
            #expect(density.inlineControls.contains(.style(.italic)))
        }
    }

    @Test("Following the link under the caret stays on the bar at every density")
    func openingALinkIsNeverBuried() {
        for density in FormattingDensity.allCases {
            #expect(density.inlineControls.contains(.openLink))
            #expect(!density.overflowControls.contains(.openLink))
        }
    }

    @Test("Every control is reachable exactly once at every density")
    func nothingIsLostOrDuplicated() {
        for density in FormattingDensity.allCases {
            let reachable = density.inlineControls + density.overflowControls

            #expect(Set(reachable) == Set(FormattingControl.all))
            #expect(reachable.count == FormattingControl.all.count)
        }
    }

    @Test("Each density is strictly tighter than the one before it")
    func densitiesNarrowMonotonically() {
        let densities = FormattingDensity.allCases

        for (looser, tighter) in zip(densities, densities.dropFirst()) {
            let loose = Set(looser.inlineControls)
            let tight = Set(tighter.inlineControls)

            // A tighter row may only drop controls, never gain one — otherwise
            // a control jumps back out of the menu as the bar gets narrower.
            #expect(tight.isSubset(of: loose))
            #expect(tight.count < loose.count)
        }
    }

    @Test("The widest density needs no menu and the narrowest keeps only the essentials")
    func theEndsOfTheScaleAreWhatTheyClaim() {
        #expect(FormattingDensity.full.overflowControls.isEmpty)
        #expect(Set(FormattingDensity.full.inlineControls) == Set(FormattingControl.all))

        #expect(FormattingDensity.minimal.inlineControls == [.style(.bold), .style(.italic), .openLink])
    }

    @Test("Overflow keeps one order, so a control does not move between densities")
    func overflowOrderIsStable() {
        for density in FormattingDensity.allCases {
            let expected = FormattingControl.all.filter { density.overflowControls.contains($0) }
            #expect(density.overflowControls == expected)
        }
    }

    @Test("Every inline style has a control")
    func everyMarkIsOffered() {
        let offered = FormattingControl.all.compactMap { control -> InlineStyle? in
            if case .style(let style) = control { style } else { nil }
        }

        #expect(offered == InlineStyle.all)
    }
}
