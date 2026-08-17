import Foundation
import OSLog
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// Preparing pictures for a note, and finding them again.
///
/// The bytes live in an `ImageAsset` on the note, `.externalStorage`, so
/// CloudKit ships them as assets and a photo taken on the phone is on the iPad.
/// Files on disk — where this started, and where PDF attachments still live —
/// never reach a second device, and pictures are the attachment people most
/// expect to.
///
/// Lookup goes through the note rather than a fetch: a block already knows its
/// note, and `note.images` is a relationship the context has usually faulted in
/// already. It also means a picture cannot be read from a note it does not
/// belong to, which a fetch by id would allow.
enum ImageStore {

    static let logger = Logger(subsystem: "com.verso.notes", category: "images")

    static let acceptedTypes: [UTType] = [.image]

    /// The longest edge kept, in pixels.
    ///
    /// A phone camera writes about 4000px. At the size a page shows one,
    /// everything past this is bytes nobody sees — and now that they sync, it
    /// is also somebody's iCloud storage.
    static let maximumPixelSize: CGFloat = 2_048

    /// JPEG, not PNG. A photograph is continuous tone, which is what JPEG is
    /// for; PNG would store the same picture several times over.
    static let compressionQuality: CGFloat = 0.82

    enum ImageError: LocalizedError {
        case unreadable

        var errorDescription: String? {
            String(localized: "That image couldn't be read.")
        }
    }

    // MARK: - Importing

    /// Encodes a picked image, attaches it to the note, and returns a payload
    /// pointing at it.
    ///
    /// - Parameter width: the page width it will be shown at, used to work out
    ///   the height to reserve.
    @MainActor
    static func importImage(
        data: Data,
        atPageWidth width: CGFloat,
        into note: Note,
        context: ModelContext
    ) throws -> ImagePayload {
        guard let image = UIImage(data: data) else { throw ImageError.unreadable }

        let scaled = downscaled(image)
        guard let encoded = scaled.jpegData(compressionQuality: compressionQuality) else {
            throw ImageError.unreadable
        }

        let asset = ImageAsset(data: encoded)
        context.insert(asset)
        asset.note = note
        note.images = (note.images ?? []) + [asset]

        // Guarded because a zero or non-finite ratio reaches a `frame` as NaN,
        // and a NaN height takes the layout with it.
        let ratio = scaled.size.width > 0 ? scaled.size.height / scaled.size.width : 1
        let height = ratio.isFinite ? Double(width * ratio) : 240

        return ImagePayload(assetID: asset.id, displayHeight: height)
    }

    // MARK: - Reading

    static func asset(_ assetID: UUID?, in note: Note?) -> ImageAsset? {
        guard let assetID, let note else { return nil }
        return (note.images ?? []).first { $0.id == assetID }
    }

    static func load(_ assetID: UUID?, in note: Note?) -> UIImage? {
        guard let asset = asset(assetID, in: note), !asset.data.isEmpty else { return nil }
        return UIImage(data: asset.data)
    }

    // MARK: - Removing

    /// Deletes the asset a payload points at, if the note still has it.
    ///
    /// Called when a picture is replaced or cleared. A block being deleted takes
    /// nothing with it — the note's cascade handles the note, and an asset
    /// orphaned by a block that was undone has to still be there to come back.
    @MainActor
    static func delete(_ assetID: UUID?, in note: Note?, context: ModelContext) {
        guard let asset = asset(assetID, in: note), let note else { return }
        note.images = (note.images ?? []).filter { $0.id != asset.id }
        context.delete(asset)
    }

    // MARK: - Private

    private static func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maximumPixelSize, longest > 0 else { return image }

        let scale = maximumPixelSize / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        // 1, not the screen's scale: the size above is already in pixels, and
        // letting it multiply by 3 puts back the megapixels this is here to
        // remove.
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
