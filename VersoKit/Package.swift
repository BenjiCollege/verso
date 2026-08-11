// swift-tools-version: 6.0
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
                // `.process` rather than `.copy`, so these are addressable
                // through `Bundle.module` with their directory structure intact.
                // That replaces the flat-bundle fallback `BundleResourceLoader`
                // needed when Xcode's synchronized groups were doing the
                // packaging.
                .process("Resources/Themes"),
                .process("Resources/Stocks"),
                .process("Resources/Templates"),
                .process("Resources/Exercises"),
                .process("Resources/Haptics"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
