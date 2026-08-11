import SwiftUI

/// The animation vocabulary from section 6.
///
/// These are computed rather than stored so they carry no global mutable state
/// under strict concurrency, regardless of whether `Animation` is `Sendable` on
/// a given SDK. The values are exactly those specified.
enum Motion {
    static var pageTurn: Animation { .spring(duration: 0.55, bounce: 0.18) }
    static var reveal: Animation { .spring(duration: 0.40, bounce: 0.24) }
    static var settle: Animation { .spring(duration: 0.30, bounce: 0.10) }
    static var snap: Animation { .spring(duration: 0.20, bounce: 0.00) }
    static var ambient: Animation { .easeInOut(duration: 2.40) }

    /// Delay between successive items in a staggered entrance.
    static let staggerGap: TimeInterval = 0.018
    /// Delay between successive words during a reveal.
    static let wordGap: TimeInterval = 0.045
}

/// Every animation in the app is named. Nothing calls `.animation(.spring(...))`
/// with an inline curve — the resolver needs a name to be able to substitute a
/// cross-fade when Reduce Motion is on.
enum MotionToken: String, CaseIterable, Sendable {
    case pageTurn
    case reveal
    case settle
    case snap
    case ambient

    var animation: Animation {
        switch self {
        case .pageTurn: Motion.pageTurn
        case .reveal: Motion.reveal
        case .settle: Motion.settle
        case .snap: Motion.snap
        case .ambient: Motion.ambient
        }
    }

    var duration: TimeInterval {
        switch self {
        case .pageTurn: 0.55
        case .reveal: 0.40
        case .settle: 0.30
        case .snap: 0.20
        case .ambient: 2.40
        }
    }

    /// What this token becomes when motion is reduced: a cross-fade, quick
    /// enough to feel like a state change rather than a transition. `ambient`
    /// keeps more of its length because it is a slow background shift, not
    /// something the user is waiting on.
    var reducedDuration: TimeInterval {
        self == .ambient ? 0.6 : min(duration, 0.25)
    }
}

/// The reveal styles from section 6. Phase 7 builds the engine; the identifiers
/// exist now because `Note.revealStyleID` and template files already name them.
enum RevealStyle: String, CaseIterable, Sendable, Codable {
    case typewriter
    case fadeUp
    case floatIn
    case blurIn
    case unfurl
    case none

    var displayName: LocalizedStringResource {
        switch self {
        case .typewriter: "Typewriter"
        case .fadeUp: "Fade Up"
        case .floatIn: "Float In"
        case .blurIn: "Blur In"
        case .unfurl: "Unfurl"
        case .none: "None"
        }
    }
}
