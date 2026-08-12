import Foundation
import SwiftData
import Testing
@testable import VersoKit

/// Covers the export paths that draw the page rather than describing it.
///
/// These exist because of a crash that shipped. `ExportPage` rendered blocks
/// through the *editing* views, eight of which read environment objects the
/// export never built — and a missing `@Environment` observable is a trap. Any
/// note holding a paragraph, a checklist or a timer took the app down on share.
/// Markdown export was fine throughout, which is why nothing caught it.
@Suite("Page export")
@MainActor
struct PageExportTests {

    private let theme = ThemeCatalog.shared.resolveTheme(selectedID: nil, appearance: .light)
    private let stock = ThemeCatalog.shared.resolveStock(selectedID: nil)

    /// One of every block type the printed path special-cases, plus the ones it
    /// leaves to the editor, in a single note.
    private func makeNote(in context: ModelContext) throws -> Note {
        let note = Note(title: "Everything")
        context.insert(note)

        let payloads: [any BlockPayload] = [
            TextPayload(plain: "A paragraph."),
            HeadingPayload(level: .two, text: "A heading"),
            ChecklistPayload(items: [.init(label: "Done"), .init(label: "Not done")]),
            ListPayload(style: .bullet, items: [.init(text: "One")]),
            DividerPayload(),
            MetricPayload(label: "Weight", value: 82.5, unit: "kg"),
            TimerPayload(label: "Rest", duration: 90),
            RatingPayload(label: "Mood", scale: 5, value: 4),
            ProgressPayload(label: "Chapters", current: 3, target: 10),
        ]

        for payload in payloads {
            let block = try Block(payload)
            context.insert(block)
            note.append(block)
        }
        return note
    }

    @Test("A note with every block type exports to PDF without taking the app with it")
    func pdfExportSurvivesEveryBlockType() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try makeNote(in: context)

        let data = try #require(NoteExporter.pdf(for: note, theme: theme, stock: stock))
        #expect(!data.isEmpty)
        // Real PDFs start with %PDF-.
        #expect(data.starts(with: Array("%PDF-".utf8)))
    }

    @Test("An empty note still produces a page rather than nothing")
    func emptyNoteExports() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = Note(title: "")
        context.insert(note)

        #expect(NoteExporter.pdf(for: note, theme: theme, stock: stock) != nil)
    }

    @Test("A note exports to a PNG")
    func imageExport() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try makeNote(in: context)

        let data = try #require(NoteExporter.image(for: note, theme: theme, stock: stock))
        #expect(!data.isEmpty)
        // PNG's magic number.
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("Every format has a distinct extension and can name a file")
    func formatsAreDistinct() {
        let extensions = NoteExporter.Format.allCases.map(\.fileExtension)
        #expect(Set(extensions).count == extensions.count)
        #expect(extensions.allSatisfy { !$0.isEmpty })
    }
}
