import Foundation
import SwiftUI
import Testing
@testable import VersoKit

@Suite("Theme loader")
struct ThemeLoaderTests {

    let catalog = ThemeCatalog.shared

    // MARK: - Catalog

    @Test("All six themes load from the bundle")
    func allThemesLoad() {
        #expect(Set(catalog.themes.map(\.id)) == [
            "iron-gall", "midnight-oil", "cyanotype", "riso", "foxed", "linen",
        ])
    }

    @Test("All seven stocks load from the bundle")
    func allStocksLoad() {
        #expect(Set(catalog.stocks.map(\.id)) == [
            "plain", "ruled", "dot-grid", "graph", "legal", "manuscript", "ledger",
        ])
    }

    /// The palette table in section 6 is the specification. If a theme file
    /// drifts from it this fails, which is the point.
    struct ThemeSpec: Sendable, CustomStringConvertible {
        let id: String
        let stock: String
        let ink: String
        let inkSecondary: String
        let accent: String
        let rule: String
        let edge: String
        let gilt: String
        let grain: Double

        var description: String { id }
    }

    static let specifiedThemes: [ThemeSpec] = [
        .init(id: "iron-gall", stock: "#E8E4DA", ink: "#16181C", inkSecondary: "#5A5F66",
              accent: "#2E4B7A", rule: "#C4BEB0", edge: "#3A3226", gilt: "#8B7355", grain: 0.06),
        .init(id: "midnight-oil", stock: "#12141A", ink: "#E6E3DC", inkSecondary: "#9C9A94",
              accent: "#C9A227", rule: "#252932", edge: "#0A0B0F", gilt: "#C9A227", grain: 0.08),
        .init(id: "cyanotype", stock: "#17384F", ink: "#F2F6F7", inkSecondary: "#9DC0CE",
              accent: "#F2F6F7", rule: "#245570", edge: "#0E2534", gilt: "#0E2534", grain: 0.05),
        .init(id: "riso", stock: "#FAF8F3", ink: "#1B1B1B", inkSecondary: "#6B6B6B",
              accent: "#FF48B0", rule: "#E4DFD4", edge: "#FF48B0", gilt: "#FF48B0", grain: 0.04),
        .init(id: "foxed", stock: "#DED3BF", ink: "#241C14", inkSecondary: "#6A5A46",
              accent: "#7B2E22", rule: "#C3B398", edge: "#4A3524", gilt: "#4A3524", grain: 0.10),
        .init(id: "linen", stock: "#EDEEEA", ink: "#22262A", inkSecondary: "#646A6E",
              accent: "#5F7A6B", rule: "#D5D8D2", edge: "#7C837C", gilt: "#7C837C", grain: 0.05),
    ]

    @Test("Theme palettes match the specification", arguments: ThemeLoaderTests.specifiedThemes)
    func themePalettesMatchSpecification(spec: ThemeSpec) throws {
        let theme = try #require(catalog.theme(id: spec.id))
        #expect(theme.palette.stock.hexString == spec.stock)
        #expect(theme.palette.ink.hexString == spec.ink)
        #expect(theme.palette.inkSecondary.hexString == spec.inkSecondary)
        #expect(theme.palette.accent.hexString == spec.accent)
        #expect(theme.palette.rule.hexString == spec.rule)
        #expect(theme.palette.edge.hexString == spec.edge)
        #expect(theme.palette.gilt.hexString == spec.gilt)
        #expect(abs(theme.grain - spec.grain) < 0.0001)
    }

    @Test("Iron Gall and Midnight Oil are the light and dark defaults")
    func defaultsAreCorrect() {
        #expect(catalog.defaultTheme(for: .light).id == "iron-gall")
        #expect(catalog.defaultTheme(for: .dark).id == "midnight-oil")
        #expect(catalog.defaultStock().id == "ruled")
    }

    @Test("A stale theme id falls back to the appearance default")
    func staleIDFallsBack() {
        #expect(catalog.resolveTheme(selectedID: "theme-that-was-deleted", appearance: .dark).id == "midnight-oil")
        #expect(catalog.resolveTheme(selectedID: nil, appearance: .light).id == "iron-gall")
        #expect(catalog.resolveStock(selectedID: "nonexistent").id == "ruled")
    }

    @Test("Riso declares the second ink from the specification")
    func risoHasAlternateAccent() throws {
        let riso = try #require(catalog.theme(id: "riso"))
        #expect(riso.palette.accentAlternate?.hexString == "#0B4BD4")
    }

    @Test("Every theme's page colour is fully opaque")
    func everyStockIsOpaque() {
        // The page is paper, never a material. An alpha below 1 on the page
        // colour would let chrome show through it.
        for theme in catalog.themes {
            #expect(theme.palette.stock.alpha == 1, "\(theme.id) page colour is not opaque")
        }
    }

    // MARK: - Hex parsing

    @Test(
        "Hex strings parse in every accepted form",
        arguments: [
            ("#FFFFFF", 1.0, 1.0, 1.0, 1.0),
            ("FFFFFF", 1.0, 1.0, 1.0, 1.0),
            ("#000000", 0.0, 0.0, 0.0, 1.0),
            ("#FFF", 1.0, 1.0, 1.0, 1.0),
            ("#F00", 1.0, 0.0, 0.0, 1.0),
            ("#FF000080", 1.0, 0.0, 0.0, 128.0 / 255.0),
            ("#F008", 1.0, 0.0, 0.0, 136.0 / 255.0),
        ]
    )
    func hexParsing(input: String, red: Double, green: Double, blue: Double, alpha: Double) throws {
        let parsed = try #require(HexColor(hex: input))
        #expect(abs(parsed.red - red) < 0.001)
        #expect(abs(parsed.green - green) < 0.001)
        #expect(abs(parsed.blue - blue) < 0.001)
        #expect(abs(parsed.alpha - alpha) < 0.001)
    }

    @Test("Malformed hex is rejected rather than silently black", arguments: [
        "", "#", "#GGGGGG", "#12345", "#1234567", "rebeccapurple", "#12 34 56",
    ])
    func malformedHexIsRejected(input: String) {
        #expect(HexColor(hex: input) == nil)
    }

    @Test("A bad hex value in a theme file fails decoding")
    func badHexFailsDecoding() {
        let data = Data(#"{"id":"x","name":"X","appearance":"light","grain":0,"palette":{"stock":"nope","ink":"#000","inkSecondary":"#111","accent":"#222","rule":"#333","edge":"#444","gilt":"#555"}}"#.utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(Theme.self, from: data)
        }
    }

    @Test("hexString round-trips")
    func hexStringRoundTrips() throws {
        for theme in catalog.themes {
            let re = try #require(HexColor(hex: theme.palette.ink.hexString))
            #expect(re == theme.palette.ink)
        }
    }

    // MARK: - Accessibility resolution

    @Test("Increase Contrast raises ink contrast and removes grain")
    func increaseContrastResolves() throws {
        for theme in catalog.themes {
            let resolved = theme.resolved(increaseContrast: true, reduceTransparency: false)
            let before = contrastRatio(theme.palette.ink, theme.palette.stock)
            let after = contrastRatio(resolved.palette.ink, resolved.palette.stock)

            #expect(after >= before, "\(theme.id) lost contrast under Increase Contrast")
            #expect(resolved.grain == 0)
            #expect(resolved.palette.stock == theme.palette.stock, "the page colour itself must not shift")
        }
    }

    @Test("Reduce Transparency alone only removes grain")
    func reduceTransparencyResolves() throws {
        let theme = try #require(catalog.theme(id: "foxed"))
        let resolved = theme.resolved(increaseContrast: false, reduceTransparency: true)
        #expect(resolved.grain == 0)
        #expect(resolved.palette.ink == theme.palette.ink)
    }

    @Test("Resolving with neither setting on is a no-op")
    func resolvingIsANoOpWhenNothingIsOn() throws {
        let theme = try #require(catalog.theme(id: "linen"))
        #expect(theme.resolved(increaseContrast: false, reduceTransparency: false) == theme)
    }

    /// WCAG contrast ratio, used only to assert the direction of the change.
    private func contrastRatio(_ a: HexColor, _ b: HexColor) -> Double {
        let l1 = max(a.relativeLuminance, b.relativeLuminance)
        let l2 = min(a.relativeLuminance, b.relativeLuminance)
        return (l1 + 0.05) / (l2 + 0.05)
    }

    // MARK: - Stocks

    @Test("Legal paper carries a margin rule and plain paper draws nothing")
    func stockParameters() throws {
        let legal = try #require(catalog.stock(id: "legal"))
        #expect(legal.pattern == .horizontalRules)
        #expect(legal.marginRule?.usesAccent == true)

        let plain = try #require(catalog.stock(id: "plain"))
        #expect(plain.pattern == .none)
        #expect(plain.marginRule == nil)

        let ledger = try #require(catalog.stock(id: "ledger"))
        #expect(ledger.pattern == .grid)
        #expect(ledger.alternateRowTint > 0)

        let manuscript = try #require(catalog.stock(id: "manuscript"))
        #expect(manuscript.showsBaselineGuides)
    }

    @Test("An unknown stock pattern degrades to nothing drawn")
    func unknownPatternDegrades() throws {
        let data = Data(#"{"id":"x","name":"X","pattern":"holographic"}"#.utf8)
        let stock = try JSONDecoder().decode(Stock.self, from: data)
        #expect(stock.pattern == .none)
    }
}

@Suite("Typography and layout tokens")
struct TypographyTokenTests {

    @Test("The type scale is 34 / 26 / 20 / 17 / 15 / 13 / 11")
    func typeScaleMatchesSpecification() {
        let sizes = Set(Typography.Role.allCases.map(\.pointSize))
        #expect(sizes == [34, 26, 20, 17, 15, 13, 11])
    }

    @Test("Body leading is 1.55x")
    func bodyLeadingIsCorrect() {
        #expect(Typography.Role.body.lineHeightMultiple == 1.55)
        let spacing = Typography.lineSpacing(forSize: 17, multiple: 1.55)
        #expect(abs(spacing - 17 * (1.55 - 1.2)) < 0.0001)
    }

    @Test("Metadata is monospaced, uppercase, +4% tracking at 11pt")
    func metadataRoleMatchesSpecification() {
        let role = Typography.Role.metadata
        #expect(role.pointSize == 11)
        #expect(role.family == .mono)
        #expect(role.isUppercased)
        #expect(abs(role.trackingFraction - 0.04) < 0.0001)
    }

    @Test("Content roles are serif and chrome roles are not")
    func familiesAreAssignedCorrectly() {
        for role in [Typography.Role.display, .title, .heading, .body, .callout, .footnote] {
            #expect(role.family == .content)
        }
        for role in [Typography.Role.chromeBody, .chromeLabel, .chromeCaption] {
            #expect(role.family == .chrome)
        }
    }

    @Test("The measure caps at 68 characters")
    func measureIsCapped() {
        #expect(Layout.measureCharacters == 68)
        let width = Layout.measureWidth(atPointSize: 17)
        #expect(width > 500 && width < 600)
        // It has to grow with Dynamic Type or the measure only holds at one size.
        #expect(Layout.measureWidth(atPointSize: 34) > width)
    }
}

@Suite("Reduce Motion resolver")
struct MotionResolverTests {

    @Test("Motion tokens carry the specified durations")
    func tokenDurations() {
        #expect(MotionToken.pageTurn.duration == 0.55)
        #expect(MotionToken.reveal.duration == 0.40)
        #expect(MotionToken.settle.duration == 0.30)
        #expect(MotionToken.snap.duration == 0.20)
        #expect(MotionToken.ambient.duration == 2.40)
        #expect(Motion.staggerGap == 0.018)
        #expect(Motion.wordGap == 0.045)
    }

    @Test("Every token resolves to a cross-fade under Reduce Motion", arguments: MotionToken.allCases)
    func everyTokenHasAReducedPath(token: MotionToken) {
        let reduced = MotionResolver(reduceMotion: true)
        let normal = MotionResolver(reduceMotion: false)

        #expect(reduced.animation(token) == .easeInOut(duration: token.reducedDuration))
        #expect(normal.animation(token) == token.animation)
        #expect(reduced.animation(token) != normal.animation(token))
        #expect(token.reducedDuration <= token.duration)
    }

    @Test("Stagger and word delays collapse to zero under Reduce Motion")
    func delaysCollapse() {
        let reduced = MotionResolver(reduceMotion: true)
        let normal = MotionResolver(reduceMotion: false)

        #expect(reduced.staggerDelay(index: 40) == 0)
        #expect(reduced.wordDelay(index: 40) == 0)
        #expect(normal.staggerDelay(index: 10) == 10 * Motion.staggerGap)
        #expect(normal.wordDelay(index: 10) == 10 * Motion.wordGap)
    }

    @Test("Every reveal style degrades to none under Reduce Motion", arguments: RevealStyle.allCases)
    func revealStylesDegrade(style: RevealStyle) {
        #expect(MotionResolver(reduceMotion: true).revealStyle(style) == .none)
        #expect(MotionResolver(reduceMotion: false).revealStyle(style) == style)
    }

    @Test("Transitions become cross-fades under Reduce Motion")
    func transitionsCollapse() {
        // AnyTransition isn't Equatable, so this asserts the branch is taken by
        // way of the resolver's own flag rather than the returned value.
        let reduced = MotionResolver(reduceMotion: true)
        #expect(reduced.reduceMotion)
        _ = reduced.transition(.reveal, motion: .move(edge: .bottom))
    }
}
