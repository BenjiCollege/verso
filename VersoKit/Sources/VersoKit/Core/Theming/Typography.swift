import SwiftUI

/// The type system from section 6.
///
/// Content is New York, chrome is SF Pro, metadata is SF Mono. Scale is
/// 34 / 26 / 20 / 17 / 15 / 13 / 11, body leading is 1.55×, and the measure caps
/// at 68 characters.
///
/// Every role maps onto a system text style so Dynamic Type — including the
/// accessibility sizes — scales it. View code says `.versoText(.body)` and
/// never names a point size.
enum Typography {

    enum Family: Sendable {
        /// New York. `Font.Design.serif` resolves to it on iOS, and because the
        /// size is passed through `ScaledMetric` the optical-size axis is
        /// selected for the size actually rendered, not the base size.
        case content
        /// SF Pro.
        case chrome
        /// SF Mono.
        case mono

        var design: Font.Design {
            switch self {
            case .content: .serif
            case .chrome: .default
            case .mono: .monospaced
            }
        }
    }

    enum Role: Sendable, CaseIterable {
        /// 34 — note titles at rest, Read Mode openers.
        case display
        /// 26 — heading level 1.
        case title
        /// 20 — heading level 2.
        case heading
        /// 17 — heading level 3, and body copy.
        case body
        /// 15 — secondary body, checklist item notes.
        case callout
        /// 13 — captions.
        case footnote
        /// 11 — SF Mono, uppercase, +4% tracking. Timestamps and counts.
        case metadata

        /// 17 — chrome body.
        case chromeBody
        /// 15 — chrome labels, list rows.
        case chromeLabel
        /// 13 — chrome secondary.
        case chromeCaption

        var pointSize: CGFloat {
            switch self {
            case .display: 34
            case .title: 26
            case .heading: 20
            case .body, .chromeBody: 17
            case .callout, .chromeLabel: 15
            case .footnote, .chromeCaption: 13
            case .metadata: 11
            }
        }

        var family: Family {
            switch self {
            case .display, .title, .heading, .body, .callout, .footnote: .content
            case .chromeBody, .chromeLabel, .chromeCaption: .chrome
            case .metadata: .mono
            }
        }

        var weight: Font.Weight {
            switch self {
            case .display, .title: .semibold
            case .heading: .medium
            case .metadata: .medium
            default: .regular
            }
        }

        /// The Dynamic Type style this role scales with.
        var textStyle: Font.TextStyle {
            switch self {
            case .display: .largeTitle
            case .title: .title
            case .heading: .title3
            case .body, .chromeBody: .body
            case .callout, .chromeLabel: .subheadline
            case .footnote, .chromeCaption: .footnote
            case .metadata: .caption2
            }
        }

        /// Line height as a multiple of point size. Body is 1.55×; headings sit
        /// tighter so a two-line title doesn't drift apart.
        var lineHeightMultiple: CGFloat {
            switch self {
            case .display, .title: 1.15
            case .heading: 1.25
            case .metadata: 1.2
            default: 1.55
            }
        }

        /// Letterspacing as a fraction of point size.
        var trackingFraction: CGFloat {
            switch self {
            case .metadata: 0.04
            case .display: -0.01
            default: 0
            }
        }

        var isUppercased: Bool { self == .metadata }
    }

    /// SwiftUI's `lineSpacing` is the gap *between* lines, not the line height,
    /// so the target multiple has to have the font's own line height taken out
    /// of it. `intrinsicLineHeightMultiple` is that baked-in amount.
    static let intrinsicLineHeightMultiple: CGFloat = 1.2

    static func lineSpacing(forSize size: CGFloat, multiple: CGFloat) -> CGFloat {
        max(0, size * (multiple - intrinsicLineHeightMultiple))
    }
}

// MARK: - Application

private struct VersoTextStyle: ViewModifier {
    let role: Typography.Role

    @ScaledMetric private var size: CGFloat

    init(role: Typography.Role) {
        self.role = role
        _size = ScaledMetric(wrappedValue: role.pointSize, relativeTo: role.textStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: role.weight, design: role.family.design))
            .tracking(size * role.trackingFraction)
            .lineSpacing(Typography.lineSpacing(forSize: size, multiple: role.lineHeightMultiple))
            .textCase(role.isUppercased ? .uppercase : nil)
    }
}

/// Constrains content to the 68-character measure at the *scaled* body size, so
/// the measure holds at every Dynamic Type size rather than only the default.
private struct PageMeasure: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = Typography.Role.body.pointSize

    func body(content: Content) -> some View {
        content.frame(maxWidth: Layout.measureWidth(atPointSize: bodySize))
    }
}

extension View {
    /// The only way view code sets type.
    func versoText(_ role: Typography.Role) -> some View {
        modifier(VersoTextStyle(role: role))
    }

    /// Caps width at the measure and centres what's left. On iPhone this is a
    /// no-op; on iPad it keeps the page a page.
    func pageMeasure() -> some View {
        modifier(PageMeasure())
    }
}
