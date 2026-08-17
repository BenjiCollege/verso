import Foundation
import SwiftData

/// A picture in a note.
///
/// **The second addition to the model in section 4**, after `AudioAsset`, and
/// added for the same reason: a photo that only exists on the device it was
/// taken on is a photo people report as missing. Files on disk — which is where
/// PDF attachments live, and where this started — never reach a second device,
/// and pictures are the attachment people most expect to.
///
/// `.externalStorage`, so CloudKit ships the bytes as an asset rather than a
/// record field. `ImageStore` already downscales to 2048px and encodes JPEG
/// before anything gets here, so what syncs is a page-sized picture and not a
/// camera's original.
///
/// Reverting is this file, one line in `VersoModelContainer.schema`, one
/// relationship on `Note`, and `ImageStore` going back to writing files.
@Model
final class ImageAsset {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    /// JPEG. Empty only in the moment between insertion and the first write.
    @Attribute(.externalStorage) var data: Data = Data()

    var note: Note?

    init(id: UUID = UUID(), createdAt: Date = Date(), data: Data = Data()) {
        self.id = id
        self.createdAt = createdAt
        self.data = data
    }
}
