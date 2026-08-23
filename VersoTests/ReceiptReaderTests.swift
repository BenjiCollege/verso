import Foundation
import Testing
@testable import VersoKit

/// Reading a receipt.
///
/// The stakes here are unusual for a notes app: a misread total does not look
/// wrong. It looks like a number, it goes into the expense series, and it adds
/// itself into a trip total that somebody then claims. So these lean hard on
/// the cases where the *plausible* answer is the wrong one — a subtotal, a
/// quantity, a card's last four digits — rather than on the happy path.
@Suite("Receipt reader")
struct ReceiptReaderTests {

    // MARK: - Totals

    @Test("The total is read, not the subtotal")
    func totalBeatsSubtotal() {
        let receipt = ReceiptReader.read([
            "THE DAILY GRIND",
            "Flat white          3.40",
            "Croissant           2.60",
            "Subtotal            6.00",
            "VAT                 1.20",
            "Total               7.20",
        ])

        #expect(receipt.total == 7.20)
    }

    /// A split bill prints a total *and* the amount that actually left the
    /// account. The second one is the one that matters.
    @Test("Amount due beats a plain total")
    func amountDueWins() {
        let receipt = ReceiptReader.read([
            "Total              48.00",
            "Cash                20.00",
            "Amount Due          28.00",
        ])

        #expect(receipt.total == 28.00)
    }

    @Test("A receipt with no total leaves it empty rather than guessing")
    func noTotalIsNil() {
        let receipt = ReceiptReader.read([
            "CORNER SHOP",
            "12 High Street",
            "Thank you for your custom",
        ])

        #expect(receipt.total == nil)
    }

    /// The failure that would be invisible: a quantity read as money. "2 x
    /// Coffee" must not become £2, which is why two decimal places are
    /// required.
    @Test("A bare number is not an amount")
    func quantitiesAreNotAmounts() {
        let receipt = ReceiptReader.read([
            "SHOP",
            "2 x Coffee",
            "Table 14",
        ])

        #expect(receipt.total == nil)
        #expect(receipt.items.isEmpty)
    }

    @Test("Thousands separators are read correctly", arguments: [
        ("Total  1,299.00", 1299.00),
        ("Total  1 299.00", 1299.00),
        ("Total    299.00", 299.00),
    ])
    func thousands(line: String, expected: Double) {
        #expect(ReceiptReader.read([line]).total == expected)
    }

    @Test("The currency is kept when the paper shows one")
    func currencyIsRead() {
        #expect(ReceiptReader.read(["Total  £12.50"]).currency == "£")
        #expect(ReceiptReader.read(["Total  $12.50"]).currency == "$")
        #expect(ReceiptReader.read(["Total  12.50"]).currency.isEmpty)
    }

    // MARK: - Items

    @Test("Line items pair a description with an amount")
    func itemsAreRead() {
        let receipt = ReceiptReader.read([
            "BOOKSHOP",
            "Pale Fire            9.99",
            "Postage              2.80",
            "Total               12.79",
        ])

        #expect(receipt.items.map(\.label) == ["Pale Fire", "Postage"])
        #expect(receipt.items.map(\.amount) == [9.99, 2.80])
    }

    /// The total's own line is not also an item, or every receipt would count
    /// its total twice.
    @Test("The total line is not also an item")
    func totalIsNotAnItem() {
        let receipt = ReceiptReader.read([
            "Coffee               3.40",
            "Total                3.40",
        ])

        #expect(receipt.items.count == 1)
        #expect(receipt.items.first?.label == "Coffee")
    }

    /// A receipt's header and footer are full of numbers that are not prices.
    @Test("Addresses and card lines are not items")
    func headersAreNotItems() {
        let receipt = ReceiptReader.read([
            "SANDWICH CO",
            "24 Bridge Street",
            "0161 496 0000",
            "Ham roll             4.25",
            "VISA ending 4242",
            "AUTH 004512",
        ])

        #expect(receipt.items.map(\.label) == ["Ham roll"])
    }

    // MARK: - Merchant

    @Test("The merchant is the first line that reads like a name")
    func merchantFromTop() {
        let receipt = ReceiptReader.read([
            "PRET A MANGER",
            "Total  6.45",
        ])

        #expect(receipt.merchant == "PRET A MANGER")
    }

    /// Plenty of receipts open with a store code or a phone number.
    @Test("A line of digits is not a merchant name")
    func digitsAreNotAName() {
        let receipt = ReceiptReader.read([
            "0800 123 4567",
            "STORE 00219",
            "GREEN GROCER",
            "Total  8.00",
        ])

        #expect(receipt.merchant == "GREEN GROCER")
    }

    // MARK: - Date

    /// A receipt photographed on Sunday is still Friday's lunch. Filing it
    /// under the day it was scanned is exactly the mistake this feature exists
    /// to stop somebody making by hand.
    @Test("The printed date wins over the scan date")
    func printedDateIsPreferred() throws {
        let receipt = ReceiptReader.read([
            "CAFE",
            "15/08/2026 13:04",
            "Total  9.00",
        ])

        let purchased = try #require(receipt.purchasedAt)
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: purchased)
        #expect(parts.year == 2026)
        #expect(parts.month == 8)
        #expect(parts.day == 15)
    }

    @Test("No readable date leaves it empty")
    func noDate() {
        #expect(ReceiptReader.read(["SHOP", "Total  4.00"]).purchasedAt == nil)
    }

    // MARK: - Nothing at all

    @Test("A blank scan reads as empty rather than as a receipt")
    func emptyScan() {
        #expect(ReceiptReader.read([]).isEmpty)
        #expect(ReceiptReader.read(["", "   "]).isEmpty)
    }
}

/// The note a receipt becomes.
///
/// The important property is not what the note looks like — it is that nothing
/// downstream can tell it apart from any other note. A receipt is a heading, a
/// table, a metric and a place, built by the same instantiator every bundled
/// template uses, with a generated id nobody can branch on.
@Suite("Receipt note")
struct ReceiptTemplateTests {

    private func sample() -> Receipt {
        Receipt(
            merchant: "The Daily Grind",
            purchasedAt: Date(timeIntervalSince1970: 1_760_000_000),
            total: 7.20,
            currency: "£",
            items: [
                .init(label: "Flat white", amount: 3.40),
                .init(label: "Croissant", amount: 2.60),
            ]
        )
    }

    @Test("A receipt becomes ordinary blocks")
    func blocksAreOrdinary() {
        let template = sample().makeTemplate(scannedAt: Date())
        let types = template.blocks.compactMap(\.blockType)

        #expect(types.contains(.table))
        #expect(types.contains(.metric))
        // Somewhere to say why it was bought — the one thing no scanner can
        // recover.
        #expect(types.contains(.text))
    }

    /// Rule 2: nothing may name a template id in Swift. A generated id is what
    /// guarantees nobody downstream can start special-casing receipts.
    @Test("The template id is generated, not a name anything can branch on")
    func idIsGenerated() {
        let a = sample().makeTemplate(scannedAt: Date()).id
        let b = sample().makeTemplate(scannedAt: Date()).id

        #expect(a != b)
        #expect(a.hasPrefix("receipt."))
    }

    @Test("The total joins the shared expense series")
    func totalJoinsTheSeries() throws {
        let template = sample().makeTemplate(scannedAt: Date())
        let metric = try #require(template.blocks.first { $0.blockType == .metric })

        #expect(metric.payload["seriesID"] == .string(Receipt.expenseSeriesID))
        #expect(metric.payload["value"] == .number(7.20))
        #expect(metric.payload["unit"] == .string("£"))
    }

    @Test("Every line item becomes a row")
    func itemsBecomeRows() throws {
        let template = sample().makeTemplate(scannedAt: Date())
        let table = try #require(template.blocks.first { $0.blockType == .table })

        guard case .array(let rows)? = table.payload["rows"] else {
            Issue.record("no rows"); return
        }
        #expect(rows.count == 2)
    }

    @Test("A place is included only when there is one")
    func placeIsOptional() {
        let without = sample().makeTemplate(scannedAt: Date())
        #expect(!without.blocks.contains { $0.blockType == .place })

        let with = sample().makeTemplate(
            scannedAt: Date(),
            place: ResolvedPlace(name: "Soho", coordinate: Coordinate(latitude: 51.5, longitude: -0.13))
        )
        #expect(with.blocks.contains { $0.blockType == .place })
    }

    @Test("A receipt with no merchant still gets a usable title")
    func titleFallsBack() {
        var receipt = sample()
        receipt.merchant = ""
        #expect(receipt.title().contains("Receipt"))
        #expect(!receipt.title().isEmpty)
    }

    @Test("An empty scan produces a note that is still valid")
    func emptyReceiptStillBuilds() throws {
        let template = Receipt().makeTemplate(scannedAt: Date())
        // No table, no metric — but a text block, so the note is never blank.
        #expect(!template.blocks.isEmpty)
        #expect(template.blocks.allSatisfy { $0.blockType != nil })
    }
}
