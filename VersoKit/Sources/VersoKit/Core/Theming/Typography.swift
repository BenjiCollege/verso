import SwiftUI
import UIKit

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

    /// The line height prose is actually set at, reader's adjustment included.
    ///
    /// The single source for it, because three things have to agree or the
    /// app's central idea breaks: the paragraph style TextKit lays the text
    /// out with, the ruled lines `PageBackground` draws, and the minimum height
    /// an empty editor reserves. Ruled paper only means anything while the text
    /// sits on the rules — let the reader stretch the leading without moving
    /// the rules and every line drifts off the paper it is printed on.
    static func contentLineHeightMultiple(_ reading: ReadingPreferences) -> CGFloat {
        Role.body.lineHeightMultiple * reading.lineSpacingScale
    }

    /// The distance between two ruled lines, for a body size that already has
    /// Dynamic Type and the reader's text scale in it.
    static func contentLineHeight(forSize size: CGFloat, reading: ReadingPreferences) -> CGFloat {
        size * contentLineHeightMultiple(reading)
    }
}

// MARK: - Application

private struct VersoTextStyle: ViewModifier {
    let role: Typography.Role

    @ScaledMetric private var size: CGFloat

    @Environment(\.readingPreferences) private var reading

    init(role: Typography.Role) {
        self.role = role
        _size = ScaledMetric(wrappedValue: role.pointSize, relativeTo: role.textStyle)
    }

    /// The reader's adjustment sits on top of Dynamic Type rather than replacing
    /// it, and applies only to content. Chrome keeps the system size, because a
    /// reader who wants larger prose has not asked for a larger toolbar — and
    /// scaling the chrome is how you end up with buttons that no longer fit.
    private var scaledSize: CGFloat {
        role.family == .content ? size * reading.textScale : size
    }

    private var family: Typography.Family {
        role.family == .content ? reading.typeface.family : role.family
    }

    func body(content: Content) -> some View {
        let size = scaledSize
        return content
            .font(.system(size: size, weight: role.weight, design: family.design))
            .tracking(size * role.trackingFraction)
            .lineSpacing(Typography.lineSpacing(
                forSize: size,
                multiple: role.lineHeightMultiple * (role.family == .content ? reading.lineSpacingScale : 1)
            ))
            .textCase(role.isUppercased ? .uppercase : nil)
    }
}

/// What the reader has asked for, on top of the system's own settings.
///
/// Separate from `Theme`, which is the *design* of a page. This is the reader
/// adjusting it: bigger, looser, narrower, or in a face they get on with. A
/// theme is chosen once; these get nudged while reading.
struct ReadingPreferences: Equatable, Sendable {
    var textScale: Double = 1
    var lineSpacingScale: Double = 1
    /// Multiplies the margin, so the column can be narrowed without changing
    /// the type.
    var marginScale: Double = 1
    var typeface: ContentTypeface = .serif

    static let `default` = ReadingPreferences()

    static let textScaleRange: ClosedRange<Double> = 0.8...1.8
    static let lineSpacingRange: ClosedRange<Double> = 0.85...1.5
    static let marginRange: ClosedRange<Double> = 0.6...1.5
}

/// The face content is set in. Chrome is always SF Pro.
enum ContentTypeface: String, CaseIterable, Identifiable, Sendable {
    case serif
    case sans
    case mono

    var id: String { rawValue }

    var family: Typography.Family {
        switch self {
        case .serif: .content
        case .sans: .chrome
        case .mono: .mono
        }
    }

    /// The UIKit equivalent of `family.design`, for the TextKit path.
    ///
    /// SwiftUI prose goes through `Font.Design`; the editor and Read Mode build
    /// a `UIFont` and need the same choice expressed the other way. Kept beside
    /// `family` so the two cannot drift — a reader who picks Mono should get
    /// SF Mono in the toolbar labels *and* in what they are writing.
    var uiDesign: UIFontDescriptor.SystemDesign? {
        switch self {
        case .serif: .serif
        case .sans: .default
        case .mono: .monospaced
        }
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .serif: "New York"
        case .sans: "SF Pro"
        case .mono: "SF Mono"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .serif: "A book face. The default."
        case .sans: "Plainer, and a little wider."
        case .mono: "Fixed width. Good for code and lists."
        }
    }
}

extension EnvironmentValues {
    @Entry var readingPreferences: ReadingPreferences = .default
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
