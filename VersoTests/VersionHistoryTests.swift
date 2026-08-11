import Foundation
import SwiftData
import Testing
@testable import VersoKit

@Suite("Snapshots and deltas")
struct NoteSnapshotTests {

    private func block(_ id: UUID, _ position: Int, _ text: String) -> NoteSnapshot.BlockSnapshot {
        NoteSnapshot.BlockSnapshot(id: id, position: position, type: "text", payload: Data(text.utf8))
    }

    @Test("An unchanged note produces an empty delta")
    func noChangeIsEmpty() {
        let id = UUID()
        let snapshot = NoteSnapshot(title: "A", blocks: [block(id, 0, "one")])
        #expect(NoteDelta.between(snapshot, and: snapshot).isEmpty)
    }

    /// The property the whole scheme rests on: applying the delta to the newer
    /// state must reproduce the older one exactly.
    @Test("A delta rewinds the newer state to the older one")
    func deltaRoundTrips() {
        let a = UUID(), b = UUID()
        let old = NoteSnapshot(title: "Before", themeID: "foxed", blocks: [block(a, 0, "one"), block(b, 1, "two")])
        let new = NoteSnapshot(title: "After", themeID: "linen", blocks: [block(b, 0, "two edited")])

        let delta = NoteDelta.between(new, and: old)
        #expect(delta.applied(to: new) == old)
    }

    @Test("Only the blocks that changed are carried")
    func deltaIsMinimal() {
        let a = UUID(), b = UUID(), c = UUID()
        let old = NoteSnapshot(blocks: [block(a, 0, "one"), block(b, 1, "two"), block(c, 2, "three")])
        var new = old
        new.blocks[1] = block(b, 1, "two changed")

        let delta = NoteDelta.between(old, and: new)
        #expect(delta.changed.map(\.id) == [b])
        #expect(delta.removed.isEmpty)
        #expect(delta.order == nil, "the order did not change")
    }

    @Test("Reordering is carried without repeating every payload")
    func reorderIsCheap() {
        let a = UUID(), b = UUID()
        let old = NoteSnapshot(blocks: [block(a, 0, "one"), block(b, 1, "two")])
        let new = NoteSnapshot(blocks: [block(b, 0, "two"), block(a, 1, "one")])

        let delta = NoteDelta.between(new, and: old)
        #expect(delta.changed.isEmpty)
        #expect(delta.order == [a, b])
        #expect(delta.applied(to: new) == old)
    }

    @Test("A deleted block comes back when the delta is applied")
    func deletionRewinds() {
        let a = UUID(), b = UUID()
        let old = NoteSnapshot(blocks: [block(a, 0, "one"), block(b, 1, "two")])
        let new = NoteSnapshot(blocks: [block(a, 0, "one")])

        let delta = NoteDelta.between(new, and: old)
        #expect(delta.changed.map(\.id) == [b])
        #expect(delta.applied(to: new) == old)
    }

    /// A field that changed *to* nil has to be distinguishable from a field
    /// that did not change at all.
    @Test("Clearing an optional field survives the round trip")
    func clearingAnOptionalIsCarried() {
        let old = NoteSnapshot(themeID: "foxed", stockID: "ruled")
        let new = NoteSnapshot(themeID: nil, stockID: "ruled")

        let forward = NoteDelta.between(old, and: new)
        #expect(forward.themeID != nil, "a change to nil is still a change")
        #expect(forward.stockID == nil, "an unchanged field is absent")

        let backward = NoteDelta.between(new, and: old)
        #expect(backward.applied(to: new) == old)
    }

    @Test("Snapshots and deltas survive compression")
    func codingRoundTrips() throws {
        let snapshot = NoteSnapshot(
            title: "Long",
            blocks: (0..<40).map { block(UUID(), $0, String(repeating: "paper ", count: 60)) }
        )

        let encoded = try SnapshotCoding.encode(snapshot)
        #expect(try SnapshotCoding.decodeSnapshot(encoded) == snapshot)

        let plain = try BlockCoding.encode(snapshot)
        #expect(encoded.count < plain.count, "compression should earn its place")

        let delta = NoteDelta.between(snapshot, and: NoteSnapshot(title: "Short"))
        #expect(try SnapshotCoding.decodeDelta(SnapshotCoding.encode(delta)) == delta)
    }

    @Test("Empty data compresses and decompresses to itself")
    func emptyCompressionIsSafe() throws {
        #expect(try SnapshotCoding.compress(Data()).isEmpty)
        #expect(try SnapshotCoding.decompress(Data()).isEmpty)
    }
}

@Suite("Version policy")
struct VersionPolicyTests {

    private let policy = VersionPolicy()
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func snapshot(_ title: String, blockCount: Int = 1, padding: Int = 0) -> NoteSnapshot {
        NoteSnapshot(
            title: title,
            blocks: (0..<blockCount).map { index in
                NoteSnapshot.BlockSnapshot(
                    id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", index))")!,
                    position: index,
                    type: "text",
                    payload: Data(repeating: 0x61, count: 10 + padding)
                )
            }
        )
    }

    @Test("The first version is always recorded")
    func firstVersionAlwaysRecords() {
        #expect(policy.shouldRecord(previous: nil, current: snapshot("A"), lastRecordedAt: nil, now: now))
    }

    @Test("An identical note is never recorded twice")
    func identicalIsSkipped() {
        let state = snapshot("A")
        #expect(!policy.shouldRecord(previous: state, current: state, lastRecordedAt: nil, now: now))
    }

    /// Adding or deleting a block is an act, not a slip of the finger, so it
    /// bypasses the interval entirely.
    @Test("Structural change records immediately, however recent the last one")
    func structuralChangeIgnoresTheInterval() {
        #expect(policy.shouldRecord(
            previous: snapshot("A", blockCount: 1),
            current: snapshot("A", blockCount: 2),
            lastRecordedAt: now,
            now: now
        ))
    }

    @Test("A small edit soon after the last version is not history")
    func smallRecentEditIsSkipped() {
        #expect(!policy.shouldRecord(
            previous: snapshot("A", padding: 0),
            current: snapshot("A", padding: 5),
            lastRecordedAt: now.addingTimeInterval(-10),
            now: now
        ))
    }

    @Test("A substantial edit is recorded once the interval has passed")
    func substantialEditRecords() {
        #expect(policy.shouldRecord(
            previous: snapshot("A", padding: 0),
            current: snapshot("A", padding: 200),
            lastRecordedAt: now.addingTimeInterval(-300),
            now: now
        ))
    }

    @Test("A retitle counts even when nothing else moved")
    func retitleRecords() {
        #expect(policy.shouldRecord(
            previous: snapshot("Before"),
            current: snapshot("After"),
            lastRecordedAt: now.addingTimeInterval(-300),
            now: now
        ))
    }

    @Test("Forcing overrides every threshold")
    func forceAlwaysRecords() {
        #expect(policy.shouldRecord(
            previous: snapshot("A", padding: 1),
            current: snapshot("A", padding: 2),
            lastRecordedAt: now,
            now: now,
            force: true
        ))
    }
}

@Suite("Version store")
struct VersionStoreTests {

    private func makeNote(in context: ModelContext, title: String = "Note") throws -> Note {
        let note = Note(title: title)
        context.insert(note)
        let block = try Block(TextPayload(plain: "first"))
        context.insert(block)
        note.append(block)
        return note
    }

    private func edit(_ note: Note, to text: String) throws {
        try note.orderedBlocks[0].store(TextPayload(plain: text))
    }

    private var store: (ModelContext) -> VersionStore {
        { VersionStore(context: $0, policy: VersionPolicy(minimumInterval: 0, minimumCharacterChange: 1, fullSnapshotInterval: 4, retentionLimit: 8)) }
    }

    @Test("Recording keeps the note as it was")
    func recordCapturesState() throws {
        let context = ModelContext(try VersionModelContainer.make())
        let note = try makeNote(in: context)
        let versions = store(context)

        versions.record(note)
        let restored = try #require(versions.snapshot(at: 0, of: note))

        #expect(restored.title == "Note")
        #expect(restored.blocks.count == 1)
    }

    /// The point of the whole feature: walking backwards has to reproduce each
    /// state exactly, however long the delta chain in between.
    @Test("Every version in a long chain reconstructs exactly")
    func longChainReconstructs() throws {
        let context = ModelContext(try VersionModelContainer.make())
        let note = try makeNote(in: context)
        let versions = store(context)

        var expected: [String] = []
        for step in 0..<12 {
            try edit(note, to: "revision \(step)")
            versions.record(note, now: Date(timeIntervalSince1970: 1_760_000_000 + Double(step) * 600))
            expected.append("revision \(step)")
        }

        let ordered = versions.versions(of: note)
        #expect(ordered.count > 1)

        for (index, version) in ordered.enumerated() {
            let snapshot = try #require(versions.snapshot(at: index, of: note), "version \(index) unreadable")
            let payload = try BlockCoding.decode(TextPayload.self, from: snapshot.blocks[0].payload)
            let expectedText = expected[expected.count - 1 - index]
            #expect(payload.plain == expectedText, "version \(index) at \(version.createdAt)")
        }
    }

    @Test("Most versions are deltas, and anchors stay full")
    func chainIsMostlyDeltas() throws {
        let context = ModelContext(try VersionModelContainer.make())
        let note = try makeNote(in: context)
        let versions = store(context)

        for step in 0..<10 {
            try edit(note, to: "revision \(step)")
            versions.record(note, now: Date(timeIntervalSince1970: 1_760_000_000 + Double(step) * 600))
        }

        let ordered = versions.versions(of: note)
        #expect(ordered.first?.isFullSnapshot == true, "the newest is always a full snapshot")
        #expect(ordered.contains { !$0.isFullSnapshot }, "older ones should be deltas")
    }

    @Test("Restoring puts the note back, and records the present first")
    func restoreIsReversible() throws {
        let context = ModelContext(try VersionModelContainer.make())
        let note = try makeNote(in: context)
        let versions = store(context)

        try edit(note, to: "original")
        versions.record(note, now: Date(timeIntervalSince1970: 1_000))

        try edit(note, to: "replaced")
        note.title = "Renamed"
        versions.record(note, now: Date(timeIntervalSince1970: 2_000))

        let countBefore = versions.versions(of: note).count
        let target = try #require(versions.snapshot(at: 1, of: note))
        versions.restore(target, to: note, now: Date(timeIntervalSince1970: 3_000))

        #expect(try note.orderedBlocks[0].decoded(as: TextPayload.self).plain == "original")
        #expect(note.title == "Note")
        // Using history must never destroy it.
        #expect(versions.versions(of: note).count > countBefore)
    }

    @Test("Restoring reinstates a deleted block and removes an added one")
    func restoreRebuildsBlocks() throws {
        let context = ModelContext(try VersionModelContainer.make())
        let note = try makeNote(in: context)
        let versions = store(context)
        versions.record(note, now: Date(timeIntervalSince1970: 1_000))

        let added = try Block(HeadingPayload(level: .two, text: "Added later"))
        context.insert(added)
        note.append(added)
        versions.record(note, now: Date(timeIntervalSince1970: 2_000))

        let original = try #require(versions.snapshot(at: 1, of: note))
        versions.restore(original, to: note, now: Date(timeIntervalSince1970: 3_000))

        #expect(note.orderedBlocks.count == 1)
        #expect(note.orderedBlocks[0].type == .text)
    }

    /// Trimming must never orphan a delta by deleting the full snapshot it
    /// depends on.
    @Test("Pruning stops at a chain anchor, so nothing older breaks")
    func pruningKeepsChainsIntact() throws {
        let context = ModelContext(try VersionModelContainer.make())
        let note = try makeNote(in: context)
        let versions = store(context)

        for step in 0..<20 {
            try edit(note, to: "revision \(step)")
            versions.record(note, now: Date(timeIntervalSince1970: 1_760_000_000 + Double(step) * 600))
        }

        let ordered = versions.versions(of: note)
        #expect(ordered.count <= 12, "retention should have trimmed")

        // Every surviving version must still be readable.
        for index in ordered.indices {
            #expect(versions.snapshot(at: index, of: note) != nil, "version \(index) was orphaned")
        }
    }

    @Test("An index past the end returns nothing rather than trapping")
    func outOfRangeIsSafe() throws {
        let context = ModelContext(try VersionModelContainer.make())
        let note = try makeNote(in: context)
        #expect(store(context).snapshot(at: 5, of: note) == nil)
    }
}

/// Versions carry `.externalStorage` blobs, which an in-memory store handles
/// differently enough to be worth naming.
private enum VersionModelContainer {
    static func make() throws -> ModelContainer {
        try VersoModelContainer.makeInMemory()
    }
}
