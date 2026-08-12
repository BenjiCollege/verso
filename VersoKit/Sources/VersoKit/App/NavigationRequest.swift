import Foundation
import SwiftUI

/// Somewhere for the outside world to say "open this".
///
/// Intents, Spotlight results, Handoff and widget taps all arrive at different
/// moments — sometimes before the scene exists — so they post a request here
/// and the root view acts on it when it can. Without a buffer, an intent that
/// fires during a cold launch is lost.
@MainActor
@Observable
final class NavigationRequest {

    static let shared = NavigationRequest()

    struct Request: Equatable, Sendable {
        var noteID: UUID
        var startRecording: Bool
        /// Distinguishes two requests for the same note, so tapping the same
        /// Spotlight result twice works.
        var issuedAt: Date
    }

    /// A template file that arrived from outside — Files, Mail, AirDrop.
    ///
    /// Buffered for a stronger reason than the rest: opening a
    /// `.versotemplate` *launches* the app, so the import has always finished
    /// before there is any view to show it in.
    struct TemplateArrival: Equatable, Sendable {
        var name: String
        var issuedAt: Date
    }

    private(set) var pending: Request?
    private(set) var arrivedTemplate: TemplateArrival?

    nonisolated init() {}

    func openNote(id: UUID, startRecording: Bool = false) {
        pending = Request(noteID: id, startRecording: startRecording, issuedAt: Date())
    }

    func templateArrived(named name: String) {
        arrivedTemplate = TemplateArrival(name: name, issuedAt: Date())
    }

    /// Called once the request has been acted on.
    func clear() {
        pending = nil
    }

    func clearTemplateArrival() {
        arrivedTemplate = nil
    }
}

/// The activity types Verso advertises.
enum VersoActivity {
    /// Handoff and Spotlight both resolve through this.
    static let openNote = "com.verso.notes.open-note"
    static let noteIDKey = "noteID"

    /// Builds the activity attached to an open note.
    @MainActor
    static func activity(for note: Note) -> NSUserActivity {
        let activity = NSUserActivity(activityType: openNote)
        activity.title = VaultPolicy.listTitle(for: note)
        activity.userInfo = [noteIDKey: note.id.uuidString]
        activity.requiredUserInfoKeys = [noteIDKey]

        // Section 7's exclusions apply to Handoff and Spotlight as much as to
        // widgets: a locked note is advertised nowhere.
        let isPublic = VaultPolicy.isEligibleForIndexing(note)
        activity.isEligibleForHandoff = isPublic
        activity.isEligibleForSearch = isPublic
        activity.isEligibleForPrediction = isPublic

        if isPublic {
            activity.persistentIdentifier = note.id.uuidString
            activity.keywords = Set(note.title.split(separator: " ").map(String.init))
        }
        return activity
    }

    static func noteID(from activity: NSUserActivity) -> UUID? {
        guard activity.activityType == openNote,
              let raw = activity.userInfo?[noteIDKey] as? String
        else { return nil }
        return UUID(uuidString: raw)
    }
}
