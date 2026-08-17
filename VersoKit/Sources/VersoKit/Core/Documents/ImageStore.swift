import Foundation
import OSLog
import UIKit
import UniformTypeIdentifiers

/// Where pictures in notes live.
///
/// Files on disk keyed by `assetID`, the same arrangement as imported
/// documents. That has one consequence worth stating plainly rather than
/// discovering: **pictures do not sync.** A photo added on the phone stays on
/// the phone.
///
/// Making them sync means a `@Model` with `@Attribute(.externalStorage)`, the
/// way `AudioAsset` carries a recording — which is a schema change, and schema
/// changes are the owner's to approve. The payload holds nothing but the id, so
/// that upgrade is a change of store and not a change of note.
enum ImageStore {

    static let logger = Logger(subsystem: "com.verso.notes", category: "images")

    static let acceptedTypes: [UTType] = [.image]

    /// The longest edge kept, in pixels.
    ///
    /// A modern phone camera writes about 4000px. At the size a page displays
    /// one, everything past this is bytes nobody sees — and on a note with a
    /// dozen pictures it is the difference between a document and a problem.
    static let maximumPixelSize: CGFloat = 2_048

    /// JPEG, not PNG. A photograph is continuous tone, which is what JPEG is
    /// for; PNG would store the same picture several times over.
    static let compressionQuality: CGFloat = 0.82

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base.appending(path: "Images", directoryHint: .isDirectory)
    }

    static func url(for assetID: UUID) -> URL {
        directory.appending(path: assetID.uuidString).appendingPathExtension("jpg")
    }

    static func exists(_ assetID: UUID?) -> Bool {
        guard let assetID else { return false }
        return FileManager.default.fileExists(atPath: url(for: assetID).path())
    }

    // MARK: - Importing

    enum ImageError: LocalizedError {
        case unreadable

        var errorDescription: String? {
            String(localized: "That image couldn't be read.")
        }
    }

    /// Takes the bytes of a picked image and returns a payload pointing at it.
    ///
    /// - Parameter width: the page width the picture will be shown at, used to
    ///   work out the height to reserve.
    static func importImage(data: Data, atPageWidth width: CGFloat) throws -> ImagePayload {
        guard let image = UIImage(data: data) else { throw ImageError.unreadable }

        let scaled = downscaled(image)
        guard let encoded = scaled.jpegData(compressionQuality: compressionQuality) else {
            throw ImageError.unreadable
        }

        let assetID = UUID()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoded.write(to: url(for: assetID), options: .atomic)

        // Guarded because a zero or non-finite ratio would reach a `frame` as
        // NaN, and a NaN height takes the layout with it.
        let ratio = scaled.size.width > 0 ? scaled.size.height / scaled.size.width : 1
        let height = ratio.isFinite ? Double(width * ratio) : 240

        return ImagePayload(assetID: assetID, displayHeight: height)
    }

    static func load(_ assetID: UUID?) -> UIImage? {
        guard let assetID, exists(assetID) else { return nil }
        return UIImage(contentsOfFile: url(for: assetID).path())
    }

    static func delete(_ assetID: UUID?) {
        guard let assetID else { return }
        try? FileManager.default.removeItem(at: url(for: assetID))
    }

    // MARK: - Private

    private static func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maximumPixelSize, longest > 0 else { return image }

        let scale = maximumPixelSize / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let format = UIGraphicsImageRendererFormat.default()
            // 1, not the screen's scale: the size above is already in pixels,
            // and letting it multiply by 3 puts back the megapixels this is
            // here to remove.
            format.scale = 1
            format.opaque = true
            return format
        }())

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
