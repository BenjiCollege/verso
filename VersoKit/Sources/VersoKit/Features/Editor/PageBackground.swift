import SwiftUI

/// The page.
///
/// Opaque, matte, grain-textured — never a glass material. The chrome above it
/// is translucent; that contrast is the app's identity and this view is the
/// half of it that must stay solid.
struct PageBackground: View {
    @Environment(\.theme) private var theme
    @Environment(\.stock) private var stock

    @Environment(\.readingPreferences) private var reading

    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = Typography.Role.body.pointSize

    /// Rules track the body line height, so ruled paper lines up with the text
    /// at every Dynamic Type size instead of only the default — and now at
    /// every reader setting too. The text scale and the leading both move the
    /// prose, so both have to move the rules or the writing sits between them.
    /// `Typography.contentLineHeight` is the one place that number is decided.
    private var lineHeight: CGFloat {
        Typography.contentLineHeight(forSize: bodySize * reading.textScale, reading: reading)
    }

    var body: some View {
        theme.stock
            .overlay { StockPattern(stock: stock, theme: theme, lineHeight: lineHeight) }
            .overlay { GrainOverlay(intensity: theme.grain) }
            .accessibilityHidden(true)
    }
}

/// Draws a stock's pattern from its parameters. There is no per-stock branch
/// beyond the four drawing primitives — `legal` and `manuscript` differ from
/// `ruled` only by the parameters in their JSON.
struct StockPattern: View {
    let stock: Stock
    let theme: Theme
    let lineHeight: CGFloat

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let spacing = max(lineHeight * stock.spacingMultiple, 4)
            let ruleColor = theme.rule.opacity(stock.opacity)

            if stock.alternateRowTint > 0 {
                drawAlternatingRows(in: &context, size: size, spacing: spacing)
            }

            switch stock.pattern {
            case .none:
                break
            case .horizontalRules:
                drawHorizontalRules(in: &context, size: size, spacing: spacing, color: ruleColor)
            case .dots:
                drawDots(in: &context, size: size, spacing: spacing, color: ruleColor)
            case .grid:
                drawGrid(in: &context, size: size, spacing: spacing, color: ruleColor)
            }

            if let margin = stock.marginRule {
                drawMarginRule(margin, in: &context, size: size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .drawingGroup()
    }

    private func drawHorizontalRules(in context: inout GraphicsContext, size: CGSize, spacing: CGFloat, color: Color) {
        var y = spacing
        while y < size.height {
            context.stroke(
                Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                with: .color(color),
                lineWidth: stock.lineWidth
            )
            if stock.showsBaselineGuides {
                let guideY = y - spacing / 2
                context.stroke(
                    Path { $0.move(to: CGPoint(x: 0, y: guideY)); $0.addLine(to: CGPoint(x: size.width, y: guideY)) },
                    with: .color(color.opacity(0.4)),
                    style: StrokeStyle(lineWidth: stock.lineWidth, dash: [2, 4])
                )
            }
            y += spacing
        }
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize, spacing: CGFloat, color: Color) {
        drawHorizontalRules(in: &context, size: size, spacing: spacing, color: color)
        var x = spacing
        while x < size.width {
            context.stroke(
                Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                with: .color(color),
                lineWidth: stock.lineWidth
            )
            x += spacing
        }
    }

    private func drawDots(in context: inout GraphicsContext, size: CGSize, spacing: CGFloat, color: Color) {
        let radius = max(stock.dotRadius, 0.5)
        var y = spacing
        while y < size.height {
            var x = spacing
            while x < size.width {
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(color)
                )
                x += spacing
            }
            y += spacing
        }
    }

    private func drawAlternatingRows(in context: inout GraphicsContext, size: CGSize, spacing: CGFloat) {
        let tint = theme.rule.opacity(stock.alternateRowTint * stock.opacity)
        var y: CGFloat = 0
        var isTinted = false
        while y < size.height {
            if isTinted {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: spacing)), with: .color(tint))
            }
            isTinted.toggle()
            y += spacing
        }
    }

    private func drawMarginRule(_ margin: Stock.MarginRule, in context: inout GraphicsContext, size: CGSize) {
        let x = margin.inset
        guard x < size.width else { return }
        let color = (margin.usesAccent ? theme.accent : theme.rule).opacity(margin.opacity)
        context.stroke(
            Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
            with: .color(color),
            lineWidth: margin.width
        )
    }
}
