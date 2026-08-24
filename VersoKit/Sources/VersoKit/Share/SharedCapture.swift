import Foundation
import OSLog
import SwiftData
import UniformTypeIdentifiers

/// What another app handed over, reduced to the three things Verso can write.
///
/// A value type rather than the `NSExtensionItem`s themselves, so everything
/// past the loader — the preview, the title suggestion, the note writer, the
/// tests — works on something inert and `Sendable`. The share sheet is the only
/// place in the app that receives content it did not create, and keeping the
/// system's objects at the doorstep is what stops that spreading.
struct SharedCapture: Sendable, Equatable {
    var text: String = ""
    var links: [URL] = []
    /// Encoded bytes, straight from the provider. Downscaling happens in
    /// `ImageStore` at save time — decoding a full-resolution photograph while
    /// the user is still looking at the sheet is exactly the spend a share
    /// extension's memory budget cannot take.
    var images: [Data] = []
    /// The page title Safari or Mail supplied, if any. Only a suggestion — the
    /// field is editable and the user's version wins.
    var providedTitle: String = ""
}

extension SharedCapture {

    var isEmpty: Bool {
        bodyText.isEmpty && images.isEmpty
    }

    /// The text the note is built from: what was shared, with any links on
    /// their own lines beneath it.
    ///
    /// One string rather than a structured hand-off because the note is built
    /// by `IntelligenceService.makeNote`, which takes free text and finds the
    /// shape in it — the same path Capture and the Shortcuts action use. A
    /// share that is a bulleted list from Notes therefore arrives as a
    /// checklist here too, for free.
    var bodyText: String {
        var lines: [String] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { lines.append(trimmed) }
        lines.append(contentsOf: links.map(\.absoluteString))
        return lines.joined(separator: "\n")
    }

    /// What the title field starts as.
    ///
    /// Safari's page title if there is one, then the first sentence of the
    /// shared text, then the link's host. Never empty when there is anything to
    /// go on: an untitled note in the library is a note nobody finds again.
    var suggestedTitle: String {
        let provided = providedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !provided.isEmpty { return HeuristicIntelligence.truncate(provided, toWords: 8) }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let sentence = HeuristicIntelligence.truncate(
                HeuristicIntelligence.firstSentence(of: trimmed),
                toWords: 8
            )
            if !sentence.isEmpty { return sentence }
        }

        if let host = links.first?.host() {
            // Bare host, not the whole URL: a title is read at a glance in a
            // list, and a query string is unreadable at that size.
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }

        return ""
    }
}

// MARK: - Loading

/// Pulls a `SharedCapture` out of what the system delivered.
///
/// Everything here is `@MainActor` deliberately. `NSItemProvider` is not
/// `Sendable`, and the callback form of `loadItem` is the one API that lets the
/// non-`Sendable` value be turned into a `String`, a `URL` or `Data` inside the
/// completion block — so nothing that cannot cross an isolation boundary ever
/// has to.
@MainActor
enum SharedCaptureLoader {

    /// Attachments beyond this are dropped. A share sheet with fifty photos in
    /// it is a mis-tap, and a share extension that tries to encode all fifty is
    /// a share extension the system kills mid-save.
    static let attachmentLimit = 10

    static func load(from items: [NSExtensionItem]) async -> SharedCapture {
        var capture = SharedCapture()

        for item in items {
            if capture.providedTitle.isEmpty {
                capture.providedTitle = (item.attributedTitle?.string ?? "")
            }

            for provider in item.attachments ?? [] {
                guard capture.links.count + capture.images.count < attachmentLimit else { break }
                await absorb(provider, into: &capture)
            }

            // Mail and Messages put the message body here rather than in an
            // attachment, so a share with no plain-text provider still has text.
            //
            // Safari fills the same field with the URL it already handed over
            // as an attachment, which is why the link is checked for: without
            // it a shared page arrives in the note twice.
            if capture.text.isEmpty,
               let content = item.attributedContentText?.string,
               !capture.links.map(\.absoluteString).contains(content.trimmingCharacters(in: .whitespacesAndNewlines)) {
                capture.text = content
            }
        }

        return capture
    }

    private static func absorb(_ provider: NSItemProvider, into capture: inout SharedCapture) async {
        // Order matters: Safari registers a page as *both* a URL and plain
        // text, and the URL is the useful half. Images are asked for last
        // because a provider that can produce one can often also produce a
        // file URL to it, and a link to a file the extension cannot reach
        // afterwards is worse than no link.
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(from: provider), !url.isFileURL {
                if !capture.links.contains(url) { capture.links.append(url) }
                return
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let data = await loadImageData(from: provider), !data.isEmpty {
                capture.images.append(data)
                return
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = await loadText(from: provider), !text.isEmpty {
                capture.text = capture.text.isEmpty ? text : capture.text + "\n" + text
            }
        }
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, _ in
                // Resolved to a `URL` inside the block: what the block is
                // handed is an `NSSecureCoding` existential, which cannot leave
                // this closure under strict concurrency.
                continuation.resume(returning: value as? URL)
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { value, _ in
                continuation.resume(returning: (value as? String) ?? (value as? NSString) as String?)
            }
        }
    }

    private static func loadImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            // The data representation rather than the item: an image arrives as
            // a `UIImage`, a file URL or raw bytes depending on which app sent
            // it, and this is the one call that answers with bytes in all three
            // cases.
            _ = provider.loadDataRepresentation(for: .image) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

// MARK: - Writing

/// Turns a `SharedCapture` into a note in the shared store.
@MainActor
enum SharedCaptureWriter {

    static let logger = Logger(subsystem: "com.verso.notes", category: "share")

    /// The width an imported picture reserves height against.
    ///
    /// The editor measures its own page and cannot be asked from here, so this
    /// is the same value `ImageBlockView` starts at — a compact-width page.
    /// Getting it wrong costs a slightly wrong reserved height until the block
    /// is next edited, not a wrong picture.
    static let assumedPageWidth: CGFloat = 320

    @discardableResult
    static func write(
        _ capture: SharedCapture,
        title: String,
        in context: ModelContext,
        intelligence: IntelligenceService
    ) async throws -> Note {
        let body = capture.bodyText

        // A share with nothing but pictures in it still gets a page to sit on,
        // and it comes from the blank template so the theme, stock and first
        // block are whatever the app would have given it.
        let note = body.isEmpty
            ? try TemplateInstantiator.makeNote(from: TemplateCatalog.shared.blank, in: context)
            : try await intelligence.makeNote(from: body, in: context)

        let chosen = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chosen.isEmpty { note.title = chosen }

        for data in capture.images {
            let payload = try ImageStore.importImage(
                data: data,
                atPageWidth: assumedPageWidth,
                into: note,
                context: context
            )
            let block = try Block(payload)
            context.insert(block)
            note.append(block)
        }

        note.touch()
        try context.save()
        return note
    }
}
