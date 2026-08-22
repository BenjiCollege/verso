import Foundation
import SwiftData
import Testing
@testable import VersoKit

/// `Testing` exports a `Tag` of its own — the one you attach to a suite — so
/// the bare name is ambiguous in any file that imports both. Everywhere below,
/// the model is what is meant.
private typealias Tag = VersoKit.Tag

/// Guards the CloudKit rules in section 4. These are the constraints that fail
/// at first sync rather than at compile time, which is exactly why they need a
/// test.
@Suite("SwiftData and CloudKit schema validity")
struct SchemaValidityTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try VersoModelContainer.makeInMemory())
    }

    @Test("The schema contains every model and builds a container")
    func schemaBuilds() throws {
        #expect(VersoModelContainer.schema.entities.count == 8)
        let names = Set(VersoModelContainer.schema.entities.map(\.name))
        #expect(names == ["Note", "Block", "MetricEntry", "Version", "AudioAsset", "ImageAsset", "Folder", "Tag"])
        _ = try VersoModelContainer.makeInMemory()
    }

    /// CloudKit requires every stored property to have a default or be
    /// optional. If any model gains a property without one, this stops
    /// compiling — which is the earliest possible failure.
    @Test("Every model is constructible with no arguments")
    func everyModelHasCompleteDefaults() throws {
        let context = try makeContext()
        context.insert(Note())
        context.insert(Block())
        context.insert(MetricEntry())
        context.insert(Version())
        context.insert(AudioAsset())
        context.insert(ImageAsset())
        context.insert(Folder())
        context.insert(Tag())
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Note>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Block>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<MetricEntry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Version>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AudioAsset>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ImageAsset>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Folder>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Tag>()) == 1)
    }

    @Test("A CloudKit-backed configuration is constructible for the private database")
    func cloudKitConfigurationIsWellFormed() {
        let configuration = ModelConfiguration(
            "Verso",
            schema: VersoModelContainer.schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .private(VersoModelContainer.cloudKitContainerIdentifier)
        )
        #expect(configuration.name == "Verso")
        #expect(VersoModelContainer.cloudKitContainerIdentifier.hasPrefix("iCloud."))
    }

    @Test("Deleting a note cascades to its versions, audio and pictures")
    func deleteCascades() throws {
        let context = try makeContext()
        let note = Note(title: "Ephemeral")
        let version = Version(snapshot: Data([0x01]))
        let audio = AudioAsset(duration: 12)
        let image = ImageAsset(data: Data([0xFF, 0xD8]))

        context.insert(note)
        context.insert(version)
        context.insert(audio)
        context.insert(image)
        version.note = note
        audio.note = note
        image.note = note
        try context.save()

        context.delete(note)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Note>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Version>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<AudioAsset>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ImageAsset>()) == 0)
    }

    @Test("A block with no note is legal, since every relationship is optional")
    func detachedBlockIsLegal() throws {
        let context = try makeContext()
        let block = try Block(HeadingPayload(level: .one, text: "Orphan"))
        context.insert(block)
        try context.save()

        #expect(block.note == nil)
        #expect(try context.fetchCount(FetchDescriptor<Block>()) == 1)
    }

    // MARK: - Ordering

    @Test("Block positions stay dense after insert, move and delete")
    func blockPositionsStayDense() throws {
        let context = try makeContext()
        let note = Note(title: "Ordered")
        context.insert(note)

        for index in 0..<5 {
            let block = try Block(HeadingPayload(level: .three, text: "\(index)"))
            context.insert(block)
            note.append(block)
        }
        #expect(note.orderedBlocks.map(\.position) == [0, 1, 2, 3, 4])

        note.moveBlocks(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(note.orderedBlocks.map(\.position) == [0, 1, 2, 3, 4])
        #expect(try note.orderedBlocks.map { try $0.decoded(as: HeadingPayload.self).text } == ["1", "2", "0", "3", "4"])

        let removed = note.orderedBlocks[2]
        note.remove(removed)
        context.delete(removed)
        #expect(note.orderedBlocks.map(\.position) == [0, 1, 2, 3])
        #expect(try note.orderedBlocks.map { try $0.decoded(as: HeadingPayload.self).text } == ["1", "2", "3", "4"])

        let inserted = try Block(HeadingPayload(level: .three, text: "new"))
        context.insert(inserted)
        note.insert(inserted, at: 1)
        #expect(note.orderedBlocks.map(\.position) == [0, 1, 2, 3, 4])
        #expect(try note.orderedBlocks[1].decoded(as: HeadingPayload.self).text == "new")

        try context.save()
    }

    @Test("Inserting past the end clamps rather than trapping")
    func insertClamps() throws {
        let context = try makeContext()
        let note = Note()
        context.insert(note)

        let block = try Block(DividerPayload())
        context.insert(block)
        note.insert(block, at: 99)

        #expect(note.orderedBlocks.count == 1)
        #expect(note.orderedBlocks[0].position == 0)
    }

    // MARK: - Tag dedupe

    @Test("findOrCreate is case-insensitive and does not duplicate")
    func tagFindOrCreate() throws {
        let context = try makeContext()
        let first = try Tag.findOrCreate(named: "Reading", in: context)
        let second = try Tag.findOrCreate(named: "  reading ", in: context)

        #expect(first.id == second.id)
        #expect(try context.fetchCount(FetchDescriptor<Tag>()) == 1)
    }

    @Test("mergeDuplicates collapses tags two devices created independently")
    func tagMergeDuplicates() throws {
        let context = try makeContext()
        let note = Note(title: "Tagged")
        let a = Tag(name: "Reading")
        let b = Tag(name: "reading")
        context.insert(note)
        context.insert(a)
        context.insert(b)
        note.tags = [a, b]
        try context.save()

        try Tag.mergeDuplicates(in: context)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Tag>()) == 1)
        #expect(note.tags?.count == 1)
    }

    // MARK: - Metric series

    @Test("Metric entries from unrelated features share one queryable series store")
    func metricSeriesIsUniform() throws {
        let context = try makeContext()
        let day = Date(timeIntervalSince1970: 1_760_000_000)

        // Two minutes apart, because two sets are: identical timestamps would
        // leave the sort below with a tie to break however it liked.
        context.insert(MetricEntry(seriesID: "bench-press", groupID: "set-1", label: "Bench press", value: 80, unit: "kg", recordedAt: day))
        context.insert(MetricEntry(seriesID: "bench-press", groupID: "set-2", label: "Bench press", value: 82.5, unit: "kg", recordedAt: day.addingTimeInterval(120)))
        context.insert(MetricEntry(seriesID: "water", label: "Water", value: 500, unit: "ml", recordedAt: day))
        try context.save()

        // The same query shape serves both, which is the point of seriesID.
        func series(_ id: String) throws -> [MetricEntry] {
            try context.fetch(
                FetchDescriptor<MetricEntry>(
                    predicate: #Predicate { $0.seriesID == id },
                    sortBy: [SortDescriptor(\.recordedAt)]
                )
            )
        }

        #expect(try series("bench-press").count == 2)
        #expect(try series("water").count == 1)
        #expect(try series("bench-press").map(\.groupID) == ["set-1", "set-2"])
    }
}
