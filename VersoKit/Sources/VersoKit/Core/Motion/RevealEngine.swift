import CoreGraphics
import Foundation

/// How a reveal is scheduled and what each unit looks like partway through.
///
/// Pure. The reveal is the app showing off, and showing off badly is worse than
/// not doing it — so the timing lives somewhere it can be reasoned about rather
/// than tuned by squinting at a simulator.
///
/// Section 6: applied at note open, in Read Mode, during audio replay and in
/// share-card export. **Never during active typing** — per-glyph animation
/// fights the caret and reads as input lag.
struct RevealPlan: Equatable, Sendable {

    /// What gets revealed one at a time.
    ///
    /// Glyph and word granularity are why the editor is TextKit 2: the reveal
    /// is applied as *rendering attributes*, which change what is drawn without
    /// touching the text storage or forcing a re-layout.
    enum Granularity: Sendable {
        case block
        case word
        case glyph
    }

    var style: RevealStyle
    var granularity: Granularity
    /// Delay added per successive unit.
    var stagger: TimeInterval
    /// How long one unit takes to arrive.
    var unitDuration: TimeInterval

    /// A glyph stagger short enough that a sentence reads as being typed rather
    /// than spelled out.
    static let glyphGap: TimeInterval = 0.012

    static func plan(for style: RevealStyle) -> RevealPlan {
        switch style {
        case .typewriter:
            RevealPlan(style: style, granularity: .glyph, stagger: glyphGap, unitDuration: 0.001)
        case .fadeUp:
            RevealPlan(style: style, granularity: .word, stagger: Motion.wordGap, unitDuration: 0.32)
        case .blurIn:
            RevealPlan(style: style, granularity: .word, stagger: Motion.wordGap, unitDuration: 0.36)
        case .floatIn:
            RevealPlan(style: style, granularity: .block, stagger: Motion.staggerGap * 6, unitDuration: 0.42)
        case .unfurl:
            RevealPlan(style: style, granularity: .block, stagger: Motion.staggerGap * 8, unitDuration: 0.5)
        case .none:
            RevealPlan(style: style, granularity: .block, stagger: 0, unitDuration: 0)
        }
    }

    func delay(forUnit index: Int) -> TimeInterval {
        max(0, Double(index)) * stagger
    }

    func totalDuration(unitCount: Int) -> TimeInterval {
        guard unitCount > 0 else { return 0 }
        return delay(forUnit: unitCount - 1) + unitDuration
    }

    /// How far through its own arrival a given unit is, at a given moment.
    ///
    /// 0 before it starts, 1 once it has landed. A zero-duration unit — the
    /// typewriter's, and `none` — snaps rather than dividing by zero.
    func progress(forUnit index: Int, elapsed: TimeInterval) -> Double {
        guard style != .none else { return 1 }

        let start = delay(forUnit: index)
        guard elapsed > start else { return 0 }
        guard unitDuration > 0 else { return 1 }
        return min((elapsed - start) / unitDuration, 1)
    }

    /// A reveal must never leave the page half-arrived. This is what the
    /// "skip" affordance and the end of the timeline both settle to.
    func isFinished(unitCount: Int, elapsed: TimeInterval) -> Bool {
        elapsed >= totalDuration(unitCount: unitCount)
    }
}

/// What one unit looks like at a given point in its arrival.
struct RevealAppearance: Equatable, Sendable {
    var opacity: Double
    var offsetY: CGFloat
    var blurRadius: CGFloat
    /// Vertical scale, anchored at the top. Only `unfurl` uses it.
    var scaleY: Double

    static let visible = RevealAppearance(opacity: 1, offsetY: 0, blurRadius: 0, scaleY: 1)

    /// Eased so units decelerate into place rather than arriving at a constant
    /// rate, which reads as mechanical.
    private static func eased(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }

    static func at(progress: Double, style: RevealStyle) -> RevealAppearance {
        let t = eased(progress)

        return switch style {
        case .none:
            .visible
        case .typewriter:
            // Glyphs appear; they do not fade. A typewriter has no dissolve.
            RevealAppearance(opacity: progress > 0 ? 1 : 0, offsetY: 0, blurRadius: 0, scaleY: 1)
        case .fadeUp:
            RevealAppearance(opacity: t, offsetY: (1 - t) * 10, blurRadius: 0, scaleY: 1)
        case .floatIn:
            RevealAppearance(opacity: t, offsetY: (1 - t) * 26, blurRadius: 0, scaleY: 1)
        case .blurIn:
            RevealAppearance(opacity: t, offsetY: 0, blurRadius: (1 - t) * 8, scaleY: 1)
        case .unfurl:
            RevealAppearance(opacity: min(t * 1.6, 1), offsetY: 0, blurRadius: 0, scaleY: 0.2 + t * 0.8)
        }
    }
}

/// Splits text into the units a plan reveals.
enum RevealUnits {

    /// UTF-16 ranges, because they are handed to `NSTextLayoutManager` and to
    /// `NSRange`. Counting `Character`s would drift on any note with an emoji.
    static func ranges(in text: String, granularity: RevealPlan.Granularity) -> [NSRange] {
        let ns = text as NSString
        guard ns.length > 0 else { return [] }

        switch granularity {
        case .block:
            return [NSRange(location: 0, length: ns.length)]

        case .glyph:
            // Composed character sequences, so a flag or a family arrives whole
            // rather than one scalar at a time.
            var result: [NSRange] = []
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byComposedCharacterSequences) { _, range, _, _ in
                result.append(range)
            }
            return result

        case .word:
            // Trailing whitespace rides with the word before it, so no gap in
            // the paragraph is ever left un-inked.
            var result: [NSRange] = []
            var cursor = 0
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { _, range, _, _ in
                let end = range.upperBound
                result.append(NSRange(location: cursor, length: end - cursor))
                cursor = end
            }
            if cursor < ns.length {
                result.append(NSRange(location: cursor, length: ns.length - cursor))
            }
            return result.isEmpty ? [NSRange(location: 0, length: ns.length)] : result
        }
    }

    static func count(in text: String, granularity: RevealPlan.Granularity) -> Int {
        ranges(in: text, granularity: granularity).count
    }
}

extension MotionResolver {
    /// The plan actually used, after Reduce Motion has had its say.
    ///
    /// Every style degrades to `.none` under the setting, which is the whole
    /// point: a per-glyph reveal is precisely the effect it exists to suppress.
    func revealPlan(for style: RevealStyle) -> RevealPlan {
        RevealPlan.plan(for: revealStyle(style))
    }
}
