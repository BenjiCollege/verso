import SwiftUI

/// Maps named motion to what should actually run, given the user's Reduce
/// Motion setting.
///
/// Built in Phase 1 rather than retrofitted, because the alternative is
/// auditing every call site later. If a view animates, it asks the resolver;
/// there is no other route.
struct MotionResolver: Equatable, Sendable {

    var reduceMotion: Bool

    init(reduceMotion: Bool = false) {
        self.reduceMotion = reduceMotion
    }

    /// The animation to attach. Under Reduce Motion every spring collapses to
    /// an ease — no bounce, no overshoot, no travel.
    func animation(_ token: MotionToken) -> Animation {
        reduceMotion ? .easeInOut(duration: token.reducedDuration) : token.animation
    }

    /// The transition to pair with it. Under Reduce Motion everything is a
    /// cross-fade; nothing slides, scales or moves.
    func transition(_ token: MotionToken, motion: AnyTransition = .opacity) -> AnyTransition {
        reduceMotion ? .opacity : motion
    }

    /// Per-item entrance delay. Zero under Reduce Motion, so a staggered list
    /// appears at once instead of cascading.
    func staggerDelay(index: Int) -> TimeInterval {
        reduceMotion ? 0 : Double(index) * Motion.staggerGap
    }

    func wordDelay(index: Int) -> TimeInterval {
        reduceMotion ? 0 : Double(index) * Motion.wordGap
    }

    /// The reveal style to actually run. Every style degrades to `.none` under
    /// Reduce Motion — a per-glyph reveal is precisely the effect the setting
    /// exists to suppress.
    func revealStyle(_ style: RevealStyle) -> RevealStyle {
        reduceMotion ? .none : style
    }

    /// Convenience for the common `withAnimation` call.
    ///
    /// `@discardableResult` because the body is almost always a mutation and
    /// only incidentally an expression — `rows.remove(at:)` returns the row it
    /// removed, and animating a removal is not a request to be handed it.
    @MainActor
    @discardableResult
    func run<Result>(_ token: MotionToken, _ body: () throws -> Result) rethrows -> Result {
        try withAnimation(animation(token), body)
    }
}

extension EnvironmentValues {
    /// Resolved once at the root from `accessibilityReduceMotion`.
    @Entry var motion: MotionResolver = MotionResolver()
}

private struct MotionApplier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.environment(\.motion, MotionResolver(reduceMotion: reduceMotion))
    }
}

extension View {
    /// Installs the resolver. Applied once, at the root.
    func versoMotion() -> some View {
        modifier(MotionApplier())
    }

    /// Attaches a named animation to a value change.
    func animation<V: Equatable>(_ token: MotionToken, value: V) -> some View {
        modifier(TokenAnimation(token: token, value: value))
    }
}

private struct TokenAnimation<V: Equatable>: ViewModifier {
    let token: MotionToken
    let value: V

    @Environment(\.motion) private var motion

    func body(content: Content) -> some View {
        content.animation(motion.animation(token), value: value)
    }
}
