import Foundation
import SwiftData

enum LocalPlayerSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Song.self]
    }

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
        var categoryName: String?

        init(
            contentHash: String,
            storageFileName: String,
            title: String,
            artist: String,
            durationSeconds: Double,
            artworkData: Data?,
            importedAt: Date,
            categoryName: String? = nil
        ) {
            self.id = UUID()
            self.contentHash = contentHash
            self.storageFileName = storageFileName
            self.title = title
            self.artist = artist
            self.durationSeconds = durationSeconds
            self.artworkData = artworkData
            self.importedAt = importedAt
            self.categoryName = categoryName
        }
    }
}

enum LocalPlayerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LocalPlayerSchemaV1.self, LocalPlayerSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1ToV2]
    }

    static let migrateV1ToV2 = MigrationStage.lightweight(
        fromVersion: LocalPlayerSchemaV1.self,
        toVersion: LocalPlayerSchemaV2.self
    )
}
