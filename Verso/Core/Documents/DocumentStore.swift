import Foundation
import OSLog
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// Where imported documents live, and how they are read.
enum DocumentStore {

    static let logger = Logger(subsystem: "com.verso.notes", category: "documents")

    static let acceptedTypes: [UTType] = [.pdf]

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base.appending(path: "Documents", directoryHint: .isDirectory)
    }

    static func url(for assetID: UUID) -> URL {
        directory.appending(path: assetID.uuidString).appendingPathExtension("pdf")
    }

    static func exists(_ assetID: UUID?) -> Bool {
        guard let assetID else { return false }
        return FileManager.default.fileExists(atPath: url(for: assetID).path())
    }

    // MARK: - Importing

    /// Copies a picked document into the container and reads what the block
    /// needs to display it.
    ///
    /// The file is copied rather than referenced in place: a document picked
    /// from another app's container can be moved or deleted, and a note
    /// pointing at a file that has wandered off is worse than a slightly larger
    /// app container.
    static func importDocument(from source: URL) throws -> AttachmentPayload {
        let needsScope = source.startAccessingSecurityScopedResource()
        defer { if needsScope { source.stopAccessingSecurityScopedResource() } }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let assetID = UUID()
        let destination = url(for: assetID)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)

        guard let document = PDFDocument(url: destination) else {
            try? FileManager.default.removeItem(at: destination)
            throw DocumentError.unreadable
        }

        let byteCount = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        return AttachmentPayload(
            assetID: assetID,
            fileName: source.lastPathComponent,
            pageCount: document.pageCount,
            byteCount: byteCount,
            thumbnail: thumbnailData(for: document.page(at: 0))
        )
    }

    static func document(for payload: AttachmentPayload) -> PDFDocument? {
        guard let assetID = payload.assetID else { return nil }
        return PDFDocument(url: url(for: assetID))
    }

    static func delete(_ payload: AttachmentPayload) {
        guard let assetID = payload.assetID else { return }
        try? FileManager.default.removeItem(at: url(for: assetID))
    }

    // MARK: - Rendering

    /// A page as an image, at a size that fits the given width.
    ///
    /// Rendered rather than shown through `PDFView` because the annotation
    /// layers sit on top as ordinary views — reaching into `PDFView`'s own
    /// scroll hierarchy to overlay a canvas is a much more fragile way to get
    /// the same result.
    static func image(of page: PDFPage, fittingWidth width: CGFloat, scale: CGFloat = 2) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, width > 0 else { return nil }

        let size = CGSize(width: width, height: width * bounds.height / bounds.width)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: size.width / bounds.width, y: -size.height / bounds.height)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    /// A small JPEG of the first page, kept inside the block payload so an
    /// attachment still looks like itself on a device without the file.
    static func thumbnailData(for page: PDFPage?, width: CGFloat = 180) -> Data {
        guard let page, let image = image(of: page, fittingWidth: width, scale: 1) else { return Data() }
        let data = image.jpegData(compressionQuality: 0.6) ?? Data()
        // A thumbnail that outgrows its budget is dropped rather than bloating
        // every read of the note it lives in.
        return data.count <= AttachmentPayload.maximumThumbnailBytes ? data : Data()
    }

    /// Page bounds, for turning normalised annotations back into points.
    static func pageSize(of page: PDFPage) -> CGSize {
        page.bounds(for: .mediaBox).size
    }
}

enum DocumentError: LocalizedError, Equatable {
    case unreadable
    case missingFile
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .unreadable:
            String(localized: "That file couldn't be opened as a PDF.")
        case .missingFile:
            String(localized: "This document isn't on this device.")
        case .exportFailed:
            String(localized: "The document couldn't be exported.")
        }
    }
}
