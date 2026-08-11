import Foundation
import OSLog
import SwiftData

/// When an edit is worth keeping.
///
/// Pure, so the judgement calls — how long is long enough, how much change is
/// enough change — are testable and adjustable in one place rather than being
/// scattered through the editor.
struct VersionPolicy: Sendable, Equatable {

    /// No more than one version per this long, however much typing happens.
    var minimumInterval: TimeInterval = 120

    /// Below this many characters of difference, a text edit is not history,
    /// it is a typo being fixed.
    var minimumCharacterChange: Int = 40

    /// A full snapshot every N versions. Deltas are cheap but a long chain is
    /// slow to walk and fragile — one corrupt link would cost everything older.
    var fullSnapshotInterval: Int = 10

    /// How many versions to keep. Older chains are dropped whole.
    var retentionLimit: Int = 120

    /// Structural change is always worth recording: adding or deleting a block
    /// is an act, not a slip of the finger.
    func isStructural(_ previous: NoteSnapshot, _ current: NoteSnapshot) -> Bool {
        previous.blocks.map(\.id) != current.blocks.map(\.id)
            || previous.blocks.count != current.blocks.count
    }

    func shouldRecord(
        previous: NoteSnapshot?,
        current: NoteSnapshot,
        lastRecordedAt: Date?,
        now: Date,
        force: Bool = false
    ) -> Bool {
        guard let previous else { return true }
        guard previous != current else { return false }
        if force || isStructural(previous, current) { return true }

        if let lastRecordedAt, now.timeIntervalSince(lastRecordedAt) < minimumInterval {
            return false
        }
        return changedCharacters(previous, current) >= minimumCharacterChange
            || previous.title != current.title
    }

    /// How much actually changed between two states.
    ///
    /// Comparing the two totals instead — which is what this used to do — reads
    /// a paragraph replaced by another of the same width as no edit at all, and
    /// "revision 0" becoming "revision 1" as nothing whatsoever. A note could be
    /// rewritten indefinitely and history would hold none of it.
    ///
    /// Blocks are matched by id and compared byte for byte: exact when text is
    /// added or deleted, and a fair over-estimate when it is rewritten in place.
    func changedCharacters(_ previous: NoteSnapshot, _ current: NoteSnapshot) -> Int {
        var total = previous.title == current.title ? 0 : max(previous.title.count, current.title.count)

        let before = Dictionary(
            previous.blocks.map { ($0.id, $0.payload) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen: Set<UUID> = []

        for block in current.blocks {
            seen.insert(block.id)
            guard let old = before[block.id] else {
                // A block that did not exist before is all new.
                total += block.payload.count
                continue
            }
            guard old != block.payload else { continue }
            total += zip(old, block.payload).reduce(0) { $1.0 == $1.1 ? $0 : $0 + 1 }
                + abs(old.count - block.payload.count)
        }

        for block in previous.blocks where !seen.contains(block.id) {
            total += block.payload.count
        }
        return total
    }
}

/// Reading and writing version history.
///
/// Deltas are stored backwards — newest to oldest — so walking history from now
/// into the past, which is what the fore-edge does, never has to replay the
/// whole chain from the beginning.
struct VersionStore {

    static let logger = Logger(subsystem: "com.verso.notes", category: "versions")

    let context: ModelContext
    var policy = VersionPolicy()

    init(context: ModelContext, policy: VersionPolicy = VersionPolicy()) {
        self.context = context
        self.policy = policy
    }

    // MARK: - Reading

    /// Newest first, which is the order the fore-edge scrubs in.
    func versions(of note: Note) -> [Version] {
        (note.versions ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    /// The note as it was at a given version.
    ///
    /// A full snapshot decodes on its own. A delta is applied to the state
    /// reconstructed from everything newer than it, walking backwards.
    func snapshot(at index: Int, of note: Note) -> NoteSnapshot? {
        let ordered = versions(of: note)
        guard ordered.indices.contains(index) else { return nil }

        // Start from the newest full snapshot at or before the target, walking
        // from the present backwards.
        var state: NoteSnapshot?
        for position in 0...index {
            let version = ordered[position]
            do {
                if version.isFullSnapshot {
                    state = try SnapshotCoding.decodeSnapshot(version.snapshot)
                } else if let current = state {
                    state = try SnapshotCoding.decodeDelta(version.snapshot).applied(to: current)
                } else {
                    // A delta with nothing newer to apply to. The chain is
                    // broken; stop rather than return a plausible-looking lie.
                    Self.logger.error("Version chain broken at \(position, privacy: .public)")
                    return nil
                }
            } catch {
                Self.logger.error("Unreadable version: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return state
    }

    // MARK: - Writing

    /// Records a version if the policy says the edit was worth keeping.
    ///
    /// The newest version always holds a full snapshot of the *previous* state,
    /// and recording rewrites the one before it as a delta. That keeps the
    /// common read — the most recent versions — a single decode.
    @discardableResult
    func record(_ note: Note, now: Date = Date(), force: Bool = false) -> Version? {
        let current = NoteSnapshot(note)
        let ordered = versions(of: note)
        // The newest version is always a full snapshot, so reading the previous
        // state never has to walk the chain.
        let previous = ordered.first.flatMap { head in
            head.isFullSnapshot ? try? SnapshotCoding.decodeSnapshot(head.snapshot) : nil
        }

        guard policy.shouldRecord(
            previous: previous,
            current: current,
            lastRecordedAt: ordered.first?.createdAt,
            now: now,
            force: force
        ) else { return nil }

        do {
            // Demote the previous head to a delta from the new state, unless it
            // is due to stay a full snapshot as a chain anchor.
            if let head = ordered.first, let previous, head.isFullSnapshot {
                let isAnchor = ordered.count % policy.fullSnapshotInterval == 0
                if !isAnchor {
                    head.snapshot = try SnapshotCoding.encode(NoteDelta.between(current, and: previous))
                    head.isFullSnapshot = false
                }
            }

            let version = Version(
                createdAt: now,
                snapshot: try SnapshotCoding.encode(current),
                isFullSnapshot: true
            )
            context.insert(version)
            version.note = note
            note.versions = (note.versions ?? []) + [version]

            prune(note)
            return version
        } catch {
            Self.logger.error("Could not record version: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Replaces the note's contents with a past state.
    ///
    /// Restoring records the current state first, so undoing a restore is just
    /// scrubbing forward again. History is never destroyed by using it.
    func restore(_ snapshot: NoteSnapshot, to note: Note, now: Date = Date()) {
        record(note, now: now, force: true)

        note.title = snapshot.title
        note.themeID = snapshot.themeID
        note.stockID = snapshot.stockID
        note.revealStyleID = snapshot.revealStyleID

        let existing = Dictionary(uniqueKeysWithValues: note.orderedBlocks.map { ($0.id, $0) })
        var rebuilt: [Block] = []

        for entry in snapshot.blocks.sorted(by: { $0.position < $1.position }) {
            if let block = existing[entry.id] {
                block.typeRaw = entry.type
                block.payload = entry.payload
                rebuilt.append(block)
            } else {
                let block = Block(id: entry.id, position: entry.position, typeRaw: entry.type, payload: entry.payload)
                context.insert(block)
                block.note = note
                rebuilt.append(block)
            }
        }

        for (id, block) in existing where !snapshot.blocks.contains(where: { $0.id == id }) {
            context.delete(block)
        }

        note.blocks = rebuilt
        note.normalizeBlockPositions()
        note.touch(now)
    }

    // MARK: - Private

    /// Drops the oldest versions once the limit is passed.
    ///
    /// Trimming stops at a chain anchor: deleting a full snapshot that later
    /// deltas depend on would quietly break everything older than it.
    private func prune(_ note: Note) {
        let ordered = versions(of: note)
        guard ordered.count > policy.retentionLimit else { return }

        var cut = policy.retentionLimit
        while cut < ordered.count, !ordered[cut].isFullSnapshot {
            cut += 1
        }
        guard cut < ordered.count else { return }

        let doomed = Array(ordered[cut...])
        note.versions = ordered.filter { candidate in !doomed.contains { $0.id == candidate.id } }
        for version in doomed {
            context.delete(version)
        }
    }
}

