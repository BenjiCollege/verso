import Foundation
import SwiftData

/// Walks the library and collects everywhere a reminder is pinned to.
///
/// Two sources, one shape: `place` blocks and the `place` field on a checklist
/// item. The budget downstream never learns which was which.
enum GeofenceCandidateBuilder {

    /// A place reminder is actionable while there is still something to do.
    ///
    /// - A checklist item's place: while the item is unchecked.
    /// - A `place` block: while its note still has an unchecked item, or has no
    ///   checklist at all — a standalone "remind me when I get there" note has
    ///   nothing to check off, and should not be silently dormant forever.
    ///
    /// A trashed or hidden note is never actionable.
    static func candidates(in notes: [Note]) -> [GeofenceCandidate] {
        notes.flatMap { candidates(in: $0) }
    }

    static func candidates(in note: Note) -> [GeofenceCandidate] {
        guard !note.isTrashed, !note.isHidden else { return [] }

        var results: [GeofenceCandidate] = []
        var checklistCount = 0
        var uncheckedCount = 0

        // Two passes: the note's own state has to be known before a place block
        // can be judged actionable, and a place block may appear first.
        var placeBlocks: [(blockID: UUID, target: PlaceTarget)] = []

        for block in note.orderedBlocks {
            switch block.type {
            case .checklist:
                guard let payload = try? block.decoded(as: ChecklistPayload.self) else { continue }
                checklistCount += 1
                for item in payload.items {
                    if !item.checked { uncheckedCount += 1 }
                    guard let place = item.place else { continue }
                    let target = place.target(named: item.label)
                    guard target.isResolvable else { continue }

                    results.append(
                        GeofenceCandidate(
                            id: GeofenceIdentity(noteID: note.id, blockID: block.id, itemID: item.id),
                            target: target,
                            center: target.coordinate,
                            isActionable: !item.checked,
                            lastActivity: note.modifiedAt,
                            noteTitle: note.title
                        )
                    )
                }

            case .place:
                guard let payload = try? block.decoded(as: PlacePayload.self), payload.target.isResolvable else {
                    continue
                }
                placeBlocks.append((block.id, payload.target))

            default:
                continue
            }
        }

        let noteHasWorkLeft = checklistCount == 0 || uncheckedCount > 0
        for entry in placeBlocks {
            results.append(
                GeofenceCandidate(
                    id: GeofenceIdentity(noteID: note.id, blockID: entry.blockID),
                    target: entry.target,
                    center: entry.target.coordinate,
                    isActionable: noteHasWorkLeft,
                    lastActivity: note.modifiedAt,
                    noteTitle: note.title
                )
            )
        }

        return results
    }
}

/// Reads the library off the main actor, so building candidates across a whole
/// library never lands in the middle of a scroll.
@ModelActor
actor GeofenceCandidateSource {
    func candidates() -> [GeofenceCandidate] {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { !$0.isTrashed && !$0.isHidden }
        )
        let notes = (try? modelContext.fetch(descriptor)) ?? []
        return GeofenceCandidateBuilder.candidates(in: notes)
    }
}
