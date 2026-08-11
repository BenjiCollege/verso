import AppIntents

/// Tells the App Intents metadata extractor that this package contains intents.
///
/// Without it, intents defined in a package are compiled but never registered:
/// Siri, Shortcuts, the Action Button and Control Centre would all find
/// nothing, and there would be no error to explain why. The app and the widget
/// extension each declare an `AppIntentsPackage` that includes this one.
public struct VersoKitPackage: AppIntentsPackage {
    public init() {}
}
