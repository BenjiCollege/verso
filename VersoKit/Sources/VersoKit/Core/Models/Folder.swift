import Foundation
import SwiftData

/// A folder, or — when `savedSearch` is non-nil — a smart folder.
@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "folder"
    var position: Int = 0
    var savedSearch: Data?           // non-nil = smart folder
    var notes: [Note]? = []

    init(
        id: UUID = UUID(),
        name: String = "",
        icon: String = "folder",
        position: Int = 0,
        savedSearch: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.position = position
        self.savedSearch = savedSearch
    }
}

extension Folder {
    var isSmartFolder: Bool { savedSearch != nil }
}
