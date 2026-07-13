import Foundation
import SwiftData

@Model
final class Song {
    var id: UUID

    @Attribute(.unique)
    var contentHash: String

    var storageFileName: String
    var title: String
    var artist: String
    var durationSeconds: Double
    var artworkData: Data?
    var importedAt: Date

    init(
        contentHash: String,
        storageFileName: String,
        title: String,
        artist: String,
        durationSeconds: Double,
        artworkData: Data?,
        importedAt: Date
    ) {
        self.id = UUID()
        self.contentHash = contentHash
        self.storageFileName = storageFileName
        self.title = title
        self.artist = artist
        self.durationSeconds = durationSeconds
        self.artworkData = artworkData
        self.importedAt = importedAt
    }
}