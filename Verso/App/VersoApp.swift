import AppIntents
import SwiftUI
import VersoKit

/// The app target holds `@main` and nothing else.
///
/// Everything Verso does lives in `VersoKit`, which the widget extension
/// depends on too — so there is exactly one copy of the engine, the models and
/// the store, and the compiler enforces that rather than a project-file
/// membership list.
@main
struct VersoApp: App {
    var body: some Scene {
        VersoScene()
    }
}

/// Registers the package's App Intents with the app.
///
/// Intents living in a package are compiled but not registered unless the app
/// says it includes them — Shortcuts would simply be empty, with nothing to
/// explain why.
struct VersoAppPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [VersoKitPackage.self]
    }
}
