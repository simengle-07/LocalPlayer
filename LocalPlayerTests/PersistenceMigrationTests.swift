import Foundation
import SwiftData
import Testing

@testable import LocalPlayer

struct PersistenceMigrationTests {
    @Test
    func migratesExistingSongsToVersionTwoWithoutLosingTheirPrimaryCategory() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalPlayer-\(UUID().uuidString).store")

        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(
                atPath: "\(storeURL.path)-shm"
            )
            try? FileManager.default.removeItem(
                atPath: "\(storeURL.path)-wal"
            )
        }

        try Self.createVersionOneSongStore(at: storeURL)

        let v2Schema = Schema(versionedSchema: LocalPlayerSchemaV2.self)
        let v2Configuration = ModelConfiguration(schema: v2Schema, url: storeURL)
        let v2Container = try ModelContainer(
            for: v2Schema,
            migrationPlan: LocalPlayerMigrationPlan.self,
            configurations: v2Configuration
        )
        let migratedSongs = try ModelContext(v2Container).fetch(FetchDescriptor<Song>())

        #expect(migratedSongs.count == 1)
        #expect(migratedSongs.first?.title == "Legacy Song")
        #expect(migratedSongs.first?.categoryName == "日语音乐")
        #expect(migratedSongs.first?.subcategoryName == nil)
    }

    private static func createVersionOneSongStore(at storeURL: URL) throws {
        let v1Schema = Schema(versionedSchema: LocalPlayerSchemaV1.self)
        let v1Configuration = ModelConfiguration(schema: v1Schema, url: storeURL)
        let v1Container = try ModelContainer(
            for: v1Schema,
            configurations: v1Configuration
        )
        let v1Context = ModelContext(v1Container)
        v1Context.insert(
            LocalPlayerSchemaV1.Song(
                contentHash: "legacy-song",
                storageFileName: "legacy-song.mp3",
                title: "Legacy Song",
                artist: "Legacy Artist",
                durationSeconds: 120,
                artworkData: nil,
                importedAt: Date(timeIntervalSince1970: 0),
                categoryName: "日语音乐"
            )
        )
        try v1Context.save()
    }
}
