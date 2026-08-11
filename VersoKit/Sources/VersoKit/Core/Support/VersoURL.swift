import Foundation

/// The `verso://` links widgets and controls open the app with.
///
/// Lives in `Core` because both the app and the widget extension need it — the
/// widget builds these and the app parses them, and a scheme that drifted
/// between the two would fail silently.
enum VersoURL {
    static let scheme = "verso"

    static var capture: URL {
        URL(string: "\(scheme)://capture")!
    }

    static func note(_ id: UUID) -> URL {
        URL(string: "\(scheme)://note/\(id.uuidString)")!
    }

    enum Destination: Equatable, Sendable {
        case capture
        case note(UUID)
    }

    static func destination(for url: URL) -> Destination? {
        guard url.scheme == scheme else { return nil }

        switch url.host() {
        case "capture":
            return .capture
        case "note":
            guard let raw = url.pathComponents.last, let id = UUID(uuidString: raw) else { return nil }
            return .note(id)
        default:
            return nil
        }
    }
}
