import Foundation

/// What was on the paper.
///
/// Deliberately a plain value with no opinion about blocks, notes or storage —
/// it is the *reading* of a receipt, and `makeTemplate()` below is the only
/// place it meets the note engine.
struct Receipt: Equatable, Sendable {

    struct LineItem: Equatable, Sendable {
        var label: String
        var amount: Double?
    }

    /// Whoever printed it. Empty when nothing on the paper looked like a name.
    var merchant: String = ""
    /// What the receipt says it was, which is not necessarily when it was
    /// scanned — a receipt photographed on Monday may be from Friday.
    var purchasedAt: Date?
    var total: Double?
    /// ISO code where one could be told, otherwise the symbol, otherwise empty.
    var currency: String = ""
    var items: [LineItem] = []

    var isEmpty: Bool {
        merchant.isEmpty && total == nil && items.isEmpty
    }
}

/// Turning the lines off a receipt into something with fields.
///
/// Heuristics, not a model. This runs on every device including the ones with
/// no Apple Intelligence, which section 1 requires — and a receipt is a
/// famously *regular* document: a name at the top, amounts on the right, and
/// the largest number near the word "total". That regularity is what makes
/// rules a reasonable tool here where they would not be for prose.
///
/// Everything it cannot establish is left `nil` rather than guessed. A receipt
/// with the wrong total silently attached is worse than one the user completes
/// by hand, because nobody re-reads a number the computer filled in.
enum ReceiptReader {

    /// Words that mark the line carrying the amount actually charged.
    ///
    /// Ordered by how final they are: a receipt often shows a subtotal, then
    /// tax, then the total, and the last of those is the one that left the
    /// account. `amountDue` and `balance` beat `total` because a split bill
    /// prints both.
    private static let totalMarkers = [
        "amount due", "balance due", "total due", "grand total", "card total",
        "total", "amount", "balance",
    ]

    /// Words that look like a total and are not.
    private static let notTotalMarkers = ["subtotal", "sub total", "total items", "total qty"]

    static func read(_ lines: [String]) -> Receipt {
        var receipt = Receipt()

        receipt.merchant = merchant(in: lines)
        receipt.purchasedAt = date(in: lines)

        let totalReading = total(in: lines)
        receipt.total = totalReading?.amount
        receipt.currency = totalReading?.currency ?? currency(in: lines)

        receipt.items = items(in: lines, excluding: totalReading?.line)
        return receipt
    }

    // MARK: - Merchant

    /// The first line that reads like a name.
    ///
    /// Receipts put the shop at the top in the largest type, so position is the
    /// strongest signal available without layout information. Lines that are
    /// mostly digits are skipped — a phone number, a store code or a date is
    /// the usual first line on a receipt that has no name at all.
    private static func merchant(in lines: [String]) -> String {
        for line in lines.prefix(5) {
            let letters = line.count { $0.isLetter }
            let digits = line.count { $0.isNumber }
            guard letters >= 3, letters > digits else { continue }
            guard !containsMarker(line, in: totalMarkers) else { continue }
            return line
        }
        return ""
    }

    // MARK: - Total

    private struct TotalReading {
        var amount: Double
        var currency: String?
        /// Index of the line it came from, so it is not also read as an item.
        var line: Int
    }

    private static func total(in lines: [String]) -> TotalReading? {
        var best: (rank: Int, index: Int, amount: Double, currency: String?)?

        for (index, line) in lines.enumerated() {
            guard !containsMarker(line, in: notTotalMarkers) else { continue }
            guard let rank = markerRank(line) else { continue }
            guard let money = lastAmount(in: line) else { continue }

            // Lower rank is a more final word. On a tie the later line wins:
            // receipts print the sequence downwards, so the last "total" is the
            // one at the bottom of the paper.
            if let current = best, rank > current.rank { continue }
            best = (rank, index, money.amount, money.currency)
        }

        guard let best else { return nil }
        return TotalReading(amount: best.amount, currency: best.currency, line: best.index)
    }

    private static func markerRank(_ line: String) -> Int? {
        let lowered = line.lowercased()
        for (rank, marker) in totalMarkers.enumerated() where lowered.contains(marker) {
            return rank
        }
        return nil
    }

    private static func containsMarker(_ line: String, in markers: [String]) -> Bool {
        let lowered = line.lowercased()
        return markers.contains { lowered.contains($0) }
    }

    // MARK: - Items

    /// Lines that pair a description with an amount.
    ///
    /// A receipt's body is exactly that shape, and its header and footer are
    /// not: an address has no trailing number, a card authorisation has no
    /// description worth keeping. Requiring both halves is what separates them
    /// without needing to know which shop printed it.
    private static func items(in lines: [String], excluding totalLine: Int?) -> [Receipt.LineItem] {
        var items: [Receipt.LineItem] = []

        for (index, line) in lines.enumerated() {
            if let totalLine, index == totalLine { continue }
            guard !containsMarker(line, in: totalMarkers + notTotalMarkers) else { continue }
            guard let money = lastAmount(in: line) else { continue }

            // Whatever precedes the amount is the description.
            guard let range = line.range(of: money.text, options: .backwards) else { continue }
            let label = line[line.startIndex..<range.lowerBound]
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t.·-–—:"))

            guard label.count >= 2, label.contains(where: \.isLetter) else { continue }
            items.append(Receipt.LineItem(label: label, amount: money.amount))
        }
        return items
    }

    // MARK: - Money

    private struct Money {
        var amount: Double
        /// Exactly as it appeared, so it can be cut back out of the line.
        var text: String
        var currency: String?
    }

    /// The rightmost money-shaped run on a line.
    ///
    /// Rightmost because that is the column receipts put amounts in; a quantity
    /// or a product code sits to the left of it. Two decimal places are
    /// required, which is what keeps "2 x Coffee" from reading as £2.
    private static func lastAmount(in line: String) -> Money? {
        let pattern = /([£$€¥]|USD|GBP|EUR)?\s?(\d{1,3}(?:[,\s]\d{3})*|\d+)[.,](\d{2})\b/
        guard let match = line.matches(of: pattern).last else { return nil }

        let whole = String(match.2).replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        let fraction = String(match.3)
        guard let amount = Double("\(whole).\(fraction)") else { return nil }

        return Money(
            amount: amount,
            text: String(match.0).trimmingCharacters(in: .whitespaces),
            currency: match.1.map(String.init)
        )
    }

    private static func currency(in lines: [String]) -> String {
        for line in lines {
            if let money = lastAmount(in: line), let currency = money.currency { return currency }
        }
        return ""
    }

    // MARK: - Date

    /// The first date on the paper.
    ///
    /// Receipts print the transaction date near the top and rarely print any
    /// other, so first-found is right far more often than it is wrong. A
    /// receipt with no readable date keeps `nil` and the note falls back to
    /// when it was scanned, which is at least a true statement about something.
    private static func date(in lines: [String]) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        guard let detector else { return nil }

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = detector.firstMatch(in: line, range: range), let date = match.date {
                return date
            }
        }
        return nil
    }
}
