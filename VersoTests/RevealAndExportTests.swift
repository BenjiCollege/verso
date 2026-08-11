import Foundation
import SwiftData
import Testing
@testable import VersoKit

@Suite("Reveal engine")
struct RevealEngineTests {

    @Test("Each style reveals at the granularity it needs")
    func granularities() {
        #expect(RevealPlan.plan(for: .typewriter).granularity == .glyph)
        #expect(RevealPlan.plan(for: .fadeUp).granularity == .word)
        #expect(RevealPlan.plan(for: .blurIn).granularity == .word)
        #expect(RevealPlan.plan(for: .floatIn).granularity == .block)
        #expect(RevealPlan.plan(for: .unfurl).granularity == .block)
        #expect(RevealPlan.plan(for: .none).granularity == .block)
    }

    @Test("Units are staggered, and the first has no delay")
    func stagger() {
        let plan = RevealPlan.plan(for: .fadeUp)
        #expect(plan.delay(forUnit: 0) == 0)
        #expect(plan.delay(forUnit: 1) == Motion.wordGap)
        #expect(plan.delay(forUnit: 10) == Motion.wordGap * 10)
    }

    @Test("A unit is absent before its turn, arriving during, and settled after")
    func progressOverTime() {
        let plan = RevealPlan.plan(for: .fadeUp)
        let start = plan.delay(forUnit: 3)

        #expect(plan.progress(forUnit: 3, elapsed: start - 0.01) == 0)
        #expect(plan.progress(forUnit: 3, elapsed: start + plan.unitDuration / 2) > 0)
        #expect(plan.progress(forUnit: 3, elapsed: start + plan.unitDuration / 2) < 1)
        #expect(plan.progress(forUnit: 3, elapsed: start + plan.unitDuration) == 1)
        #expect(plan.progress(forUnit: 3, elapsed: 100) == 1)
    }

    /// A typewriter has no dissolve — glyphs appear.
    @Test("The typewriter snaps rather than fading")
    func typewriterSnaps() {
        let plan = RevealPlan.plan(for: .typewriter)
        #expect(plan.progress(forUnit: 0, elapsed: 0) == 0)
        #expect(plan.progress(forUnit: 0, elapsed: 0.0005) == 1)

        #expect(RevealAppearance.at(progress: 0, style: .typewriter).opacity == 0)
        #expect(RevealAppearance.at(progress: 0.5, style: .typewriter).opacity == 1)
    }

    @Test("Nothing is hidden when the style is none")
    func noneIsImmediate() {
        let plan = RevealPlan.plan(for: .none)
        #expect(plan.progress(forUnit: 99, elapsed: 0) == 1)
        #expect(plan.totalDuration(unitCount: 500) == 0)
        #expect(plan.isFinished(unitCount: 500, elapsed: 0))
        #expect(RevealAppearance.at(progress: 0, style: .none) == .visible)
    }

    /// The reveal must never leave the page half-arrived.
    @Test("Every style ends fully visible", arguments: RevealStyle.allCases)
    func everyStyleSettles(style: RevealStyle) {
        let appearance = RevealAppearance.at(progress: 1, style: style)
        #expect(appearance == .visible, "\(style) does not settle")
    }

    @Test("Every style starts hidden except none", arguments: RevealStyle.allCases.filter { $0 != .none })
    func everyStyleStartsHidden(style: RevealStyle) {
        #expect(RevealAppearance.at(progress: 0, style: style).opacity == 0)
    }

    @Test("Styles differ in how they arrive, not only in when")
    func stylesAreDistinct() {
        let half = 0.5
        #expect(RevealAppearance.at(progress: half, style: .fadeUp).offsetY > 0)
        #expect(RevealAppearance.at(progress: half, style: .floatIn).offsetY
                > RevealAppearance.at(progress: half, style: .fadeUp).offsetY)
        #expect(RevealAppearance.at(progress: half, style: .blurIn).blurRadius > 0)
        #expect(RevealAppearance.at(progress: half, style: .unfurl).scaleY < 1)
    }

    @Test("The whole reveal takes the last unit's delay plus its own arrival")
    func totalDuration() {
        let plan = RevealPlan.plan(for: .fadeUp)
        #expect(plan.totalDuration(unitCount: 0) == 0)
        #expect(plan.totalDuration(unitCount: 1) == plan.unitDuration)
        #expect(plan.totalDuration(unitCount: 5) == plan.delay(forUnit: 4) + plan.unitDuration)
        #expect(plan.isFinished(unitCount: 5, elapsed: plan.totalDuration(unitCount: 5)))
    }

    /// Section 6: a per-glyph reveal is precisely what Reduce Motion exists to
    /// suppress.
    @Test("Reduce Motion flattens every style", arguments: RevealStyle.allCases)
    func reduceMotionFlattens(style: RevealStyle) {
        let reduced = MotionResolver(reduceMotion: true).revealPlan(for: style)
        #expect(reduced.style == .none)
        #expect(reduced.totalDuration(unitCount: 200) == 0)

        let normal = MotionResolver(reduceMotion: false).revealPlan(for: style)
        #expect(normal.style == style)
    }

    // MARK: - Units

    @Test("Text splits into the units a plan reveals")
    func unitSplitting() {
        let text = "One two three"
        #expect(RevealUnits.count(in: text, granularity: .block) == 1)
        #expect(RevealUnits.count(in: text, granularity: .word) == 3)
        #expect(RevealUnits.count(in: text, granularity: .glyph) == 13)
    }

    /// Every character has to belong to some unit, or a paragraph reveals with
    /// permanent gaps in it.
    @Test("Word units tile the whole string with no gaps")
    func wordUnitsTile() {
        for text in ["One two three", "  leading", "trailing  ", "punctuation, and — dashes!", "one"] {
            let ranges = RevealUnits.ranges(in: text, granularity: .word)
            let ns = text as NSString

            #expect(ranges.first?.location == 0, "\(text)")
            #expect(ranges.last.map { $0.upperBound } == ns.length, "\(text)")
            for (a, b) in zip(ranges, ranges.dropFirst()) {
                #expect(a.upperBound == b.location, "gap in \(text)")
            }
        }
    }

    /// Counting `Character`s would drift the moment a note contains an emoji,
    /// and these ranges are handed straight to TextKit.
    @Test("Glyph units are composed sequences, in UTF-16")
    func glyphUnitsAreComposed() {
        let text = "a🇬🇧b"
        let ranges = RevealUnits.ranges(in: text, granularity: .glyph)

        #expect(ranges.count == 3, "the flag is one glyph, not four")
        #expect(ranges[1].length == 4, "and four UTF-16 units wide")
        #expect(ranges.last?.upperBound == (text as NSString).length)
    }

    @Test("Empty text has no units")
    func emptyTextHasNoUnits() {
        #expect(RevealUnits.ranges(in: "", granularity: .word).isEmpty)
        #expect(RevealUnits.ranges(in: "", granularity: .glyph).isEmpty)
    }
}

@Suite("Markdown export")
struct MarkdownExportTests {

    private func note(in context: ModelContext, title: String = "Weekly Shop") throws -> Note {
        let note = Note(title: title)
        context.insert(note)
        return note
    }

    private func attach<P: BlockPayload>(_ payload: P, to note: Note, in context: ModelContext) throws {
        let block = try Block(payload)
        context.insert(block)
        note.append(block)
    }

    @Test("A note exports with its title as a heading")
    func titleBecomesHeading() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try note(in: context)
        try attach(TextPayload(plain: "Some prose."), to: note, in: context)

        let markdown = NoteExporter.markdown(for: note)
        #expect(markdown.hasPrefix("# Weekly Shop"))
        #expect(markdown.contains("Some prose."))
    }

    @Test("Headings export at their level")
    func headings() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try note(in: context, title: "")
        try attach(HeadingPayload(level: .one, text: "One"), to: note, in: context)
        try attach(HeadingPayload(level: .three, text: "Three"), to: note, in: context)

        let markdown = NoteExporter.markdown(for: note)
        #expect(markdown.contains("# One"))
        #expect(markdown.contains("### Three"))
    }

    @Test("Checklists export as task lists, with their groups as headings")
    func checklists() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try note(in: context, title: "")
        try attach(
            ChecklistPayload(
                groupBy: .group,
                groups: [.init(id: "produce", label: "Produce", position: 0)],
                itemFields: [.quantity, .unit],
                items: [
                    .init(label: "Lemons", checked: true, quantity: 6, unit: "ea", group: "produce"),
                    .init(label: "Bread", group: "produce"),
                ]
            ),
            to: note,
            in: context
        )

        let markdown = NoteExporter.markdown(for: note)
        #expect(markdown.contains("**Produce**"))
        #expect(markdown.contains("- [x] Lemons"))
        #expect(markdown.contains("- [ ] Bread"))
        #expect(markdown.contains("6 ea"))
    }

    @Test("Lists export bulleted or numbered")
    func lists() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try note(in: context, title: "")
        try attach(ListPayload(style: .numbered, items: [.init(text: "First"), .init(text: "Second")]), to: note, in: context)

        let markdown = NoteExporter.markdown(for: note)
        #expect(markdown.contains("1. First"))
        #expect(markdown.contains("2. Second"))
    }

    @Test("Tables export as pipe tables, with pipes in cells escaped")
    func tables() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try note(in: context, title: "")
        try attach(
            TablePayload(
                caption: "Sets",
                columns: [.init(title: "Weight", kind: .number), .init(title: "Note", kind: .text)],
                rows: [.init(cells: [.init(number: 100), .init(text: "felt | heavy")])]
            ),
            to: note,
            in: context
        )

        let markdown = NoteExporter.markdown(for: note)
        #expect(markdown.contains("| Weight | Note |"))
        #expect(markdown.contains("| --- | --- |"))
        #expect(markdown.contains("felt \\| heavy"), "an unescaped pipe would break the table")
    }

    /// A Markdown file is never recomputed, so exporting a stale number would
    /// be worse than exporting the formula.
    @Test("Formulas export as their expression, not a frozen result")
    func formulas() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try note(in: context, title: "")
        try attach(FormulaPayload(label: "Total", expression: "sum(subtotal)"), to: note, in: context)

        #expect(NoteExporter.markdown(for: note).contains("`sum(subtotal)`"))
    }

    @Test("An unrecorded metric says so rather than exporting zero")
    func emptyMetric() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try note(in: context, title: "")
        try attach(MetricPayload(label: "Bodyweight", unit: "kg"), to: note, in: context)

        let markdown = NoteExporter.markdown(for: note)
        #expect(markdown.contains("Bodyweight"))
        #expect(!markdown.contains("0 kg"))
    }

    /// One unreadable block must not cost the user the export.
    @Test("A block this build cannot read is skipped, not fatal")
    func unknownBlocksAreSkipped() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try note(in: context)
        try attach(TextPayload(plain: "Kept"), to: note, in: context)

        let alien = Block(typeRaw: "hologram", payload: Data())
        context.insert(alien)
        note.append(alien)

        let markdown = NoteExporter.markdown(for: note)
        #expect(markdown.contains("Kept"))
        #expect(!markdown.contains("hologram"))
    }

    @Test("An empty note still exports something valid")
    func emptyNote() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try note(in: context, title: "")
        #expect(!NoteExporter.markdown(for: note).isEmpty)
    }

    @Test("Every implemented block type produces Markdown without throwing")
    func everyBlockTypeExports() throws {
        for type in BlockRegistry.shared.implementedTypes {
            let data = try BlockRegistry.shared.makeDefaultData(for: type)
            #expect(throws: Never.self, "\(type.rawValue)") {
                _ = try BlockRegistry.shared.markdown(data, as: type)
            }
        }
    }

    // MARK: - Filenames

    @Test("Filenames are derived from the title and are safe to write")
    func fileNames() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())

        let normal = try note(in: context, title: "Shopping List")
        #expect(NoteExporter.fileName(for: normal, format: .markdown) == "Shopping List.md")

        let hostile = try note(in: context, title: "../../etc/passwd")
        let name = NoteExporter.fileName(for: hostile, format: .pdf)
        #expect(!name.contains("/"))
        #expect(name.hasSuffix(".pdf"))

        let untitled = try note(in: context, title: "")
        #expect(!NoteExporter.fileName(for: untitled, format: .shareCard).isEmpty)
        #expect(NoteExporter.fileName(for: untitled, format: .shareCard).hasSuffix(".gif"))
    }
}
