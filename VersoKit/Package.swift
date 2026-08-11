// swift-tools-version: 6.2
//
// 6.2 rather than 6.0 because `.iOS(.v26)` was introduced in PackageDescription
// 6.2. Declaring 6.0 fails resolution outright with `'v26' is unavailable`.
import PackageDescription

/// Everything Verso is, apart from the two `@main` declarations that have to
/// live in their own targets.
///
/// The app and the widget extension both need the same engine, the same models
/// and the same store. Sharing that as source between two Xcode targets meant a
/// hand-written membership exception set; sharing it as a package means the
/// dependency is declared once and the compiler enforces the boundary.
///
/// The boundary is deliberately narrow: `VersoScene` and the three widgets are
/// the only public types. Everything else is internal, which is what keeps the
/// engine's shape a decision rather than an accident of what happened to be
/// reachable.
let package = Package(
    name: "VersoKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "VersoKit", targets: ["VersoKit"]),
    ],
    targets: [
        .target(
            name: "VersoKit",
            resources: [
                // `.copy`, not `.process`: process flattens a directory into the
                // bundle root, which leaves every catalogue in one pile and a
                // subdirectory lookup finding nothing. Copy preserves the
                // folder, which is the whole basis on which
                // `BundleResourceLoader` tells a stock from a template.
                .copy("Resources/Themes"),
                .copy("Resources/Stocks"),
                .copy("Resources/Templates"),
                .copy("Resources/Exercises"),
                .copy("Resources/Haptics"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
